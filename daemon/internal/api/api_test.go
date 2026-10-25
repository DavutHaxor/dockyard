package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/DavutHaxor/dockyard/daemon/internal/auth"
	"github.com/DavutHaxor/dockyard/daemon/internal/docker"
	"github.com/DavutHaxor/dockyard/daemon/internal/metrics"
	"github.com/DavutHaxor/dockyard/daemon/internal/store"
	"github.com/DavutHaxor/dockyard/daemon/internal/ws"
	"github.com/coder/websocket"
)

const testToken = "test-admin-token-123456"

type fakeEngine struct {
	containers []docker.Container
	listErr    error
	actionErr  error
	actions    []string
}

func (f *fakeEngine) List(context.Context) ([]docker.Container, error) {
	return f.containers, f.listErr
}

func (f *fakeEngine) Start(_ context.Context, id string) error {
	f.actions = append(f.actions, "start:"+id)
	return f.actionErr
}

func (f *fakeEngine) Stop(_ context.Context, id string) error {
	f.actions = append(f.actions, "stop:"+id)
	return f.actionErr
}

func (f *fakeEngine) Restart(_ context.Context, id string) error {
	f.actions = append(f.actions, "restart:"+id)
	return f.actionErr
}

func (f *fakeEngine) Ping(context.Context) error { return nil }

func newTestServer(t *testing.T, engine *fakeEngine, samples ...metrics.Sample) (*httptest.Server, *auth.Manager) {
	t.Helper()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	manager := auth.New(testToken, time.Hour)
	sampleStore := store.New(10)
	for _, sample := range samples {
		sampleStore.Add(sample)
	}
	hub := ws.NewHub(logger)
	t.Cleanup(hub.Close)

	server := httptest.NewServer(New(engine, manager, sampleStore, hub, logger).Handler())
	t.Cleanup(server.Close)
	return server, manager
}

func login(t *testing.T, server *httptest.Server) string {
	t.Helper()
	resp, err := http.Post(server.URL+"/api/v1/auth/login", "application/json", strings.NewReader(`{"token":"`+testToken+`"}`))
	if err != nil {
		t.Fatalf("login request: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("login status = %d, want 200", resp.StatusCode)
	}
	var body struct {
		Token     string    `json:"token"`
		ExpiresAt time.Time `json:"expires_at"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("decode login: %v", err)
	}
	if body.Token == "" || body.ExpiresAt.IsZero() {
		t.Fatalf("unexpected login body: %+v", body)
	}
	return body.Token
}

func request(t *testing.T, method, target, token string) *http.Response {
	t.Helper()
	req, err := http.NewRequest(method, target, nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, target, err)
	}
	return resp
}

func TestHealthNeedsNoAuth(t *testing.T) {
	server, _ := newTestServer(t, &fakeEngine{})
	resp := request(t, http.MethodGet, server.URL+"/healthz", "")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
}

func TestLogin(t *testing.T) {
	server, manager := newTestServer(t, &fakeEngine{})

	resp, err := http.Post(server.URL+"/api/v1/auth/login", "application/json", strings.NewReader(`{"token":"nope"}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("wrong token status = %d, want 401", resp.StatusCode)
	}

	resp, err = http.Post(server.URL+"/api/v1/auth/login", "application/json", strings.NewReader(`{`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("malformed body status = %d, want 400", resp.StatusCode)
	}

	session := login(t, server)
	if err := manager.Verify(session); err != nil {
		t.Errorf("Verify(session) error = %v", err)
	}
}

func TestContainersRequireAuth(t *testing.T) {
	server, _ := newTestServer(t, &fakeEngine{})
	for _, token := range []string{"", "garbage"} {
		resp := request(t, http.MethodGet, server.URL+"/api/v1/containers", token)
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("token %q status = %d, want 401", token, resp.StatusCode)
		}
	}
}

func TestListContainers(t *testing.T) {
	engine := &fakeEngine{containers: []docker.Container{{ID: "abc", Name: "web", State: "running"}}}
	server, _ := newTestServer(t, engine)
	token := login(t, server)

	resp := request(t, http.MethodGet, server.URL+"/api/v1/containers", token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	var body struct {
		Containers []docker.Container `json:"containers"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if len(body.Containers) != 1 || body.Containers[0].Name != "web" {
		t.Fatalf("containers = %+v", body.Containers)
	}
}

func TestContainerActions(t *testing.T) {
	engine := &fakeEngine{}
	server, _ := newTestServer(t, engine)
	token := login(t, server)

	for _, action := range []string{"start", "stop", "restart"} {
		resp := request(t, http.MethodPost, server.URL+"/api/v1/containers/web/"+action, token)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Errorf("%s status = %d, want 200", action, resp.StatusCode)
		}
	}
	want := []string{"start:web", "stop:web", "restart:web"}
	if len(engine.actions) != len(want) {
		t.Fatalf("actions = %v", engine.actions)
	}
	for i := range want {
		if engine.actions[i] != want[i] {
			t.Errorf("actions[%d] = %q, want %q", i, engine.actions[i], want[i])
		}
	}
}

func TestContainerActionErrors(t *testing.T) {
	tests := []struct {
		name       string
		engineErr  error
		wantStatus int
		wantCode   string
	}{
		{"not found", &docker.APIError{StatusCode: http.StatusNotFound, Message: "no such container"}, http.StatusNotFound, "container_not_found"},
		{"docker down", errors.New("dial unix: no such file"), http.StatusBadGateway, "docker_unavailable"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			engine := &fakeEngine{actionErr: tt.engineErr}
			server, _ := newTestServer(t, engine)
			token := login(t, server)

			resp := request(t, http.MethodPost, server.URL+"/api/v1/containers/web/start", token)
			defer resp.Body.Close()
			if resp.StatusCode != tt.wantStatus {
				t.Fatalf("status = %d, want %d", resp.StatusCode, tt.wantStatus)
			}
			var body struct {
				Error struct {
					Code string `json:"code"`
				} `json:"error"`
			}
			if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
				t.Fatal(err)
			}
			if body.Error.Code != tt.wantCode {
				t.Errorf("code = %q, want %q", body.Error.Code, tt.wantCode)
			}
		})
	}
}

func TestInvalidContainerID(t *testing.T) {
	server, _ := newTestServer(t, &fakeEngine{})
	token := login(t, server)

	resp := request(t, http.MethodPost, server.URL+"/api/v1/containers/bad%20id/start", token)
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

func TestMetricsEndpoints(t *testing.T) {
	server, _ := newTestServer(t, &fakeEngine{})
	token := login(t, server)

	resp := request(t, http.MethodGet, server.URL+"/api/v1/metrics", token)
	resp.Body.Close()
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("empty metrics status = %d, want 503", resp.StatusCode)
	}

	server, _ = newTestServer(t, &fakeEngine{}, metrics.Sample{CPUPercent: 12.5}, metrics.Sample{CPUPercent: 20})
	token = login(t, server)

	resp = request(t, http.MethodGet, server.URL+"/api/v1/metrics", token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("metrics status = %d, want 200", resp.StatusCode)
	}
	var sample metrics.Sample
	if err := json.NewDecoder(resp.Body).Decode(&sample); err != nil {
		t.Fatal(err)
	}
	if sample.CPUPercent != 20 {
		t.Errorf("CPUPercent = %v, want 20", sample.CPUPercent)
	}

	resp = request(t, http.MethodGet, server.URL+"/api/v1/metrics/history?limit=1", token)
	defer resp.Body.Close()
	var history struct {
		Samples []metrics.Sample `json:"samples"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&history); err != nil {
		t.Fatal(err)
	}
	if len(history.Samples) != 1 || history.Samples[0].CPUPercent != 20 {
		t.Errorf("history = %+v", history.Samples)
	}

	resp = request(t, http.MethodGet, server.URL+"/api/v1/metrics/history?limit=-1", token)
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("invalid limit status = %d, want 400", resp.StatusCode)
	}
}

func TestWebSocketSnapshot(t *testing.T) {
	engine := &fakeEngine{containers: []docker.Container{{ID: "abc", Name: "web"}}}
	server, _ := newTestServer(t, engine, metrics.Sample{CPUPercent: 5})
	token := login(t, server)

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/v1/ws?token=" + url.QueryEscape(token)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	conn, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		t.Fatalf("websocket dial: %v", err)
	}
	defer conn.CloseNow()

	_, payload, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("websocket read: %v", err)
	}

	var event struct {
		Type string `json:"type"`
		Data struct {
			Metrics    *metrics.Sample    `json:"metrics"`
			History    []metrics.Sample   `json:"history"`
			Containers []docker.Container `json:"containers"`
		} `json:"data"`
	}
	if err := json.Unmarshal(payload, &event); err != nil {
		t.Fatalf("decode event: %v", err)
	}
	if event.Type != "snapshot" {
		t.Errorf("type = %q, want snapshot", event.Type)
	}
	if event.Data.Metrics == nil || event.Data.Metrics.CPUPercent != 5 {
		t.Errorf("metrics = %+v", event.Data.Metrics)
	}
	if len(event.Data.History) != 1 {
		t.Errorf("history length = %d, want 1", len(event.Data.History))
	}
	if len(event.Data.Containers) != 1 || event.Data.Containers[0].Name != "web" {
		t.Errorf("containers = %+v", event.Data.Containers)
	}
}

func TestWebSocketRequiresAuth(t *testing.T) {
	server, _ := newTestServer(t, &fakeEngine{})
	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/api/v1/ws"

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, resp, err := websocket.Dial(ctx, wsURL, nil)
	if err == nil {
		conn.CloseNow()
		t.Fatal("websocket dial without token succeeded")
	}
	if resp == nil || resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("status = %v, want 401", resp)
	}
}
