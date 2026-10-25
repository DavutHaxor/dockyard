package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"reflect"
	"syscall"
	"time"

	"github.com/DavutHaxor/dockyard/daemon/internal/api"
	"github.com/DavutHaxor/dockyard/daemon/internal/auth"
	"github.com/DavutHaxor/dockyard/daemon/internal/config"
	"github.com/DavutHaxor/dockyard/daemon/internal/docker"
	"github.com/DavutHaxor/dockyard/daemon/internal/metrics"
	"github.com/DavutHaxor/dockyard/daemon/internal/store"
	"github.com/DavutHaxor/dockyard/daemon/internal/ws"
)

func main() {
	healthcheck := flag.Bool("healthcheck", false, "probe the local daemon and exit")
	flag.Parse()
	if *healthcheck {
		os.Exit(runHealthcheck())
	}
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "dockyardd:", err)
		os.Exit(1)
	}
}

func run() error {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	engine, err := docker.New(cfg.DockerHost)
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	authManager := auth.New(cfg.AdminToken, cfg.TokenTTL)
	samples := store.New(cfg.HistorySize)
	collector := metrics.NewCollector(cfg.ProcPath, cfg.DiskPath)
	hub := ws.NewHub(logger, cfg.AllowedOrigins...)
	defer hub.Close()

	pingCtx, cancelPing := context.WithTimeout(ctx, 5*time.Second)
	if err := engine.Ping(pingCtx); err != nil {
		logger.Warn("docker engine is not reachable yet; container endpoints will fail until it is", "error", err)
	} else {
		logger.Info("docker engine connected", "host", cfg.DockerHost)
	}
	cancelPing()

	if sample, err := collector.Sample(); err != nil {
		logger.Warn("initial metrics sample failed", "error", err)
	} else {
		samples.Add(sample)
	}

	go collectMetrics(ctx, logger, collector, samples, hub, cfg.MetricsInterval)
	go watchContainers(ctx, logger, engine, hub, cfg.ContainerPollInterval)

	server := &http.Server{
		Addr:              cfg.Addr,
		Handler:           api.New(engine, authManager, samples, hub, logger).Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       120 * time.Second,
		// WriteTimeout stays zero: WebSocket writes carry their own deadlines.
	}

	serverErr := make(chan error, 1)
	go func() {
		logger.Info("dockyardd listening", "addr", cfg.Addr)
		serverErr <- server.ListenAndServe()
	}()

	select {
	case err := <-serverErr:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	case <-ctx.Done():
		logger.Info("shutting down")
	}

	hub.Close()
	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancelShutdown()
	if err := server.Shutdown(shutdownCtx); err != nil {
		_ = server.Close()
		return fmt.Errorf("shutdown: %w", err)
	}
	return nil
}

func collectMetrics(ctx context.Context, logger *slog.Logger, collector *metrics.Collector, samples *store.Store, hub *ws.Hub, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			sample, err := collector.Sample()
			if err != nil {
				logger.Warn("collect metrics", "error", err)
				continue
			}
			samples.Add(sample)
			hub.Broadcast("metrics", sample)
		}
	}
}

func watchContainers(ctx context.Context, logger *slog.Logger, engine docker.Engine, hub *ws.Hub, interval time.Duration) {
	var (
		last    []docker.Container
		lastErr string
	)

	refresh := func() {
		reqCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
		containers, err := engine.List(reqCtx)
		cancel()
		if err != nil {
			// Log repeated failures once, not every poll.
			if err.Error() != lastErr {
				logger.Warn("watch containers", "error", err)
				lastErr = err.Error()
			}
			return
		}
		lastErr = ""
		if reflect.DeepEqual(containers, last) {
			return
		}
		last = containers
		hub.Broadcast("containers", containers)
	}

	refresh()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			refresh()
		}
	}
}

func runHealthcheck() int {
	addr := os.Getenv("DOCKYARD_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		fmt.Fprintln(os.Stderr, "healthcheck: invalid DOCKYARD_ADDR:", err)
		return 1
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}

	target := "http://" + net.JoinHostPort(host, port) + "/healthz"
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(target)
	if err != nil {
		fmt.Fprintln(os.Stderr, "healthcheck:", err)
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "healthcheck: unexpected status %d\n", resp.StatusCode)
		return 1
	}
	return 0
}
