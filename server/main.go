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
	return &c, nil
}

func main() {
	cfgPath := flag.String("config", "config.json", "path to config.json")
	flag.Parse()
	cfg, err := loadConfig(*cfgPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	st, err := storage.NewSQLite(cfg.DatabasePath)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer st.Close()
	// reuse DB for handlers
	db := st.DB()
	srv := &handlers.Server{DB: db}

	r := mux.NewRouter()
	r.HandleFunc("/register", srv.Register).Methods("POST")
	r.HandleFunc("/pair", srv.Pair).Methods("POST")
	r.HandleFunc("/push", srv.Push).Methods("POST")
	r.HandleFunc("/pull", srv.Pull).Methods("GET")

	addr := cfg.Bind
	fmt.Printf("listening on %s\n", addr)
	if cfg.TLS.Enabled {
		log.Fatal(http.ListenAndServeTLS(addr, cfg.TLS.CertFile, cfg.TLS.KeyFile, r))
	} else {
		log.Fatal(http.ListenAndServe(addr, r))
	}
}
