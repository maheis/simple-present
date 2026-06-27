package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/gorilla/mux"
	"github.com/simplepresent/server/handlers"
	"github.com/simplepresent/server/storage"
)

const ServerVersion = "0.1.0"

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
		AccountPolicy     struct {
			MaxAccounts          int    `json:"max_accounts"`
			AdminEmail           string `json:"admin_email"`
			ArchiveAfterDays     int    `json:"archive_after_days"`
			WarningDays          []int  `json:"warning_days"`
			SweepIntervalMinutes int    `json:"sweep_interval_minutes"`
			SMTP                 struct {
				Host     string `json:"host"`
				Port     int    `json:"port"`
				Username string `json:"username"`
				Password string `json:"password"`
				From     string `json:"from"`
			} `json:"smtp"`
		} `json:"account_policy"`
		RateLimit struct {
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
	readEnvString := func(key, current string) string {
		if v := strings.TrimSpace(os.Getenv(key)); v != "" {
			return v
		}
		return current
	}
	readEnvInt := func(key string, current int) int {
		if v := strings.TrimSpace(os.Getenv(key)); v != "" {
			if parsed, err := strconv.Atoi(v); err == nil {
				return parsed
			}
		}
		return current
	}
	readEnvInt64 := func(key string, current int64) int64 {
		if v := strings.TrimSpace(os.Getenv(key)); v != "" {
			if parsed, err := strconv.ParseInt(v, 10, 64); err == nil {
				return parsed
			}
		}
		return current
	}
	readEnvIntList := func(key string, fallback []int) []int {
		raw := strings.TrimSpace(os.Getenv(key))
		if raw == "" {
			return fallback
		}
		parts := strings.Split(raw, ",")
		out := make([]int, 0, len(parts))
		for _, p := range parts {
			p = strings.TrimSpace(p)
			if p == "" {
				continue
			}
			v, err := strconv.Atoi(p)
			if err == nil {
				out = append(out, v)
			}
		}
		if len(out) == 0 {
			return fallback
		}
		return out
	}

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
	c.Security.JWTSecret = readEnvString("SIMPLEPRESENT_JWT_SECRET", c.Security.JWTSecret)
	if c.Security.RateLimit.RequestsPerMinute == 0 {
		c.Security.RateLimit.RequestsPerMinute = 60
	}
	c.Security.RateLimit.RequestsPerMinute = readEnvInt(
		"SIMPLEPRESENT_RATE_LIMIT_RPM",
		c.Security.RateLimit.RequestsPerMinute,
	)
	if c.Security.RateLimit.Burst == 0 {
		c.Security.RateLimit.Burst = 20
	}
	c.Security.RateLimit.Burst = readEnvInt(
		"SIMPLEPRESENT_RATE_LIMIT_BURST",
		c.Security.RateLimit.Burst,
	)
	if c.Security.Quotas.MaxDevices == 0 {
		c.Security.Quotas.MaxDevices = 5
	}
	c.Security.Quotas.MaxDevices = readEnvInt(
		"SIMPLEPRESENT_QUOTA_MAX_DEVICES",
		c.Security.Quotas.MaxDevices,
	)
	if c.Security.Quotas.MaxItems == 0 {
		c.Security.Quotas.MaxItems = 10000
	}
	c.Security.Quotas.MaxItems = readEnvInt(
		"SIMPLEPRESENT_QUOTA_MAX_ITEMS",
		c.Security.Quotas.MaxItems,
	)
	if c.Security.Quotas.MaxBytesPerAccount == 0 {
		c.Security.Quotas.MaxBytesPerAccount = 10 * 1024 * 1024
	}
	c.Security.Quotas.MaxBytesPerAccount = readEnvInt64(
		"SIMPLEPRESENT_QUOTA_MAX_BYTES",
		c.Security.Quotas.MaxBytesPerAccount,
	)
	if c.Security.AccountPolicy.ArchiveAfterDays == 0 {
		c.Security.AccountPolicy.ArchiveAfterDays = 30
	}
	c.Security.AccountPolicy.ArchiveAfterDays = readEnvInt(
		"SIMPLEPRESENT_ARCHIVE_AFTER_DAYS",
		c.Security.AccountPolicy.ArchiveAfterDays,
	)
	if len(c.Security.AccountPolicy.WarningDays) == 0 {
		c.Security.AccountPolicy.WarningDays = []int{14, 7}
	}
	c.Security.AccountPolicy.WarningDays = readEnvIntList(
		"SIMPLEPRESENT_ARCHIVE_WARNING_DAYS",
		c.Security.AccountPolicy.WarningDays,
	)
	if c.Security.AccountPolicy.SweepIntervalMinutes == 0 {
		c.Security.AccountPolicy.SweepIntervalMinutes = 60
	}
	c.Security.AccountPolicy.SweepIntervalMinutes = readEnvInt(
		"SIMPLEPRESENT_SWEEP_INTERVAL_MINUTES",
		c.Security.AccountPolicy.SweepIntervalMinutes,
	)
	c.Security.AccountPolicy.MaxAccounts = readEnvInt(
		"SIMPLEPRESENT_MAX_ACCOUNTS",
		c.Security.AccountPolicy.MaxAccounts,
	)
	c.Security.AccountPolicy.AdminEmail = readEnvString(
		"SIMPLEPRESENT_ADMIN_EMAIL",
		c.Security.AccountPolicy.AdminEmail,
	)
	c.Security.AccountPolicy.SMTP.Host = readEnvString(
		"SIMPLEPRESENT_SMTP_HOST",
		c.Security.AccountPolicy.SMTP.Host,
	)
	c.Security.AccountPolicy.SMTP.Port = readEnvInt(
		"SIMPLEPRESENT_SMTP_PORT",
		c.Security.AccountPolicy.SMTP.Port,
	)
	c.Security.AccountPolicy.SMTP.Username = readEnvString(
		"SIMPLEPRESENT_SMTP_USERNAME",
		c.Security.AccountPolicy.SMTP.Username,
	)
	c.Security.AccountPolicy.SMTP.Password = readEnvString(
		"SIMPLEPRESENT_SMTP_PASSWORD",
		c.Security.AccountPolicy.SMTP.Password,
	)
	c.Security.AccountPolicy.SMTP.From = readEnvString(
		"SIMPLEPRESENT_SMTP_FROM",
		c.Security.AccountPolicy.SMTP.From,
	)
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
		AccountPolicy: handlers.AccountPolicy{
			MaxAccounts:          cfg.Security.AccountPolicy.MaxAccounts,
			AdminEmail:           cfg.Security.AccountPolicy.AdminEmail,
			ArchiveAfterDays:     cfg.Security.AccountPolicy.ArchiveAfterDays,
			WarningDays:          handlers.NormalizeWarningDays(cfg.Security.AccountPolicy.WarningDays),
			SweepIntervalMinutes: cfg.Security.AccountPolicy.SweepIntervalMinutes,
			SMTP: handlers.SMTPConfig{
				Host:     cfg.Security.AccountPolicy.SMTP.Host,
				Port:     cfg.Security.AccountPolicy.SMTP.Port,
				Username: cfg.Security.AccountPolicy.SMTP.Username,
				Password: cfg.Security.AccountPolicy.SMTP.Password,
				From:     cfg.Security.AccountPolicy.SMTP.From,
			},
		},
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
	r.Handle("/devices", srv.SecureOnly(srv.RateLimitByIP(srv.AuthMiddleware(http.HandlerFunc(srv.DevicesList))))).Methods("GET")
	r.Handle("/account/status", srv.SecureOnly(srv.RateLimitByIP(srv.AuthMiddleware(http.HandlerFunc(srv.AccountStatus))))).Methods("GET")
	r.Handle("/devices/{id}/revoke", srv.SecureOnly(srv.RateLimitByIP(srv.AuthMiddleware(http.HandlerFunc(srv.RevokeDevice))))).Methods("POST")
	r.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"version": ServerVersion, "status": "ok"})
	}).Methods("GET")

	addr := cfg.Bind
	srv.StartMaintenanceLoop()
	fmt.Printf("listening on %s\n", addr)
	if cfg.TLS.Enabled {
		log.Fatal(http.ListenAndServeTLS(addr, cfg.TLS.CertFile, cfg.TLS.KeyFile, r))
	} else {
		log.Fatal(http.ListenAndServe(addr, r))
	}
}
