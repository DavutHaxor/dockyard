# Daemon

`dockyardd` is the server-side component: it holds the only privileged access to
Docker and system metrics, and exposes them to the Flutter client over REST and
WebSocket.

## First-time setup

Go is not installed in the current environment. Once it is, initialize the
module (replace the path with the real repository URL):

```bash
cd daemon
go mod init github.com/<owner>/dockyard/daemon
```

Then `main()` goes in `cmd/dockyardd/`.

## Package map

| Package | Responsibility |
| --- | --- |
| `cmd/dockyardd` | `main()`: config, dependency wiring, graceful shutdown |
| `internal/api` | HTTP router, REST handlers, middleware |
| `internal/auth` | Admin token verification, JWT issue/verify |
| `internal/config` | Environment and config file parsing |
| `internal/docker` | Docker Engine API wrapper (list/start/stop/restart) |
| `internal/metrics` | `/proc` and `/sys` collectors (CPU, RAM, disk, uptime) |
| `internal/store` | In-memory current snapshot + short history |
| `internal/ws` | WebSocket hub: clients, subscriptions, broadcast |

Rules of thumb:

- `cmd/` stays thin; no business logic.
- `docker` and `metrics` do not import `api` or `ws`.
- No database. Metrics history is bounded and in memory, per project scope.
- Run `go test ./...` and `go vet ./...` before committing.

## Running

```bash
go run ./cmd/dockyardd
```

Docker access requires `/var/run/docker.sock` (root-equivalent). Metrics need
read access to `/proc` and `/sys`. In production the daemon runs in a container
via `deploy/compose.yaml` or natively via `deploy/systemd/dockyard.service`.
