# Daemon

`dockyardd` is the server-side component. It holds the only privileged access to
Docker and host metrics and exposes them to the Flutter client over REST and
WebSocket.

## Run

```bash
cd daemon
export DOCKYARD_ADMIN_TOKEN="$(openssl rand -hex 32)"
go run ./cmd/dockyardd
```

It needs read access to `/var/run/docker.sock` for containers and to `/proc` for
metrics. Docker being down is not fatal: the HTTP API starts, metrics work, and
container routes answer `502` until the socket comes back.

## Configuration

| Variable | Default | Notes |
| --- | --- | --- |
| `DOCKYARD_ADMIN_TOKEN` | required | Minimum 16 characters |
| `DOCKYARD_ADDR` | `:8080` | `host:port` |
| `DOCKYARD_DOCKER_HOST` | `DOCKER_HOST`, then `unix:///var/run/docker.sock` | `unix://`, `tcp://`, `http://`, `https://` |
| `DOCKYARD_TOKEN_TTL` | `12h` | Session lifetime |
| `DOCKYARD_METRICS_INTERVAL` | `2s` | Minimum `250ms` |
| `DOCKYARD_HISTORY_SIZE` | `150` | In-memory ring size |
| `DOCKYARD_CONTAINER_POLL_INTERVAL` | `5s` | Minimum `1s` |
| `DOCKYARD_PROC_PATH` | `/proc` | Point at a host mount in containers |
| `DOCKYARD_DISK_PATH` | `/` | Filesystem for disk metrics |
| `DOCKYARD_ALLOWED_ORIGINS` | empty | Comma-separated WebSocket origins |
| `DOCKYARD_SHUTDOWN_TIMEOUT` | `10s` | Graceful shutdown budget |

## Endpoints

- `GET /healthz` — liveness, unauthenticated
- `POST /api/v1/auth/login` — admin token → JWT
- `GET /api/v1/containers`
- `POST /api/v1/containers/{id}/start|stop|restart`
- `GET /api/v1/metrics`, `GET /api/v1/metrics/history`
- `GET /api/v1/ws` — `snapshot`, `metrics`, `containers` events

The full contract lives in [`../api/`](../api/).

## Design notes

- **Docker Engine API over HTTP, not an SDK.** Dockyard needs list/start/stop/
  restart only. A ~200-line client (`internal/docker`) keeps the dependency
  surface small, works over a Unix socket, and is trivial to test. Migrating to
  the official SDK later is contained to that package and its `Engine` interface.
- **No Docker needed to build or test.** The client is tested with `httptest`
  and a real Unix socket; `go test ./...` runs without a Docker daemon.
- **Container watcher, not request polling.** `internal/store` holds the metric
  window, while `cmd/dockyardd` polls Docker every few seconds and only
  broadcasts when the list changes.
- **Single admin, JWT sessions.** The long-lived admin token is never sent after
  login; the signing key is derived from it, so rotating the token invalidates
  all sessions and restarting the daemon does not.
- **Graceful shutdown.** `SIGINT`/`SIGTERM` stops the collector, closes
  WebSockets, then drains HTTP within `DOCKYARD_SHUTDOWN_TIMEOUT`.

## Package map

| Package | Responsibility |
| --- | --- |
| `cmd/dockyardd` | `main()`: config, wiring, background loops, shutdown |
| `internal/api` | Router, handlers, auth middleware, error mapping |
| `internal/auth` | Admin token check, JWT issue/verify |
| `internal/config` | Environment parsing and validation |
| `internal/docker` | Docker Engine HTTP client and `Engine` interface |
| `internal/metrics` | `/proc` + `statfs` collector |
| `internal/store` | Bounded in-memory metric history |
| `internal/ws` | WebSocket hub, per-client pumps, broadcast |

Rules of thumb:

- `cmd/` stays thin; no business logic.
- `docker` and `metrics` do not import `api` or `ws`.
- No database. Metrics history is bounded and in memory, per project scope.
- Run `make daemon-check` (or `gofmt`, `go vet`, `go test -race ./...`) before
  committing.

## Checks

```bash
go vet ./...
go test -race ./...
go build ./cmd/dockyardd
```
