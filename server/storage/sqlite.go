package storage

import (
	"database/sql"
	"fmt"

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
		`CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, created_at INTEGER);`,
		`CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, account_id TEXT, name TEXT, created_at INTEGER, FOREIGN KEY(account_id) REFERENCES accounts(id));`,
		`CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, account_id TEXT, payload TEXT, modified_at INTEGER, tombstone INTEGER DEFAULT 0, origin_device_id TEXT, version INTEGER, FOREIGN KEY(account_id) REFERENCES accounts(id));`,
		`CREATE INDEX IF NOT EXISTS idx_items_account_modified ON items(account_id, modified_at);`,
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	for _, st := range stmts {
		if _, err := tx.Exec(st); err != nil {
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
