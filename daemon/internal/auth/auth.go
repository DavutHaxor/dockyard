package auth

import (
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const issuer = "dockyard"

var (
	// ErrInvalidCredentials is returned when the admin token does not match.
	ErrInvalidCredentials = errors.New("invalid credentials")
	// ErrInvalidSession is returned when a JWT is missing, tampered with or expired.
	ErrInvalidSession = errors.New("invalid or expired session")
)

// Manager issues and verifies session tokens for the single admin user.
//
// The admin token is the long-lived secret configured on the server. Clients
// exchange it for a short-lived JWT, which is what every API request carries.
type Manager struct {
	adminToken []byte
	secret     []byte
	ttl        time.Duration
	now        func() time.Time
}

// New creates a Manager. Session tokens remain valid across restarts because
// the signing key is derived from the admin token.
func New(adminToken string, ttl time.Duration) *Manager {
	sum := sha256.Sum256([]byte("dockyard-session:" + adminToken))
	return &Manager{
		adminToken: []byte(adminToken),
		secret:     sum[:],
		ttl:        ttl,
		now:        time.Now,
	}
}

// Login exchanges the admin token for a signed session token.
func (m *Manager) Login(adminToken string) (string, time.Time, error) {
	if subtle.ConstantTimeCompare([]byte(adminToken), m.adminToken) != 1 {
		return "", time.Time{}, ErrInvalidCredentials
	}

	now := m.now().UTC()
	expiresAt := now.Add(m.ttl)
	claims := jwt.RegisteredClaims{
		Issuer:    issuer,
		Subject:   "admin",
		IssuedAt:  jwt.NewNumericDate(now),
		NotBefore: jwt.NewNumericDate(now.Add(-time.Minute)),
		ExpiresAt: jwt.NewNumericDate(expiresAt),
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.secret)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("sign session token: %w", err)
	}
	return signed, expiresAt, nil
}

// Verify checks the signature, issuer and expiry of a session token.
func (m *Manager) Verify(raw string) error {
	claims := &jwt.RegisteredClaims{}
	token, err := jwt.ParseWithClaims(
		raw,
		claims,
		func(token *jwt.Token) (any, error) {
			if token.Method != jwt.SigningMethodHS256 {
				return nil, ErrInvalidSession
			}
			return m.secret, nil
		},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(issuer),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(m.now),
	)
	if err != nil || !token.Valid {
		return ErrInvalidSession
	}
	return nil
}
