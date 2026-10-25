// Package api exposes the daemon's HTTP and WebSocket surface.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"github.com/DavutHaxor/dockyard/daemon/internal/auth"
	"github.com/DavutHaxor/dockyard/daemon/internal/docker"
	"github.com/DavutHaxor/dockyard/daemon/internal/metrics"
	"github.com/DavutHaxor/dockyard/daemon/internal/store"
	"github.com/DavutHaxor/dockyard/daemon/internal/ws"
)

const (
	dockerListTimeout = 15 * time.Second
	dockerActTimeout  = 30 * time.Second
	maxHistoryLimit   = 1000
	maxLoginBody      = 4 << 10
)

var containerRef = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$`)

// Server wires the HTTP layer to the daemon's dependencies.
type Server struct {
	engine docker.Engine
	auth   *auth.Manager
	store  *store.Store
	hub    *ws.Hub
	logger *slog.Logger
}

// New creates an API server.
func New(engine docker.Engine, authManager *auth.Manager, sampleStore *store.Store, hub *ws.Hub, logger *slog.Logger) *Server {
	return &Server{
		engine: engine,
		auth:   authManager,
		store:  sampleStore,
		hub:    hub,
		logger: logger,
	}
}

// Handler returns the fully wrapped HTTP handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealth)
	mux.HandleFunc("POST /api/v1/auth/login", s.handleLogin)

	mux.Handle("GET /api/v1/containers", s.authenticated(http.HandlerFunc(s.handleListContainers)))
	mux.Handle("POST /api/v1/containers/{id}/start", s.authenticated(http.HandlerFunc(s.handleStart)))
	mux.Handle("POST /api/v1/containers/{id}/stop", s.authenticated(http.HandlerFunc(s.handleStop)))
	mux.Handle("POST /api/v1/containers/{id}/restart", s.authenticated(http.HandlerFunc(s.handleRestart)))

	mux.Handle("GET /api/v1/metrics", s.authenticated(http.HandlerFunc(s.handleMetrics)))
	mux.Handle("GET /api/v1/metrics/history", s.authenticated(http.HandlerFunc(s.handleMetricsHistory)))
	mux.Handle("GET /api/v1/ws", s.authenticated(http.HandlerFunc(s.handleWebSocket)))

	return s.recoverer(s.securityHeaders(s.logRequests(mux)))
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxLoginBody)

	var request struct {
		Token string `json:"token"`
	}
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "expected a JSON body with a token field")
		return
	}
	if request.Token == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "token is required")
		return
	}

	session, expiresAt, err := s.auth.Login(request.Token)
	if errors.Is(err, auth.ErrInvalidCredentials) {
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "invalid admin token")
		return
	}
	if err != nil {
		s.logger.Error("issue session token", "error", err)
		writeError(w, http.StatusInternalServerError, "internal_error", "could not issue a session token")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"token":      session,
		"expires_at": expiresAt.UTC(),
	})
}

func (s *Server) handleListContainers(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), dockerListTimeout)
	defer cancel()

	containers, err := s.engine.List(ctx)
	if err != nil {
		s.writeDockerError(w, "list containers", err)
		return
	}
	if containers == nil {
		containers = []docker.Container{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"containers": containers})
}

func (s *Server) handleStart(w http.ResponseWriter, r *http.Request) {
	s.containerAction(w, r, "start", s.engine.Start)
}

func (s *Server) handleStop(w http.ResponseWriter, r *http.Request) {
	s.containerAction(w, r, "stop", s.engine.Stop)
}

func (s *Server) handleRestart(w http.ResponseWriter, r *http.Request) {
	s.containerAction(w, r, "restart", s.engine.Restart)
}

func (s *Server) containerAction(w http.ResponseWriter, r *http.Request, action string, fn func(context.Context, string) error) {
	id := r.PathValue("id")
	if !containerRef.MatchString(id) {
		writeError(w, http.StatusBadRequest, "invalid_container", "container id or name is not valid")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), dockerActTimeout)
	defer cancel()

	if err := fn(ctx, id); err != nil {
		s.writeDockerError(w, action+" container", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleMetrics(w http.ResponseWriter, _ *http.Request) {
	sample, ok := s.store.Latest()
	if !ok {
		writeError(w, http.StatusServiceUnavailable, "metrics_unavailable", "no metrics collected yet")
		return
	}
	writeJSON(w, http.StatusOK, sample)
}

func (s *Server) handleMetricsHistory(w http.ResponseWriter, r *http.Request) {
	limit := 0
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 0 || parsed > maxHistoryLimit {
			writeError(w, http.StatusBadRequest, "invalid_limit", fmt.Sprintf("limit must be between 0 and %d", maxHistoryLimit))
			return
		}
		limit = parsed
	}
	writeJSON(w, http.StatusOK, map[string]any{"samples": s.store.History(limit)})
}

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	var latest *metrics.Sample
	if sample, ok := s.store.Latest(); ok {
		latest = &sample
	}

	ctx, cancel := context.WithTimeout(r.Context(), dockerListTimeout)
	containers, err := s.engine.List(ctx)
	cancel()
	if err != nil {
		s.logger.Warn("list containers for websocket snapshot", "error", err)
		containers = []docker.Container{}
	}

	snapshot := struct {
		Metrics    *metrics.Sample    `json:"metrics"`
		History    []metrics.Sample   `json:"history"`
		Containers []docker.Container `json:"containers"`
	}{
		Metrics:    latest,
		History:    s.store.History(0),
		Containers: containers,
	}

	s.hub.Serve(w, r, ws.Event{Type: "snapshot", Data: snapshot})
}

func (s *Server) authenticated(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		// Browsers cannot set headers on WebSocket connections, so the
		// stream endpoint also accepts the session as a query parameter.
		if token == "" && r.URL.Path == "/api/v1/ws" {
			token = r.URL.Query().Get("token")
		}
		if token == "" || s.auth.Verify(token) != nil {
			writeError(w, http.StatusUnauthorized, "unauthorized", "missing or invalid session token")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) writeDockerError(w http.ResponseWriter, operation string, err error) {
	if errors.Is(err, context.DeadlineExceeded) {
		writeError(w, http.StatusGatewayTimeout, "docker_timeout", "docker did not respond in time")
		return
	}
	if docker.IsNotFound(err) {
		writeError(w, http.StatusNotFound, "container_not_found", "container not found")
		return
	}
	s.logger.Error(operation, "error", err)
	writeError(w, http.StatusBadGateway, "docker_unavailable", "could not reach the Docker Engine")
}

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		recorder := &statusRecorder{ResponseWriter: w}
		next.ServeHTTP(recorder, r)
		s.logger.Info("http request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", recorder.statusCode(),
			"duration_ms", time.Since(start).Milliseconds(),
			"remote", remoteHost(r.RemoteAddr),
		)
	})
}

func (s *Server) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

func (s *Server) recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			recovered := recover()
			if recovered == nil {
				return
			}
			if recovered == http.ErrAbortHandler {
				panic(recovered)
			}
			s.logger.Error("panic in handler", "panic", recovered, "stack", string(debug.Stack()))
			writeError(w, http.StatusInternalServerError, "internal_error", "internal server error")
		}()
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	if r.status == 0 {
		r.status = code
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(data []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	return r.ResponseWriter.Write(data)
}

// Unwrap lets http.ResponseController (used by the WebSocket upgrade) reach
// the original ResponseWriter.
func (r *statusRecorder) Unwrap() http.ResponseWriter {
	return r.ResponseWriter
}

func (r *statusRecorder) statusCode() int {
	if r.status == 0 {
		return http.StatusOK
	}
	return r.status
}

func bearerToken(r *http.Request) string {
	parts := strings.Fields(r.Header.Get("Authorization"))
	if len(parts) == 2 && strings.EqualFold(parts[0], "bearer") {
		return parts[1]
	}
	return ""
}

func remoteHost(addr string) string {
	if i := strings.LastIndex(addr, ":"); i > 0 {
		return addr[:i]
	}
	return addr
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{
		"error": map[string]string{
			"code":    code,
			"message": message,
		},
	})
}
