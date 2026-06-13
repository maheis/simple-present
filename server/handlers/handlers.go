package handlers

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
)

type Server struct {
	DB                *sql.DB
	JWTSecret         []byte
	RequireTLS        bool
	TrustProxyHeaders bool
	DefaultQuotas     Quotas
	IPLimiters        *limiterStore
	AccountLimiters   *limiterStore
}

func writeJSON(w http.ResponseWriter, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func (s *Server) Register(w http.ResponseWriter, r *http.Request) {
	id := uuid.New().String()
	now := time.Now().Unix()
	_, err := s.DB.Exec(
		"INSERT INTO accounts (id, created_at, max_devices, max_items, max_bytes) VALUES (?, ?, ?, ?, ?)",
		id,
		now,
		s.DefaultQuotas.MaxDevices,
		s.DefaultQuotas.MaxItems,
		s.DefaultQuotas.MaxBytesPerAccount,
	)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]string{"account_id": id})
}

func (s *Server) Pair(w http.ResponseWriter, r *http.Request) {
	var req struct {
		AccountID string `json:"account_id"`
		Name      string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	if req.AccountID == "" || req.Name == "" {
		http.Error(w, "account_id and name are required", http.StatusBadRequest)
		return
	}

	var maxDevices int
	err := s.DB.QueryRow("SELECT max_devices FROM accounts WHERE id = ?", req.AccountID).Scan(&maxDevices)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			http.Error(w, "unknown account", http.StatusNotFound)
			return
		}
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	var activeDevices int
	err = s.DB.QueryRow("SELECT COUNT(*) FROM devices WHERE account_id = ? AND revoked = 0", req.AccountID).Scan(&activeDevices)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if activeDevices >= maxDevices {
		http.Error(w, "device quota exceeded", http.StatusForbidden)
		return
	}

	id := uuid.New().String()
	now := time.Now().Unix()
	_, err = s.DB.Exec(
		"INSERT INTO devices (id, account_id, name, created_at, revoked, token_version) VALUES (?, ?, ?, ?, 0, 1)",
		id,
		req.AccountID,
		req.Name,
		now,
	)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	token, err := s.issueToken(req.AccountID, id, 1)
	if err != nil {
		http.Error(w, "token issue failed", http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]string{"device_id": id, "token": token})
}

func (s *Server) Pull(w http.ResponseWriter, r *http.Request) {
	auth, ok := authFromContext(r.Context())
	if !ok {
		http.Error(w, "missing auth context", http.StatusUnauthorized)
		return
	}
	since := r.URL.Query().Get("since")
	var sinceInt int64
	if since != "" {
		if parsed, err := json.Number(since).Int64(); err == nil {
			sinceInt = parsed
		}
	}
	rows, err := s.DB.Query("SELECT id, payload, modified_at, tombstone, origin_device_id, version FROM items WHERE account_id = ? AND modified_at > ?", auth.AccountID, sinceInt)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	var out []map[string]interface{}
	for rows.Next() {
		var id, payload, origin string
		var modified int64
		var tomb int
		var version int
		if err := rows.Scan(&id, &payload, &modified, &tomb, &origin, &version); err != nil {
			continue
		}
		var payloadObj interface{}
		json.Unmarshal([]byte(payload), &payloadObj)
		out = append(out, map[string]interface{}{"id": id, "payload": payloadObj, "modified_at": modified, "tombstone": tomb, "origin_device_id": origin, "version": version})
	}
	writeJSON(w, map[string]interface{}{"items": out})
}

func (s *Server) Push(w http.ResponseWriter, r *http.Request) {
	auth, ok := authFromContext(r.Context())
	if !ok {
		http.Error(w, "missing auth context", http.StatusUnauthorized)
		return
	}

	var req struct {
		AccountID string `json:"account_id"`
		Items     []struct {
			ID             string      `json:"id"`
			Payload        interface{} `json:"payload"`
			ModifiedAt     int64       `json:"modified_at"`
			Tombstone      bool        `json:"tombstone"`
			OriginDeviceID string      `json:"origin_device_id"`
			Version        int         `json:"version"`
		} `json:"items"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	if req.AccountID != "" && req.AccountID != auth.AccountID {
		http.Error(w, "account mismatch", http.StatusForbidden)
		return
	}
	req.AccountID = auth.AccountID

	tx, err := s.DB.Begin()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	stmt, err := tx.Prepare("INSERT OR REPLACE INTO items (id, account_id, payload, modified_at, tombstone, origin_device_id, version) VALUES (?, ?, ?, ?, ?, ?, ?)")
	if err != nil {
		tx.Rollback()
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer stmt.Close()
	for _, it := range req.Items {
		b, _ := json.Marshal(it.Payload)
		tomb := 0
		if it.Tombstone {
			tomb = 1
		}
		if _, err := stmt.Exec(it.ID, req.AccountID, string(b), it.ModifiedAt, tomb, it.OriginDeviceID, it.Version); err != nil {
			tx.Rollback()
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	}
	if err := s.enforceAccountQuota(tx, req.AccountID); err != nil {
		tx.Rollback()
		http.Error(w, err.Error(), http.StatusForbidden)
		return
	}
	if err := tx.Commit(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]string{"status": "ok"})
}

func (s *Server) RevokeDevice(w http.ResponseWriter, r *http.Request) {
	auth, ok := authFromContext(r.Context())
	if !ok {
		http.Error(w, "missing auth context", http.StatusUnauthorized)
		return
	}
	deviceID := mux.Vars(r)["id"]
	if deviceID == "" {
		http.Error(w, "missing device id", http.StatusBadRequest)
		return
	}
	result, err := s.DB.Exec(
		"UPDATE devices SET revoked = 1, token_version = token_version + 1 WHERE id = ? AND account_id = ? AND revoked = 0",
		deviceID,
		auth.AccountID,
	)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	rows, err := result.RowsAffected()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if rows == 0 {
		http.Error(w, "device not found", http.StatusNotFound)
		return
	}
	writeJSON(w, map[string]string{"status": "revoked"})
}

func (s *Server) enforceAccountQuota(tx *sql.Tx, accountID string) error {
	var maxItems int
	var maxBytes int64
	err := tx.QueryRow("SELECT max_items, max_bytes FROM accounts WHERE id = ?", accountID).Scan(&maxItems, &maxBytes)
	if err != nil {
		return err
	}

	var itemCount int
	var totalBytes sql.NullInt64
	err = tx.QueryRow(
		"SELECT COUNT(*), COALESCE(SUM(LENGTH(payload)), 0) FROM items WHERE account_id = ? AND tombstone = 0",
		accountID,
	).Scan(&itemCount, &totalBytes)
	if err != nil {
		return err
	}
	if itemCount > maxItems {
		return errors.New("item quota exceeded")
	}
	if totalBytes.Int64 > maxBytes {
		return errors.New("storage quota exceeded")
	}
	return nil
}
