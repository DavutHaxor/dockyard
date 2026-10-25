package auth

import (
	"errors"
	"testing"
	"time"
)

const adminToken = "correct-admin-token-123456"

func TestLoginAndVerify(t *testing.T) {
	base := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	manager := New(adminToken, time.Hour)
	manager.now = func() time.Time { return base }

	session, expiresAt, err := manager.Login(adminToken)
	if err != nil {
		t.Fatalf("Login() error = %v", err)
	}
	if session == "" {
		t.Fatal("Login() returned an empty session token")
	}
	if want := base.Add(time.Hour); !expiresAt.Equal(want) {
		t.Errorf("expiresAt = %v, want %v", expiresAt, want)
	}
	if err := manager.Verify(session); err != nil {
		t.Errorf("Verify() error = %v", err)
	}
}

func TestLoginRejectsWrongToken(t *testing.T) {
	manager := New(adminToken, time.Hour)
	if _, _, err := manager.Login("wrong-token"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("Login() error = %v, want ErrInvalidCredentials", err)
	}
}

func TestVerifyRejectsExpiredSession(t *testing.T) {
	base := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	manager := New(adminToken, time.Minute)
	manager.now = func() time.Time { return base }

	session, _, err := manager.Login(adminToken)
	if err != nil {
		t.Fatalf("Login() error = %v", err)
	}

	manager.now = func() time.Time { return base.Add(2 * time.Minute) }
	if err := manager.Verify(session); !errors.Is(err, ErrInvalidSession) {
		t.Fatalf("Verify() error = %v, want ErrInvalidSession", err)
	}
}

func TestVerifyRejectsGarbage(t *testing.T) {
	manager := New(adminToken, time.Hour)
	for _, token := range []string{"", "not-a-jwt", adminToken} {
		if err := manager.Verify(token); !errors.Is(err, ErrInvalidSession) {
			t.Errorf("Verify(%q) error = %v, want ErrInvalidSession", token, err)
		}
	}
}
