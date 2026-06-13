package handlers

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/time/rate"
)

type Quotas struct {
	MaxDevices         int
	MaxItems           int
	MaxBytesPerAccount int64
}

type AuthInfo struct {
	AccountID    string
	DeviceID     string
	TokenVersion int
}

type AuthClaims struct {
	AccountID    string `json:"account_id"`
	DeviceID     string `json:"device_id"`
	TokenVersion int    `json:"token_version"`
	jwt.RegisteredClaims
}

type contextKey string

const authContextKey contextKey = "auth"

type limiterStore struct {
	mu       sync.Mutex
	limit    rate.Limit
	burst    int
	limiters map[string]*rate.Limiter
}

func newLimiterStore(requestsPerMinute, burst int) *limiterStore {
	if requestsPerMinute <= 0 {
		requestsPerMinute = 60
	}
	if burst <= 0 {
		burst = 20
	}
	return &limiterStore{
		limit:    rate.Every(time.Minute / time.Duration(requestsPerMinute)),
		burst:    burst,
		limiters: make(map[string]*rate.Limiter),
	}
}

func NewIPLimiters(requestsPerMinute, burst int) *limiterStore {
	return newLimiterStore(requestsPerMinute, burst)
}

func NewAccountLimiters(requestsPerMinute, burst int) *limiterStore {
	return newLimiterStore(requestsPerMinute, burst)
}

func (s *limiterStore) get(key string) *rate.Limiter {
	s.mu.Lock()
	defer s.mu.Unlock()
	limiter, ok := s.limiters[key]
	if !ok {
		limiter = rate.NewLimiter(s.limit, s.burst)
		s.limiters[key] = limiter
	}
	return limiter
}

func (s *Server) SecureOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.RequireTLS {
			next.ServeHTTP(w, r)
			return
		}
		if r.TLS != nil {
			next.ServeHTTP(w, r)
			return
		}
		if s.TrustProxyHeaders && strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
			next.ServeHTTP(w, r)
			return
		}
		http.Error(w, "https required", http.StatusUpgradeRequired)
	})
}

func (s *Server) RateLimitByIP(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		key := "ip:" + s.clientIP(r)
		if !s.IPLimiters.get(key).Allow() {
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			http.Error(w, "missing bearer token", http.StatusUnauthorized)
			return
		}

		claims, err := s.parseToken(strings.TrimPrefix(header, "Bearer "))
		if err != nil {
			http.Error(w, "invalid token", http.StatusUnauthorized)
			return
		}

		var revoked int
		var tokenVersion int
		err = s.DB.QueryRow(
			"SELECT revoked, token_version FROM devices WHERE id = ? AND account_id = ?",
			claims.DeviceID,
			claims.AccountID,
		).Scan(&revoked, &tokenVersion)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				http.Error(w, "unknown device", http.StatusUnauthorized)
				return
			}
			http.Error(w, "auth lookup failed", http.StatusInternalServerError)
			return
		}
		if revoked != 0 || tokenVersion != claims.TokenVersion {
			http.Error(w, "device revoked", http.StatusUnauthorized)
			return
		}

		accountKey := "account:" + claims.AccountID
		if !s.AccountLimiters.get(accountKey).Allow() {
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}

		ctx := context.WithValue(r.Context(), authContextKey, AuthInfo{
			AccountID:    claims.AccountID,
			DeviceID:     claims.DeviceID,
			TokenVersion: claims.TokenVersion,
		})
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *Server) issueToken(accountID, deviceID string, tokenVersion int) (string, error) {
	now := time.Now()
	claims := AuthClaims{
		AccountID:    accountID,
		DeviceID:     deviceID,
		TokenVersion: tokenVersion,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(30 * 24 * time.Hour)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.JWTSecret)
}

func (s *Server) parseToken(tokenString string) (*AuthClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &AuthClaims{}, func(token *jwt.Token) (interface{}, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return s.JWTSecret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*AuthClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid claims")
	}
	return claims, nil
}

func authFromContext(ctx context.Context) (AuthInfo, bool) {
	info, ok := ctx.Value(authContextKey).(AuthInfo)
	return info, ok
}

func (s *Server) clientIP(r *http.Request) string {
	if s.TrustProxyHeaders {
		forwardedFor := r.Header.Get("X-Forwarded-For")
		if forwardedFor != "" {
			parts := strings.Split(forwardedFor, ",")
			return strings.TrimSpace(parts[0])
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
