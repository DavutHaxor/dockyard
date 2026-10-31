# Guide

Detailed setup, configuration, and development notes for Dockyard.

> Status: the daemon is functional and tested; the Linux client is implemented.
> Packaging and OS keyring storage are the main open items.

## Client setup

Flutter is managed with [FVM](https://fvm.app/). Always use `fvm flutter`,
never bare `flutter`. The SDK is pinned in `app/.fvmrc`.

```bash
cd app
fvm flutter pub get
fvm flutter run -d linux
```

On first launch, open **Settings** in the left rail and enter the daemon URL
(for example `http://192.168.1.10:8080`) and the admin token. Choose **Test
connection** or **Save settings**. The session and live WebSocket connection
run in the background.

The admin token is stored in the desktop app's local preferences. Use a
dedicated strong token and keep the daemon on a trusted network or behind TLS.

## API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/healthz` | Liveness probe (no auth) |
| `POST` | `/api/v1/auth/login` | Exchange admin token for a JWT |
| `GET` | `/api/v1/containers` | List containers |
| `POST` | `/api/v1/containers/{id}/start` | Start a container |
| `POST` | `/api/v1/containers/{id}/stop` | Stop a container |
| `POST` | `/api/v1/containers/{id}/restart` | Restart a container |
| `GET` | `/api/v1/metrics` | Latest metric sample |
| `GET` | `/api/v1/metrics/history` | In-memory metric window |
| `GET` | `/api/v1/ws` | Live metrics + container updates |

Details: [../api/openapi.yaml](../api/openapi.yaml) and
[../api/websocket.md](../api/websocket.md).

### Example

```bash
curl http://127.0.0.1:8080/healthz

TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"token\":\"$DOCKYARD_ADMIN_TOKEN\"}" | jq -r .token)

curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/api/v1/containers
```

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

Daemon tests use a fake HTTP server and a real Unix socket, so Docker is not
required:

```bash
cd daemon
go test -race ./...
```

## Roadmap

1. OS keyring storage for the admin token.
2. Generate the API client from `api/openapi.yaml`.
3. TLS reverse proxy in `deploy/compose.yaml`.
4. Linux packaging (Flatpak/AppImage), release automation, and license.
