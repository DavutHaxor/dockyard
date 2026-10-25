# Dockyard

A self-hosted homelab dashboard: a small Go daemon on your server, and a Flutter
client on your Linux desktop.

- **Daemon** (`daemon/`): talks to the Docker Engine API and reads `/proc` and
  `/sys`; exposes REST + WebSocket with token auth.
- **Client** (`app/`): Flutter desktop app showing live container and system
  state and sending start/stop/restart commands.

> Status: repository skeleton. The layout, Flutter shell, and tooling are in
> place; daemon and client features are not implemented yet.

## Layout

```
app/       Flutter client (Linux desktop first; web/mobile later)
daemon/    Go daemon: Docker control, metrics, REST + WebSocket API
api/       Shared API contract (OpenAPI + WebSocket schemas)
deploy/    Docker Compose, Dockerfile, systemd unit, reverse proxy
docs/      Architecture notes and decision records
scripts/   Development and release helpers
```

See [docs/layout.md](docs/layout.md) for the full tree and the reasoning behind
it.

## Quick start

### Client

Flutter is managed with [FVM](https://fvm.app/). **Always use `fvm flutter`**,
never bare `flutter`:

```bash
cd app
fvm flutter pub get
fvm flutter run -d linux
```

The SDK is pinned in `app/.fvmrc`. On a fresh machine, install FVM and run
`fvm install` once.

### Daemon

Requires Go 1.22+ (not installed in this environment yet):

```bash
cd daemon
go mod init github.com/<owner>/dockyard/daemon
go run ./cmd/dockyardd
```

The daemon needs access to `/var/run/docker.sock` and `/proc` when it runs.

### Common commands

```bash
make app-run       # fvm flutter run -d linux
make app-test      # fvm flutter test
make app-analyze   # fvm flutter analyze
make daemon-run    # go run ./cmd/dockyardd
```

## Roadmap

1. API contract in `api/` and daemon skeleton (`config`, `auth`, `/healthz`).
2. Docker listing and start/stop/restart.
3. `/proc` metrics + WebSocket streaming.
4. Flutter login, container list, live metrics dashboard.
5. `docker compose up` deployment, CI, documentation.
