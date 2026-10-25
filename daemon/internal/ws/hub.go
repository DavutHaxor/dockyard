// Package ws owns the WebSocket hub that pushes live metrics and container
// changes to connected clients.
package ws

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
)

const (
	sendBuffer   = 32
	writeTimeout = 10 * time.Second
	pingInterval = 30 * time.Second
	readLimit    = 1024
)

// Event is the envelope sent to clients. Type is one of "snapshot",
// "metrics", or "containers"; Data is the corresponding payload.
type Event struct {
	Type string `json:"type"`
	Data any    `json:"data"`
}

type client struct {
	conn *websocket.Conn
	send chan []byte
}

// Hub tracks connected clients and broadcasts events to all of them.
type Hub struct {
	logger  *slog.Logger
	origins []string

	mu      sync.Mutex
	clients map[*client]struct{}
	closed  bool
}

// NewHub creates a hub. origins is passed to the WebSocket origin check; an
// empty list keeps the library's strict same-origin default.
func NewHub(logger *slog.Logger, origins ...string) *Hub {
	return &Hub{
		logger:  logger,
		origins: origins,
		clients: make(map[*client]struct{}),
	}
}

// Serve upgrades the request and blocks until the client disconnects or the
// hub shuts down. initial events (for example a snapshot) are queued first.
func (h *Hub) Serve(w http.ResponseWriter, r *http.Request, initial ...Event) {
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		OriginPatterns: h.origins,
	})
	if err != nil {
		h.logger.Warn("websocket accept failed", "error", err)
		return
	}
	conn.SetReadLimit(readLimit)

	c := &client{conn: conn, send: make(chan []byte, sendBuffer)}
	if !h.add(c) {
		return
	}
	defer h.remove(c)

	for _, event := range initial {
		payload, err := json.Marshal(event)
		if err != nil {
			h.logger.Warn("marshal initial event", "type", event.Type, "error", err)
			continue
		}
		c.send <- payload
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	writeDone := make(chan struct{})
	go func() {
		defer close(writeDone)
		h.writeLoop(ctx, c)
	}()

	// The client is not expected to send commands over the socket; reading
	// keeps the connection alive and detects disconnects.
	for {
		if _, _, err := conn.Read(ctx); err != nil {
			break
		}
	}

	cancel()
	conn.CloseNow()
	<-writeDone
}

func (h *Hub) writeLoop(ctx context.Context, c *client) {
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case payload := <-c.send:
			writeCtx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.conn.Write(writeCtx, websocket.MessageText, payload)
			cancel()
			if err != nil {
				c.conn.CloseNow()
				return
			}
		case <-ticker.C:
			pingCtx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.conn.Ping(pingCtx)
			cancel()
			if err != nil {
				c.conn.CloseNow()
				return
			}
		}
	}
}

// Broadcast sends an event to every connected client. Slow clients drop
// events rather than blocking the caller; the next sample arrives shortly.
func (h *Hub) Broadcast(eventType string, data any) {
	payload, err := json.Marshal(Event{Type: eventType, Data: data})
	if err != nil {
		h.logger.Error("marshal websocket event", "type", eventType, "error", err)
		return
	}

	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closed {
		return
	}
	for c := range h.clients {
		select {
		case c.send <- payload:
		default:
			h.logger.Debug("dropping event for slow websocket client")
		}
	}
}

// Close disconnects all clients and prevents new broadcasts.
func (h *Hub) Close() {
	h.mu.Lock()
	if h.closed {
		h.mu.Unlock()
		return
	}
	h.closed = true
	clients := make([]*client, 0, len(h.clients))
	for c := range h.clients {
		clients = append(clients, c)
	}
	h.mu.Unlock()

	for _, c := range clients {
		_ = c.conn.Close(websocket.StatusGoingAway, "server shutting down")
	}
}

func (h *Hub) add(c *client) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closed {
		_ = c.conn.Close(websocket.StatusGoingAway, "server shutting down")
		return false
	}
	h.clients[c] = struct{}{}
	return true
}

func (h *Hub) remove(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.clients, c)
}
