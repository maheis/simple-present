package storage

import (
	"database/sql"
	"fmt"
	"strings"

	_ "github.com/mattn/go-sqlite3"
)

type Store struct {
	db *sql.DB
}

func NewSQLite(path string) (*Store, error) {
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		return nil, err
	}
	s := &Store{db: db}
	if err := s.initSchema(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Store) initSchema() error {
	stmts := []string{
		`PRAGMA journal_mode = WAL;`,
		`PRAGMA foreign_keys = ON;`,
		`CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, created_at INTEGER, max_devices INTEGER DEFAULT 5, max_items INTEGER DEFAULT 10000, max_bytes INTEGER DEFAULT 10485760);`,
		`CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, account_id TEXT, name TEXT, created_at INTEGER, revoked INTEGER DEFAULT 0, token_version INTEGER DEFAULT 1, FOREIGN KEY(account_id) REFERENCES accounts(id));`,
		`CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, account_id TEXT, payload TEXT, modified_at INTEGER, tombstone INTEGER DEFAULT 0, origin_device_id TEXT, version INTEGER, FOREIGN KEY(account_id) REFERENCES accounts(id));`,
		`CREATE INDEX IF NOT EXISTS idx_devices_account_active ON devices(account_id, revoked);`,
		`CREATE INDEX IF NOT EXISTS idx_items_account_modified ON items(account_id, modified_at);`,
		`ALTER TABLE accounts ADD COLUMN max_devices INTEGER DEFAULT 5;`,
		`ALTER TABLE accounts ADD COLUMN max_items INTEGER DEFAULT 10000;`,
		`ALTER TABLE accounts ADD COLUMN max_bytes INTEGER DEFAULT 10485760;`,
		`ALTER TABLE devices ADD COLUMN revoked INTEGER DEFAULT 0;`,
		`ALTER TABLE devices ADD COLUMN token_version INTEGER DEFAULT 1;`,
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	for _, st := range stmts {
		if _, err := tx.Exec(st); err != nil {
			if strings.Contains(err.Error(), "duplicate column name") {
				continue
			}
			tx.Rollback()
			return fmt.Errorf("init schema: %w", err)
		}
	}
	return tx.Commit()
}

func (s *Store) Close() error {
	return s.db.Close()
}

func (s *Store) DB() *sql.DB {
	return s.db
}
