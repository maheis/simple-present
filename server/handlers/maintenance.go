package handlers

import (
	"database/sql"
	"fmt"
	"log"
	"net/smtp"
	"sort"
	"strconv"
	"strings"
	"time"
)

type SMTPConfig struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
}

type AccountPolicy struct {
	MaxAccounts          int
	AdminEmail           string
	ArchiveAfterDays     int
	WarningDays          []int
	SweepIntervalMinutes int
	SMTP                 SMTPConfig
}

func NormalizeWarningDays(days []int) []int {
	if len(days) == 0 {
		return []int{14, 7}
	}
	set := make(map[int]struct{})
	for _, d := range days {
		if d > 0 {
			set[d] = struct{}{}
		}
	}
	out := make([]int, 0, len(set))
	for d := range set {
		out = append(out, d)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(out)))
	if len(out) == 0 {
		return []int{14, 7}
	}
	return out
}

func (s *Server) activeAccountCount() (int, error) {
	var count int
	err := s.DB.QueryRow("SELECT COUNT(*) FROM accounts WHERE archived = 0").Scan(&count)
	return count, err
}

func (s *Server) checkRegistrationCapacity() error {
	if s.AccountPolicy.MaxAccounts <= 0 {
		return nil
	}
	count, err := s.activeAccountCount()
	if err != nil {
		return err
	}
	if count >= s.AccountPolicy.MaxAccounts {
		return fmt.Errorf("account capacity exceeded")
	}
	return nil
}

func (s *Server) touchAccountActivity(accountID string) {
	if accountID == "" {
		return
	}
	_, _ = s.DB.Exec(
		"UPDATE accounts SET last_active_at = ? WHERE id = ? AND archived = 0",
		time.Now().Unix(),
		accountID,
	)
}

func (s *Server) archiveInactiveAccounts(now time.Time) (int64, error) {
	if s.AccountPolicy.ArchiveAfterDays <= 0 {
		return 0, nil
	}
	cutoff := now.Add(-time.Duration(s.AccountPolicy.ArchiveAfterDays) * 24 * time.Hour).Unix()
	result, err := s.DB.Exec(
		"UPDATE accounts SET archived = 1, archived_at = ? WHERE archived = 0 AND last_active_at > 0 AND last_active_at < ?",
		now.Unix(),
		cutoff,
	)
	if err != nil {
		return 0, err
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return 0, err
	}
	if rows > 0 {
		_, _ = s.DB.Exec(
			"UPDATE devices SET revoked = 1, token_version = token_version + 1 WHERE account_id IN (SELECT id FROM accounts WHERE archived = 1 AND archived_at = ?)",
			now.Unix(),
		)
	}
	return rows, nil
}

func (s *Server) alertThresholdStateKey(threshold int) string {
	return fmt.Sprintf("capacity_alert_%d_of_%d", threshold, s.AccountPolicy.MaxAccounts)
}

func (s *Server) hasCapacityAlertBeenSent(threshold int) (bool, error) {
	key := s.alertThresholdStateKey(threshold)
	var value string
	err := s.DB.QueryRow("SELECT value FROM system_state WHERE key = ?", key).Scan(&value)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	return value == "sent", nil
}

func (s *Server) markCapacityAlertSent(threshold int) error {
	key := s.alertThresholdStateKey(threshold)
	_, err := s.DB.Exec(
		"INSERT INTO system_state(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
		key,
		"sent",
	)
	return err
}

func (s *Server) maybeSendCapacityAlerts() {
	if s.AccountPolicy.MaxAccounts <= 0 || s.AccountPolicy.AdminEmail == "" {
		return
	}
	count, err := s.activeAccountCount()
	if err != nil {
		log.Printf("capacity count failed: %v", err)
		return
	}
	percent := (count * 100) / s.AccountPolicy.MaxAccounts
	for _, threshold := range []int{75, 90, 100} {
		if percent < threshold {
			continue
		}
		sent, err := s.hasCapacityAlertBeenSent(threshold)
		if err != nil {
			log.Printf("capacity alert state failed: %v", err)
			continue
		}
		if sent {
			continue
		}
		subject := fmt.Sprintf("[SimplePresent] Account capacity reached %d%%", threshold)
		body := fmt.Sprintf("Current active accounts: %d/%d (%d%%).", count, s.AccountPolicy.MaxAccounts, percent)
		if err := s.sendAdminMail(subject, body); err != nil {
			log.Printf("capacity alert mail failed: %v", err)
			continue
		}
		if err := s.markCapacityAlertSent(threshold); err != nil {
			log.Printf("mark capacity alert failed: %v", err)
		}
	}
}

func (s *Server) sendAdminMail(subject, body string) error {
	if s.AccountPolicy.AdminEmail == "" {
		return nil
	}
	if s.AccountPolicy.SMTP.Host == "" || s.AccountPolicy.SMTP.Port <= 0 {
		log.Printf("admin email configured without SMTP host/port, message: %s", subject)
		return nil
	}

	from := s.AccountPolicy.SMTP.From
	if from == "" {
		from = s.AccountPolicy.AdminEmail
	}

	addr := fmt.Sprintf("%s:%d", s.AccountPolicy.SMTP.Host, s.AccountPolicy.SMTP.Port)
	host := s.AccountPolicy.SMTP.Host
	var auth smtp.Auth
	if s.AccountPolicy.SMTP.Username != "" {
		auth = smtp.PlainAuth("", s.AccountPolicy.SMTP.Username, s.AccountPolicy.SMTP.Password, host)
	}

	msg := strings.Join([]string{
		"From: " + from,
		"To: " + s.AccountPolicy.AdminEmail,
		"Subject: " + subject,
		"",
		body,
	}, "\r\n")

	return smtp.SendMail(addr, auth, from, []string{s.AccountPolicy.AdminEmail}, []byte(msg))
}

func (s *Server) accountStatus(accountID string) (map[string]interface{}, error) {
	var lastActiveAt int64
	var archived int
	err := s.DB.QueryRow("SELECT last_active_at, archived FROM accounts WHERE id = ?", accountID).Scan(&lastActiveAt, &archived)
	if err != nil {
		return nil, err
	}

	now := time.Now().Unix()
	daysUntilArchive := -1
	warning := false
	if archived != 0 {
		daysUntilArchive = 0
	} else if s.AccountPolicy.ArchiveAfterDays > 0 {
		remaining := int((lastActiveAt + int64(s.AccountPolicy.ArchiveAfterDays*24*3600) - now) / (24 * 3600))
		if remaining < 0 {
			remaining = 0
		}
		daysUntilArchive = remaining
		for _, d := range s.AccountPolicy.WarningDays {
			if remaining <= d {
				warning = true
				break
			}
		}
	}

	return map[string]interface{}{
		"archived":           archived != 0,
		"last_active_at":     lastActiveAt,
		"archive_after_days": s.AccountPolicy.ArchiveAfterDays,
		"warning_days":       s.AccountPolicy.WarningDays,
		"days_until_archive": daysUntilArchive,
		"warning":            warning,
	}, nil
}

func (s *Server) registrationNotice() string {
	if s.AccountPolicy.ArchiveAfterDays <= 0 {
		return ""
	}
	warnParts := make([]string, 0, len(s.AccountPolicy.WarningDays))
	for _, d := range s.AccountPolicy.WarningDays {
		warnParts = append(warnParts, strconv.Itoa(d))
	}
	return fmt.Sprintf(
		"Hinweis: Dieser Account wird nach %d Tagen Inaktivität archiviert. Warnungen erfolgen %s Tage vorher.",
		s.AccountPolicy.ArchiveAfterDays,
		strings.Join(warnParts, "/"),
	)
}

func (s *Server) StartMaintenanceLoop() {
	interval := s.AccountPolicy.SweepIntervalMinutes
	if interval <= 0 {
		interval = 60
	}
	ticker := time.NewTicker(time.Duration(interval) * time.Minute)
	go func() {
		for range ticker.C {
			archived, err := s.archiveInactiveAccounts(time.Now())
			if err != nil {
				log.Printf("archive sweep failed: %v", err)
				continue
			}
			if archived > 0 {
				log.Printf("archived %d inactive accounts", archived)
			}

			// Clean up old redo items to avoid unbounded growth. Default TTL: 30 days.
			cleaned, err := s.cleanupRedoItems(time.Now())
			if err != nil {
				log.Printf("redo cleanup failed: %v", err)
			} else if cleaned > 0 {
				log.Printf("deleted %d old redo items", cleaned)
			}
		}
	}()
}

func (s *Server) cleanupRedoItems(now time.Time) (int64, error) {
	ttl := 30 * 24 * time.Hour
	cutoff := now.Add(-ttl).Unix()
	result, err := s.DB.Exec("DELETE FROM redo_items WHERE modified_at < ?", cutoff)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected()
}
