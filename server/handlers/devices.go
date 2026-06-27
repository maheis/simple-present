package handlers

import (
	"net/http"
)

// DevicesList returns all devices for the authenticated account.
func (s *Server) DevicesList(w http.ResponseWriter, r *http.Request) {
	auth, ok := authFromContext(r.Context())
	if !ok {
		http.Error(w, "missing auth context", http.StatusUnauthorized)
		return
	}

	rows, err := s.DB.Query("SELECT id, name, created_at, revoked, token_version FROM devices WHERE account_id = ?", auth.AccountID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var out []map[string]interface{}
	for rows.Next() {
		var id, name string
		var created int64
		var revoked int
		var tokenVersion int
		if err := rows.Scan(&id, &name, &created, &revoked, &tokenVersion); err != nil {
			continue
		}
		out = append(out, map[string]interface{}{
			"id":            id,
			"name":          name,
			"created_at":    created,
			"revoked":       revoked == 1,
			"token_version": tokenVersion,
		})
	}

	s.touchAccountActivity(auth.AccountID)
	writeJSON(w, map[string]interface{}{"devices": out})
}
