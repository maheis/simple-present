package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/gorilla/mux"
	"github.com/simplepresent/server/handlers"
	"github.com/simplepresent/server/storage"
)

type Config struct {
	Bind         string `json:"bind"`
	DatabasePath string `json:"database_path"`
	TLS          struct {
		Enabled  bool   `json:"enabled"`
		CertFile string `json:"cert_file"`
		KeyFile  string `json:"key_file"`
	} `json:"tls"`
	Security struct {
		RequireTLS        bool   `json:"require_tls"`
		TrustProxyHeaders bool   `json:"trust_proxy_headers"`
		JWTSecret         string `json:"jwt_secret"`
		RateLimit         struct {
			RequestsPerMinute int `json:"requests_per_minute"`
			Burst             int `json:"burst"`
		} `json:"rate_limit"`
		Quotas struct {
			MaxDevices         int   `json:"max_devices"`
			MaxItems           int   `json:"max_items"`
			MaxBytesPerAccount int64 `json:"max_bytes_per_account"`
		} `json:"quotas"`
	} `json:"security"`
}

func loadConfig(path string) (*Config, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var c Config
	if err := json.NewDecoder(f).Decode(&c); err != nil {
		return nil, err
	}
	if c.Security.RequireTLS == false {
		// keep explicit false if user set it; defaults are applied below only when values are empty
	}
	if c.Security.JWTSecret == "" {
		c.Security.JWTSecret = os.Getenv("SIMPLEPRESENT_JWT_SECRET")
	}
	if c.Security.RateLimit.RequestsPerMinute == 0 {
		c.Security.RateLimit.RequestsPerMinute = 60
	}
	if c.Security.RateLimit.Burst == 0 {
		c.Security.RateLimit.Burst = 20
	}
	if c.Security.Quotas.MaxDevices == 0 {
		c.Security.Quotas.MaxDevices = 5
	}
	if c.Security.Quotas.MaxItems == 0 {
		c.Security.Quotas.MaxItems = 10000
	}
	if c.Security.Quotas.MaxBytesPerAccount == 0 {
		c.Security.Quotas.MaxBytesPerAccount = 10 * 1024 * 1024
	}
	if !c.TLS.Enabled && c.Security.RequireTLS == false {
		// explicit insecure local mode remains possible
	} else if !c.TLS.Enabled && c.Security.RequireTLS == false {
	}
	return &c, nil
}

func main() {
	cfgPath := flag.String("config", "config.json", "path to config.json")
	flag.Parse()
	cfg, err := loadConfig(*cfgPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	if cfg.Security.JWTSecret == "" {
		log.Fatal("security.jwt_secret is required")
	}
	st, err := storage.NewSQLite(cfg.DatabasePath)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer st.Close()
	// reuse DB for handlers
	db := st.DB()
	srv := &handlers.Server{
		DB:                db,
		JWTSecret:         []byte(cfg.Security.JWTSecret),
		RequireTLS:        cfg.Security.RequireTLS,
		TrustProxyHeaders: cfg.Security.TrustProxyHeaders,
		DefaultQuotas: handlers.Quotas{
			MaxDevices:         cfg.Security.Quotas.MaxDevices,
			MaxItems:           cfg.Security.Quotas.MaxItems,
			MaxBytesPerAccount: cfg.Security.Quotas.MaxBytesPerAccount,
		},
		IPLimiters:      handlers.NewIPLimiters(cfg.Security.RateLimit.RequestsPerMinute, cfg.Security.RateLimit.Burst),
		AccountLimiters: handlers.NewAccountLimiters(cfg.Security.RateLimit.RequestsPerMinute, cfg.Security.RateLimit.Burst),
	}

	r := mux.NewRouter()
	r.Handle("/register", srv.SecureOnly(srv.RateLimitByIP(http.HandlerFunc(srv.Register)))).Methods("POST")
	r.Handle("/pair/challenge", srv.SecureOnly(srv.RateLimitByIP(http.HandlerFunc(srv.PairChallenge)))).Methods("POST")
	r.Handle("/pair", srv.SecureOnly(srv.RateLimitByIP(http.HandlerFunc(srv.Pair)))).Methods("POST")
	r.Handle("/push", srv.SecureOnly(srv.RateLimitByIP(srv.AuthMiddleware(http.HandlerFunc(srv.Push))))).Methods("POST")
	r.Handle("/pull", srv.SecureOnly(srv.RateLimitByIP(srv.AuthMiddleware(http.HandlerFunc(srv.Pull))))).Methods("GET")
	r.Handle("/devices/{id}/revoke", srv.SecureOnly(srv.RateLimitByIP(srv.AuthMiddleware(http.HandlerFunc(srv.RevokeDevice))))).Methods("POST")

	addr := cfg.Bind
	fmt.Printf("listening on %s\n", addr)
	if cfg.TLS.Enabled {
		log.Fatal(http.ListenAndServeTLS(addr, cfg.TLS.CertFile, cfg.TLS.KeyFile, r))
	} else {
		log.Fatal(http.ListenAndServe(addr, r))
	}
}
