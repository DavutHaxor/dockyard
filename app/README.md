# Dockyard client

Flutter desktop client for the Dockyard daemon. Linux is the first target; web
and mobile can be added later with
`fvm flutter create --platforms=web,android,ios,macos,windows .`.

## Running

The SDK is pinned with FVM (`app/.fvmrc`). Always prefix Flutter commands with
`fvm`:

```bash
fvm flutter pub get
fvm flutter run -d linux
```

If FVM has not installed the pinned SDK on this machine yet:

```bash
fvm install
```

## Structure

```
lib/
├── main.dart          entry point
├── app.dart           root widget, theme, routing
├── api/generated/     generated API client (do not edit)
├── core/
│   ├── config/        server URL, build flavors
│   ├── network/       REST and WebSocket clients
│   ├── storage/       token storage (OS keyring)
│   └── theme/
├── features/
│   ├── auth/
│   ├── containers/
│   ├── metrics/
│   └── settings/
└── shared/widgets/    reusable widgets
```

Each feature grows its own `data/`, `domain/`, and `presentation/` folders.
Features do not import each other's internals; shared infrastructure belongs in
`core/`. See [../docs/layout.md](../docs/layout.md).

## Checks

```bash
fvm flutter analyze
fvm flutter test
```
