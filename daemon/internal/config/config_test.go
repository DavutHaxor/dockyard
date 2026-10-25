package config

import (
	"testing"
	"time"
)

func clearEnv(t *testing.T) {
	t.Helper()
	for _, key := range []string{
		"DOCKYARD_ADDR",
		"DOCKYARD_ADMIN_TOKEN",
		"DOCKYARD_DOCKER_HOST",
		"DOCKER_HOST",
		"DOCKYARD_PROC_PATH",
		"DOCKYARD_DISK_PATH",
		"DOCKYARD_ALLOWED_ORIGINS",
		"DOCKYARD_TOKEN_TTL",
		"DOCKYARD_METRICS_INTERVAL",
		"DOCKYARD_CONTAINER_POLL_INTERVAL",
		"DOCKYARD_SHUTDOWN_TIMEOUT",
		"DOCKYARD_HISTORY_SIZE",
	} {
		t.Setenv(key, "")
	}
}

func TestLoadDefaults(t *testing.T) {
	clearEnv(t)
	t.Setenv("DOCKYARD_ADMIN_TOKEN", "0123456789abcdef")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Addr != ":8080" {
		t.Errorf("Addr = %q, want :8080", cfg.Addr)
	}
	if cfg.DockerHost != "unix:///var/run/docker.sock" {
		t.Errorf("DockerHost = %q", cfg.DockerHost)
	}
	if cfg.TokenTTL != 12*time.Hour {
		t.Errorf("TokenTTL = %v", cfg.TokenTTL)
	}
	if cfg.MetricsInterval != 2*time.Second {
		t.Errorf("MetricsInterval = %v", cfg.MetricsInterval)
	}
	if cfg.HistorySize != 150 {
		t.Errorf("HistorySize = %d", cfg.HistorySize)
	}
}

func TestLoadOverrides(t *testing.T) {
	clearEnv(t)
	t.Setenv("DOCKYARD_ADMIN_TOKEN", "0123456789abcdef")
	t.Setenv("DOCKYARD_ADDR", "127.0.0.1:9000")
	t.Setenv("DOCKYARD_DOCKER_HOST", "tcp://127.0.0.1:2375")
	t.Setenv("DOCKYARD_PROC_PATH", "/host/proc")
	t.Setenv("DOCKYARD_DISK_PATH", "/host")
	t.Setenv("DOCKYARD_TOKEN_TTL", "1h")
	t.Setenv("DOCKYARD_METRICS_INTERVAL", "500ms")
	t.Setenv("DOCKYARD_HISTORY_SIZE", "60")
	t.Setenv("DOCKYARD_ALLOWED_ORIGINS", "http://localhost:3000, https://dockyard.lan")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Addr != "127.0.0.1:9000" || cfg.DockerHost != "tcp://127.0.0.1:2375" {
		t.Errorf("unexpected addr/docker host: %+v", cfg)
	}
	if cfg.TokenTTL != time.Hour || cfg.MetricsInterval != 500*time.Millisecond {
		t.Errorf("unexpected durations: %+v", cfg)
	}
	if len(cfg.AllowedOrigins) != 2 || cfg.AllowedOrigins[1] != "https://dockyard.lan" {
		t.Errorf("AllowedOrigins = %v", cfg.AllowedOrigins)
	}
}

func TestLoadUsesDockerHostEnv(t *testing.T) {
	clearEnv(t)
	t.Setenv("DOCKYARD_ADMIN_TOKEN", "0123456789abcdef")
	t.Setenv("DOCKER_HOST", "unix:///run/user/1000/docker.sock")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.DockerHost != "unix:///run/user/1000/docker.sock" {
		t.Errorf("DockerHost = %q", cfg.DockerHost)
	}
}

func TestLoadValidation(t *testing.T) {
	tests := []struct {
		name  string
		setup func(t *testing.T)
	}{
		{"missing token", func(t *testing.T) {}},
		{"short token", func(t *testing.T) { t.Setenv("DOCKYARD_ADMIN_TOKEN", "short") }},
		{"bad interval", func(t *testing.T) {
			t.Setenv("DOCKYARD_ADMIN_TOKEN", "0123456789abcdef")
			t.Setenv("DOCKYARD_METRICS_INTERVAL", "10ms")
		}},
		{"bad addr", func(t *testing.T) {
			t.Setenv("DOCKYARD_ADMIN_TOKEN", "0123456789abcdef")
			t.Setenv("DOCKYARD_ADDR", "8080")
		}},
		{"bad docker host", func(t *testing.T) {
			t.Setenv("DOCKYARD_ADMIN_TOKEN", "0123456789abcdef")
			t.Setenv("DOCKYARD_DOCKER_HOST", "ssh://server")
		}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			clearEnv(t)
			tt.setup(t)
			if _, err := Load(); err == nil {
				t.Fatal("Load() error = nil, want error")
			}
		})
	}
}
