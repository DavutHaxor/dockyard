# Repository layout

Dockyard is one repository with two deployables and one shared contract:

| Part | Path | Runs on | Built with |
| --- | --- | --- | --- |
| Client | `app/` | Linux desktop (web/mobile later) | Flutter |
| Daemon | `daemon/` | The monitored server | Go |
| API contract | `api/` | — | OpenAPI + WebSocket docs |
| Deployment | `deploy/` | The monitored server | Docker Compose / systemd |

```
dockyard/
├── app/                          # Flutter client (Linux desktop first)
│   ├── lib/
│   │   ├── main.dart             # entry point
│   │   ├── app.dart              # root widget, theme, router
│   │   ├── api/generated/        # generated from ../../api (do not edit)
│   │   ├── core/                 # cross-cutting client infrastructure
│   │   │   ├── config/           # server URL, build flavors
│   │   │   ├── network/          # REST client, WebSocket client, auth
│   │   │   ├── storage/          # token storage (OS keyring)
│   │   │   └── theme/
│   │   ├── features/             # feature-first: auth, containers, metrics, settings
│   │   └── shared/widgets/       # reusable widgets only
│   ├── test/
│   ├── integration_test/
│   ├── assets/
│   ├── linux/                    # generated Linux runner (flutter create)
│   ├── .fvmrc                    # pinned Flutter SDK (FVM)
│   └── pubspec.yaml
├── daemon/                       # Go daemon ("dockyardd")
│   ├── cmd/dockyardd/            # main() only: wire config, server, signal handling
│   └── internal/                 # not importable outside this module
│       ├── api/                  # HTTP router, handlers, middleware
│       ├── auth/                 # admin token check, JWT issue/verify
│       ├── config/               # environment/config parsing
│       ├── docker/               # Docker Engine API wrapper
│       ├── metrics/              # /proc and /sys collectors
│       ├── store/                # in-memory short-history ring buffer
│       └── ws/                   # WebSocket hub, subscriptions, broadcast
├── api/                          # language-neutral API contract
├── deploy/                       # compose file, Dockerfile, systemd unit, proxy config
├── docs/                         # architecture notes, development guide, ADRs
├── scripts/                      # development and release helpers
├── .github/workflows/            # CI (lint, test, build, image publish)
├── Makefile                      # common commands (Flutter always via FVM)
├── README.md
└── .gitignore
```

## Why this shape

- **One repo, two deployables.** The client and daemon evolve together; a single
  PR can change an endpoint and its only consumer. Separate repositories would
  force version-matching and cross-repo PRs for a one-person project.
- **The daemon owns all privileged access.** Only `daemon/` talks to the Docker
  socket and `/proc`. The client never touches the server directly; it speaks
  HTTP + WebSocket to the daemon.
- **The contract lives in `api/`, not in either codebase.** REST and WebSocket
  payloads are specified once. Dart models are generated into
  `app/lib/api/generated/`; Go DTOs live next to the handlers. Neither side is
  the source of truth, so neither drifts silently.
- **Feature-first client, domain-first daemon.** Flutter features
  (`containers`, `metrics`, ...) keep UI/data/state together. The Go daemon is
  split by domain (`docker`, `metrics`, `auth`) with the HTTP layer on top,
  instead of generic `handlers/`, `services/`, `models/` folders.
- **Desktop now, other platforms later.** `app/linux/` is generated today;
  `fvm flutter create --platforms=web,android,ios,macos,windows .` adds the
  rest without moving any Dart code.

## Layering rules

### Client (`app/`)

```
features/*/presentation  ->  features/*/domain  ->  features/*/data
          |                          |                    |
          +----------> core/network + api/generated <-----+
```

- `core/` contains infrastructure with no feature knowledge (HTTP, WS, config,
  token storage, theme).
- A feature owns its `data/`, `domain/`, and `presentation/` subfolders and may
  depend on `core/` and `shared/`. Features must not import each other's
  internals; cross-feature flows go through `app.dart` (routing/shell) or a
  shared domain type.
- `shared/` is presentation-only: widgets, formatters, extensions.
- `lib/api/generated/` is machine output. Never hand-edit it; regenerate from
  `api/`.

### Daemon (`daemon/`)

- `cmd/dockyardd` is a thin `main`: load config, construct dependencies, start,
  wait for SIGINT/SIGTERM, shut down.
- Dependency direction: `api`/`ws` → `docker`, `metrics`, `auth`, `store` →
  `config`. The `docker` and `metrics` packages know nothing about HTTP, which
  keeps them unit-testable and lets `ws` reuse them.
- No `pkg/` directory yet. Nothing is meant for reuse outside this module;
  promote a package only when a second consumer exists.
- No database. `store/` keeps the current snapshot plus a short in-memory
  history, matching the project scope.

## Runtime view

```
┌──────────────────────┐   HTTPS (REST) + WSS   ┌──────────────────────┐
│ Flutter app          │ ─────────────────────► │ dockyardd            │
│ app/ (Linux desktop) │ ◄───────────────────── │ daemon/ (server)     │
└──────────────────────┘   JSON, token auth     └───────┬──────────────┘
                                                        │
                                          ┌─────────────┴─────────────┐
                                          │                           │
                                  /var/run/docker.sock          /proc, /sys
                                  (container list/control)      (CPU, RAM, disk)
```

- The daemon is deployed by `deploy/compose.yaml` (or the systemd unit) on the
  server; the app is a native Linux binary built on the user's machine.
- HTTPS/WSS termination belongs to a reverse proxy in `deploy/`, so the daemon
  can stay a plain HTTP server on localhost/the Docker network.
- The attacker model matters: Docker socket access is root-equivalent. The
  daemon is the only process that gets it, and the token protects every route.

## Flutter via FVM

The SDK is pinned in `app/.fvmrc` (`stable`). **Always run Flutter through
FVM:**

```bash
cd app
fvm flutter pub get
fvm flutter run -d linux
fvm flutter test
fvm flutter analyze
```

Do not call bare `flutter`; it may use a different SDK than the one the project
is pinned to. The root `Makefile` wraps these commands, and CI uses the same
`.fvmrc`.

## Where new things go

| Change | Location |
| --- | --- |
| New REST route or WS event | `api/` first, then `daemon/internal/api` or `daemon/internal/ws`, then the client feature |
| New container action | `daemon/internal/docker` + handler, event through `ws` |
| New metric | `daemon/internal/metrics` collector + `store` + WS broadcast |
| New screen or panel | `app/lib/features/<feature>/presentation/` |
| Shared token/config handling | `daemon/internal/config` + `app/lib/core/` |
| Deployment or reverse proxy | `deploy/` |
| Design decision worth remembering | `docs/adr/NNNN-title.md` |
