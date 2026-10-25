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
│   │   ├── main.dart             # entry point; loads SharedPreferences
│   │   ├── app.dart              # root widget, Material 3 themes, shell
│   │   ├── api/generated/        # generated from ../../api (do not edit)
│   │   ├── core/                 # cross-cutting client infrastructure
│   │   │   ├── config/           # settings model, validation, persistence
│   │   │   ├── models/           # container and metric DTOs
│   │   │   ├── network/          # REST client, JWT exchange, WS URI
│   │   │   ├── state/            # live WebSocket controller, navigation
│   │   │   ├── theme/            # light and dark Material 3 themes
│   │   │   └── utils/            # byte/percent/time formatters
│   │   ├── features/             # shell, overview, containers, metrics, settings
│   │   └── shared/widgets/       # reusable widgets only
│   ├── test/
│   ├── integration_test/
│   ├── assets/
│   ├── linux/                    # generated Linux runner (flutter create)
│   ├── .fvmrc                    # pinned Flutter SDK (FVM)
│   └── pubspec.yaml
├── daemon/                       # Go daemon ("dockyardd")
│   ├── cmd/dockyardd/
│   │   └── main.go               # config, wiring, background loops, shutdown
│   ├── internal/                 # not importable outside this module
│   │   ├── api/                  # router, handlers, auth middleware
│   │   ├── auth/                 # admin token check, JWT issue/verify
│   │   ├── config/               # environment parsing and validation
│   │   ├── docker/               # Docker Engine HTTP client + Engine interface
│   │   ├── metrics/              # /proc parser and statfs disk usage
│   │   ├── store/                # in-memory short-history ring buffer
│   │   └── ws/                   # WebSocket hub, per-client pumps, broadcast
│   ├── go.mod
│   └── go.sum
├── api/                          # language-neutral API contract
│   ├── openapi.yaml              # REST endpoints and schemas
│   └── websocket.md              # event envelope and client behavior
├── deploy/
│   ├── compose.yaml              # recommended self-hosting setup
│   ├── daemon.Dockerfile         # distroless, nonroot image
│   ├── .env.example
│   └── systemd/dockyard.service  # native install alternative
├── docs/                         # architecture notes and ADRs
├── scripts/                      # development and release helpers
├── .github/workflows/ci.yml      # format, vet, test, build, image
├── .dockerignore
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
  (`overview`, `containers`, `metrics`, `settings`, `shell`) keep UI and
  feature state together. The Go daemon is split by domain (`docker`, `metrics`,
  `auth`) with the HTTP layer on top, instead of generic `handlers/`,
  `services/`, `models/` folders.
- **Desktop now, other platforms later.** `app/linux/` is generated today;
  `fvm flutter create --platforms=web,android,ios,macos,windows .` adds the
  rest without moving any Dart code.

## Layering rules

### Client (`app/`)

```
features/*/presentation  ->  core/state  ->  core/network  ->  api/generated
          |                     |                |
          +---------> shared/widgets            +--> core/config
```

- `core/` contains infrastructure with no feature knowledge (HTTP, WebSocket,
  settings, models, theme, formatters).
- A feature owns its `presentation/` (and later `data/`/`domain/`) subfolder and
  may depend on `core/` and `shared/`. Features must not import each other's
  internals; cross-feature navigation goes through `core/state/navigation.dart`
  and the shell.
- `shared/` is presentation-only: widgets, formatters, extensions.
- `lib/api/generated/` is reserved for machine output. Never hand-edit it;
  regenerate from `api/`. Models are hand-written until codegen lands.

### Client UI architecture

- The shell is a Material 3 `Scaffold` with a permanent left `NavigationRail`
  (Overview, Containers, Metrics, Settings). It expands labels when the window
  is at least 1080 px wide and shows icon labels otherwise.
- There is intentionally no login route. `SettingsController` persists the
  server URL and admin token with `shared_preferences`; the API client trades
  the token for a short-lived JWT and retries once after a `401`.
- `liveControllerProvider` owns the WebSocket, reconnect backoff, the metric
  window, and the container list. Any settings change rebuilds the API client
  and live controller, so saving Settings reconnects automatically.
- Pages read `LiveState` through Riverpod and issue actions through the same
  controller; the daemon pushes the resulting container state back.
- Hidden sections stay alive with `Offstage`/`TickerMode` so search text and
  form state survive tab switches without animating in the background.

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
- The Docker client is a small HTTP client over the Unix socket, not the official
  SDK. Dockyard only needs list/start/stop/restart, and this keeps the
  dependency surface tiny; the `docker.Engine` interface contains the choice.

## Testing without Docker

Neither building nor testing the daemon requires a Docker daemon:

- `internal/docker` tests run against `httptest` and a temporary Unix socket.
- `internal/api` tests use a fake `docker.Engine`, including a real WebSocket
  connection.
- `internal/metrics` tests parse fixture files in a temp directory.
- CI validates `deploy/compose.yaml` with `docker compose config` and builds the
  image, but never runs the daemon against a live Docker Engine.

Only when you actually run `dockyardd` does it need `/var/run/docker.sock`.

## Runtime view

```
┌──────────────────────┐   HTTPS (REST) + WSS   ┌──────────────────────┐
│ Flutter app          │ ─────────────────────► │ dockyardd            │
│ app/ (Linux desktop) │ ◄───────────────────── │ daemon/ (server)     │
└──────────────────────┘   JSON, token auth     └───────┬──────────────┘
                                                        │
                                          ┌─────────────┴─────────────┐
                                          │                           │
                                  /var/run/docker.sock          /proc + statfs
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
| New shared UI widget | `app/lib/shared/widgets/` |
| Shared token/config handling | `daemon/internal/config` + `app/lib/core/config/` |
| Deployment or reverse proxy | `deploy/` |
| Design decision worth remembering | `docs/adr/NNNN-title.md` |
