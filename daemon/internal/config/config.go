package config

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config holds the daemon configuration, loaded from the environment.
type Config struct {
	Addr                  string
	AdminToken            string
	TokenTTL              time.Duration
	DockerHost            string
	ProcPath              string
	DiskPath              string
	MetricsInterval       time.Duration
	HistorySize           int
	ContainerPollInterval time.Duration
	ShutdownTimeout       time.Duration
	AllowedOrigins        []string
}

func defaults() Config {
	return Config{
		Addr:                  ":8080",
		TokenTTL:              12 * time.Hour,
		DockerHost:            "unix:///var/run/docker.sock",
		ProcPath:              "/proc",
		DiskPath:              "/",
		MetricsInterval:       2 * time.Second,
		HistorySize:           150,
		ContainerPollInterval: 5 * time.Second,
		ShutdownTimeout:       10 * time.Second,
	}
}

// Load reads configuration from DOCKYARD_* environment variables.
func Load() (Config, error) {
	cfg := defaults()

	if v := os.Getenv("DOCKYARD_ADDR"); v != "" {
		cfg.Addr = v
	}
	cfg.AdminToken = strings.TrimSpace(os.Getenv("DOCKYARD_ADMIN_TOKEN"))
	if v := os.Getenv("DOCKYARD_DOCKER_HOST"); v != "" {
		cfg.DockerHost = v
	} else if v := os.Getenv("DOCKER_HOST"); v != "" {
		cfg.DockerHost = v
	}
	if v := os.Getenv("DOCKYARD_PROC_PATH"); v != "" {
		cfg.ProcPath = v
	}
	if v := os.Getenv("DOCKYARD_DISK_PATH"); v != "" {
		cfg.DiskPath = v
	}
	if v := os.Getenv("DOCKYARD_ALLOWED_ORIGINS"); v != "" {
		for _, origin := range strings.Split(v, ",") {
			if origin = strings.TrimSpace(origin); origin != "" {
				cfg.AllowedOrigins = append(cfg.AllowedOrigins, origin)
			}
		}
	}

	var err error
	if cfg.TokenTTL, err = durationEnv("DOCKYARD_TOKEN_TTL", cfg.TokenTTL); err != nil {
		return Config{}, err
	}
	if cfg.MetricsInterval, err = durationEnv("DOCKYARD_METRICS_INTERVAL", cfg.MetricsInterval); err != nil {
		return Config{}, err
	}
	if cfg.ContainerPollInterval, err = durationEnv("DOCKYARD_CONTAINER_POLL_INTERVAL", cfg.ContainerPollInterval); err != nil {
		return Config{}, err
	}
	if cfg.ShutdownTimeout, err = durationEnv("DOCKYARD_SHUTDOWN_TIMEOUT", cfg.ShutdownTimeout); err != nil {
		return Config{}, err
	}
	if cfg.HistorySize, err = intEnv("DOCKYARD_HISTORY_SIZE", cfg.HistorySize); err != nil {
		return Config{}, err
	}

	if err := cfg.validate(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func (c Config) validate() error {
	if c.AdminToken == "" {
		return fmt.Errorf("DOCKYARD_ADMIN_TOKEN is required")
	}
	if len(c.AdminToken) < 16 {
		return fmt.Errorf("DOCKYARD_ADMIN_TOKEN must be at least 16 characters")
	}
	if c.MetricsInterval < 250*time.Millisecond {
		return fmt.Errorf("DOCKYARD_METRICS_INTERVAL must be at least 250ms")
	}
	if c.ContainerPollInterval < time.Second {
		return fmt.Errorf("DOCKYARD_CONTAINER_POLL_INTERVAL must be at least 1s")
	}
	if c.HistorySize < 1 {
		return fmt.Errorf("DOCKYARD_HISTORY_SIZE must be positive")
	}
	if _, _, err := net.SplitHostPort(c.Addr); err != nil {
		return fmt.Errorf("DOCKYARD_ADDR: %w", err)
	}
	if err := validateDockerHost(c.DockerHost); err != nil {
		return fmt.Errorf("DOCKYARD_DOCKER_HOST: %w", err)
	}
	return nil
}

func validateDockerHost(host string) error {
	switch {
	case strings.HasPrefix(host, "unix://"):
		if strings.TrimPrefix(host, "unix://") == "" {
			return fmt.Errorf("unix socket path is empty")
		}
	case strings.HasPrefix(host, "tcp://"), strings.HasPrefix(host, "http://"), strings.HasPrefix(host, "https://"):
	default:
		return fmt.Errorf("unsupported scheme in %q (use unix://, tcp://, http:// or https://)", host)
	}
	return nil
}

func durationEnv(key string, def time.Duration) (time.Duration, error) {
	raw := os.Getenv(key)
	if raw == "" {
		return def, nil
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return d, nil
}

func intEnv(key string, def int) (int, error) {
	raw := os.Getenv(key)
	if raw == "" {
		return def, nil
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return n, nil
}
