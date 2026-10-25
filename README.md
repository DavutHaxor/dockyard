# Dockyard

A self-hosted homelab dashboard: a small Go daemon on your server and a Flutter
client on your Linux desktop.

- **Daemon** (`daemon/`): talks to the Docker Engine API, reads host metrics
  from `/proc`, and exposes REST + WebSocket with token auth.
- **Client** (`app/`): Flutter desktop app with live metrics, container
  controls, and a Settings tab for the server URL and admin token. There is no
  login screen; the daemon session is established in the background.
- **Contract** (`api/`): OpenAPI spec and WebSocket protocol shared by both.

> Status: the daemon is functional and tested. The Linux Flutter client is
> implemented: left navigation rail, overview, containers, metrics, settings,
> live WebSocket updates, and container actions. Packaging and OS keyring
> storage are the main open client items.

## Quick start

### Daemon

Requires Go 1.27+ and access to `/var/run/docker.sock`.

```bash
cd daemon
export DOCKYARD_ADMIN_TOKEN="$(openssl rand -hex 32)"
go run ./cmd/dockyardd
```

The daemon starts even if Docker is not running: metrics keep working and
container routes return `502` until the socket is available.

```bash
curl http://127.0.0.1:8080/healthz

TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"token\":\"$DOCKYARD_ADMIN_TOKEN\"}" | jq -r .token)

curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/api/v1/containers
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/api/v1/metrics
```

### Client

Flutter is managed with [FVM](https://fvm.app/). **Always use `fvm flutter`**,
never bare `flutter`:

```bash
cd app
fvm flutter pub get
fvm flutter run -d linux
```

The SDK is pinned in `app/.fvmrc`. On a fresh machine run `fvm install` once.

On first launch the Overview page asks for connection details. Open **Settings**
in the left rail, enter the daemon URL (for example
`http://192.168.1.10:8080`) and the admin token, then choose **Test connection**
or **Save settings**. The app keeps the session and live connection running in
the background; it never shows a login screen.

The admin token is stored in the desktop app's local preferences. Use a
dedicated strong token and keep the daemon on a trusted network or behind TLS.

### Docker Compose

```bash
cd deploy
cp .env.example .env
# Set DOCKYARD_ADMIN_TOKEN and DOCKER_GID (stat -c '%g' /var/run/docker.sock)
docker compose up -d --build
```

The API binds to `127.0.0.1:8080` by default. See
[deploy/README.md](deploy/README.md) for the security model and a native
systemd alternative.

## Layout

```
app/       Flutter client (Linux desktop first; web/mobile later)
daemon/    Go daemon: Docker control, metrics, REST + WebSocket API
api/       OpenAPI + WebSocket contract
deploy/    Docker Compose, Dockerfile, systemd unit
docs/      Architecture notes and decision records
scripts/   Development and release helpers
```

Full tree and reasoning: [docs/layout.md](docs/layout.md).

## API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/healthz` | Liveness probe (no auth) |
| `POST` | `/api/v1/auth/login` | Exchange admin token for a JWT |
| `GET` | `/api/v1/containers` | List all containers |
| `POST` | `/api/v1/containers/{id}/start` | Start a container |
| `POST` | `/api/v1/containers/{id}/stop` | Stop a container |
| `POST` | `/api/v1/containers/{id}/restart` | Restart a container |
| `GET` | `/api/v1/metrics` | Latest metric sample |
| `GET` | `/api/v1/metrics/history` | In-memory metric window |
| `GET` | `/api/v1/ws` | Live metrics + container updates |

Details: [api/openapi.yaml](api/openapi.yaml) and
[api/websocket.md](api/websocket.md).

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `DOCKYARD_ADMIN_TOKEN` | required | Login secret, at least 16 characters |
| `DOCKYARD_ADDR` | `:8080` | HTTP listen address |
| `DOCKYARD_DOCKER_HOST` | `DOCKER_HOST` or `unix:///var/run/docker.sock` | Engine socket |
| `DOCKYARD_TOKEN_TTL` | `12h` | Session JWT lifetime |
| `DOCKYARD_METRICS_INTERVAL` | `2s` | Sampling/broadcast interval |
| `DOCKYARD_HISTORY_SIZE` | `150` | Samples kept in memory |
| `DOCKYARD_CONTAINER_POLL_INTERVAL` | `5s` | Container change detection |
| `DOCKYARD_PROC_PATH` | `/proc` | Host proc mount |
| `DOCKYARD_DISK_PATH` | `/` | Filesystem to report |
| `DOCKYARD_ALLOWED_ORIGINS` | empty | Browser origins for WebSocket |
| `DOCKYARD_SHUTDOWN_TIMEOUT` | `10s` | Graceful shutdown budget |

## Development

```bash
make app-run        # fvm flutter run -d linux
make app-test       # fvm flutter test
make app-analyze    # fvm flutter analyze
make daemon-run     # go run ./cmd/dockyardd
make daemon-check   # gofmt, go vet, go test
```

The daemon's Docker client is tested against a fake HTTP server and a real Unix
socket, so the test suite does not need a Docker daemon:

```bash
cd daemon
go test -race ./...
```

## Roadmap

1. OS keyring storage for the admin token (`flutter_secure_storage` or libsecret).
2. API client generated from `api/openapi.yaml` instead of hand-written models.
3. TLS reverse proxy service in `deploy/compose.yaml`.
4. Linux packaging (Flatpak/AppImage) and release automation; license.
