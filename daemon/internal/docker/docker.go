// Package docker is a small client for the Docker Engine HTTP API.
//
// Only the operations Dockyard needs are implemented: listing containers and
// starting, stopping or restarting them. Talking HTTP directly keeps the
// daemon dependency-free and makes it easy to test with a fake socket.
package docker

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const userAgent = "dockyard/0.1"

// Container is the subset of container state the UI needs.
type Container struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Image   string `json:"image"`
	State   string `json:"state"`
	Status  string `json:"status"`
	Created int64  `json:"created"`
	Ports   []Port `json:"ports"`
}

// Port describes a published or exposed container port.
type Port struct {
	IP          string `json:"ip,omitempty"`
	PrivatePort uint16 `json:"private_port"`
	PublicPort  uint16 `json:"public_port,omitempty"`
	Type        string `json:"type"`
}

// Engine is the container control surface used by the API and the watcher.
type Engine interface {
	List(ctx context.Context) ([]Container, error)
	Start(ctx context.Context, id string) error
	Stop(ctx context.Context, id string) error
	Restart(ctx context.Context, id string) error
	Ping(ctx context.Context) error
}

// APIError is a non-2xx response from the Docker Engine.
type APIError struct {
	StatusCode int
	Message    string
}

func (e *APIError) Error() string {
	if e.Message == "" {
		return fmt.Sprintf("docker: HTTP %d", e.StatusCode)
	}
	return fmt.Sprintf("docker: HTTP %d: %s", e.StatusCode, e.Message)
}

// IsNotFound reports whether err is a Docker "no such container" response.
func IsNotFound(err error) bool {
	var apiErr *APIError
	return errors.As(err, &apiErr) && apiErr.StatusCode == http.StatusNotFound
}

// Client speaks the Docker Engine API over a Unix socket or TCP.
type Client struct {
	httpClient *http.Client
	baseURL    string
}

// New creates a client for hosts such as unix:///var/run/docker.sock or
// tcp://127.0.0.1:2375.
func New(host string) (*Client, error) {
	switch {
	case strings.HasPrefix(host, "unix://"):
		socket := strings.TrimPrefix(host, "unix://")
		if socket == "" {
			return nil, errors.New("docker: unix socket path is empty")
		}
		transport := &http.Transport{
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				var dialer net.Dialer
				return dialer.DialContext(ctx, "unix", socket)
			},
			MaxIdleConns:    4,
			IdleConnTimeout: 90 * time.Second,
		}
		return newClient("http://docker", &http.Client{Transport: transport, Timeout: 30 * time.Second}), nil

	case strings.HasPrefix(host, "tcp://"):
		return newClient("http://"+strings.TrimPrefix(host, "tcp://"), &http.Client{Timeout: 30 * time.Second}), nil

	case strings.HasPrefix(host, "http://"), strings.HasPrefix(host, "https://"):
		return newClient(strings.TrimRight(host, "/"), &http.Client{Timeout: 30 * time.Second}), nil

	default:
		return nil, fmt.Errorf("docker: unsupported host %q", host)
	}
}

func newClient(baseURL string, httpClient *http.Client) *Client {
	return &Client{httpClient: httpClient, baseURL: baseURL}
}

// List returns all containers, running or not.
func (c *Client) List(ctx context.Context) ([]Container, error) {
	resp, err := c.do(ctx, http.MethodGet, "/containers/json?all=true")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if err := check(resp); err != nil {
		return nil, err
	}

	var raw []apiContainer
	if err := json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(&raw); err != nil {
		return nil, fmt.Errorf("docker: decode container list: %w", err)
	}

	containers := make([]Container, 0, len(raw))
	for _, item := range raw {
		containers = append(containers, item.container())
	}
	return containers, nil
}

// Start starts a stopped container.
func (c *Client) Start(ctx context.Context, id string) error {
	return c.action(ctx, id, "start")
}

// Stop stops a running container.
func (c *Client) Stop(ctx context.Context, id string) error {
	return c.action(ctx, id, "stop")
}

// Restart restarts a container.
func (c *Client) Restart(ctx context.Context, id string) error {
	return c.action(ctx, id, "restart")
}

// Ping checks that the Docker daemon is reachable.
func (c *Client) Ping(ctx context.Context) error {
	resp, err := c.do(ctx, http.MethodGet, "/_ping")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return check(resp)
}

func (c *Client) action(ctx context.Context, id, action string) error {
	if strings.TrimSpace(id) == "" {
		return errors.New("docker: container id is required")
	}
	resp, err := c.do(ctx, http.MethodPost, "/containers/"+url.PathEscape(id)+"/"+action)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return check(resp)
}

func (c *Client) do(ctx context.Context, method, path string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, nil)
	if err != nil {
		return nil, fmt.Errorf("docker: build request: %w", err)
	}
	req.Header.Set("User-Agent", userAgent)
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("docker: %w", err)
	}
	return resp, nil
}

// check converts Docker's status codes into errors. A 304 means the requested
// state was already in effect (for example, starting a running container), so
// it is treated as success.
func check(resp *http.Response) error {
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	if resp.StatusCode == http.StatusNotModified {
		return nil
	}

	message := ""
	var body struct {
		Message string `json:"message"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 8<<10)).Decode(&body); err == nil {
		message = body.Message
	}
	if message == "" {
		message = http.StatusText(resp.StatusCode)
	}
	return &APIError{StatusCode: resp.StatusCode, Message: message}
}

type apiContainer struct {
	ID      string    `json:"Id"`
	Names   []string  `json:"Names"`
	Image   string    `json:"Image"`
	State   string    `json:"State"`
	Status  string    `json:"Status"`
	Created int64     `json:"Created"`
	Ports   []apiPort `json:"Ports"`
}

type apiPort struct {
	IP          string `json:"IP"`
	PrivatePort uint16 `json:"PrivatePort"`
	PublicPort  uint16 `json:"PublicPort"`
	Type        string `json:"Type"`
}

func (c apiContainer) container() Container {
	name := c.ID
	if len(name) > 12 {
		name = name[:12]
	}
	if len(c.Names) > 0 {
		name = strings.TrimPrefix(c.Names[0], "/")
	}
	ports := make([]Port, 0, len(c.Ports))
	for _, p := range c.Ports {
		ports = append(ports, Port{
			IP:          p.IP,
			PrivatePort: p.PrivatePort,
			PublicPort:  p.PublicPort,
			Type:        p.Type,
		})
	}
	return Container{
		ID:      c.ID,
		Name:    name,
		Image:   c.Image,
		State:   c.State,
		Status:  c.Status,
		Created: c.Created,
		Ports:   ports,
	}
}
