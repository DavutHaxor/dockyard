# Dockyard

A self-hosted homelab dashboard: a Go daemon runs on your server, and a Flutter
app runs on your Linux desktop.

- Live CPU, memory, disk, load, and uptime metrics
- Container list with start, stop, and restart
- REST + WebSocket API protected by a token

## Requirements

- **Daemon:** Go 1.27+ and access to `/var/run/docker.sock`
- **Client:** Flutter via [FVM](https://fvm.app/) (run `fvm install` once)

## Run the daemon

```bash
cd daemon
export DOCKYARD_ADMIN_TOKEN="$(openssl rand -hex 32)"
go run ./cmd/dockyardd
```

It listens on `:8080`. Metrics work without Docker; container routes return
`502` until the socket is available.

## Run the desktop client

```bash
cd app
fvm flutter pub get
fvm flutter run -d linux
```

In **Settings**, enter the daemon URL and admin token, then test or save the
connection. There is no login screen.

## Run with Docker Compose

```bash
cd deploy
cp .env.example .env
# Set DOCKYARD_ADMIN_TOKEN and DOCKER_GID in .env
docker compose up -d --build
```

## Build

```bash
make daemon-build   # bin/dockyardd
make app-build      # Linux desktop bundle
```

## Documentation

- [docs/guide.md](docs/guide.md) — client setup, API, configuration, development, roadmap
- [docs/layout.md](docs/layout.md) — repository layout and architecture
- [api/README.md](api/README.md) — API contract
- [deploy/README.md](deploy/README.md) — deployment and security
- [docs/adr/](docs/adr/) — design decisions
