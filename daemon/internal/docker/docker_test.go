package docker

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestList(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/containers/json" || r.URL.Query().Get("all") != "true" {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.String())
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[
			{
				"Id": "abc123def4567890",
				"Names": ["/web"],
				"Image": "nginx:latest",
				"State": "running",
				"Status": "Up 2 hours",
				"Created": 1700000000,
				"Ports": [
					{"IP": "0.0.0.0", "PrivatePort": 80, "PublicPort": 8080, "Type": "tcp"}
				]
			},
			{
				"Id": "fedcba9876543210",
				"Names": [],
				"Image": "redis:7",
				"State": "exited",
				"Status": "Exited (0) 3 hours ago",
				"Created": 1690000000,
				"Ports": []
			}
		]`))
	}))
	defer server.Close()

	client := newClient(server.URL, server.Client())
	containers, err := client.List(context.Background())
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if len(containers) != 2 {
		t.Fatalf("List() returned %d containers, want 2", len(containers))
	}

	web := containers[0]
	if web.Name != "web" || web.Image != "nginx:latest" || web.State != "running" {
		t.Errorf("unexpected container: %+v", web)
	}
	if len(web.Ports) != 1 || web.Ports[0].PublicPort != 8080 || web.Ports[0].PrivatePort != 80 {
		t.Errorf("unexpected ports: %+v", web.Ports)
	}
	if containers[1].Name != "fedcba987654" {
		t.Errorf("fallback name = %q, want short id", containers[1].Name)
	}
	if containers[1].Ports == nil {
		t.Error("Ports is nil, want empty slice")
	}
}

func TestActions(t *testing.T) {
	tests := []struct {
		name       string
		status     int
		wantErr    bool
		wantStatus int
	}{
		{"accepted", http.StatusNoContent, false, http.StatusNoContent},
		{"already in state", http.StatusNotModified, false, http.StatusNotModified},
		{"docker error", http.StatusInternalServerError, true, http.StatusInternalServerError},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost {
					t.Errorf("method = %s, want POST", r.Method)
				}
				w.WriteHeader(tt.status)
				if tt.status >= 400 {
					_, _ = w.Write([]byte(`{"message":"boom"}`))
				}
			}))
			defer server.Close()

			client := newClient(server.URL, server.Client())
			err := client.Start(context.Background(), "web")
			if tt.wantErr && err == nil {
				t.Fatal("Start() error = nil, want error")
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("Start() error = %v", err)
			}
			if tt.wantErr {
				var apiErr *APIError
				if !errors.As(err, &apiErr) || apiErr.StatusCode != tt.wantStatus {
					t.Fatalf("error = %v, want APIError %d", err, tt.wantStatus)
				}
			}
		})
	}
}

func TestActionNotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"message":"No such container: missing"}`))
	}))
	defer server.Close()

	client := newClient(server.URL, server.Client())
	err := client.Stop(context.Background(), "missing")
	if !IsNotFound(err) {
		t.Fatalf("IsNotFound(%v) = false, want true", err)
	}
	var apiErr *APIError
	if !errors.As(err, &apiErr) || apiErr.Message != "No such container: missing" {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestUnixSocket(t *testing.T) {
	socket := filepath.Join(t.TempDir(), "docker.sock")
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatalf("listen unix: %v", err)
	}

	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[]`))
	})}
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Close() })

	client, err := New("unix://" + socket)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	containers, err := client.List(context.Background())
	if err != nil {
		t.Fatalf("List() over unix socket error = %v", err)
	}
	if len(containers) != 0 {
		t.Errorf("List() = %v, want empty", containers)
	}
}

func TestNewRejectsUnsupportedHost(t *testing.T) {
	for _, host := range []string{"", "ssh://server", "unix://"} {
		if _, err := New(host); err == nil {
			t.Errorf("New(%q) error = nil, want error", host)
		}
	}
}
