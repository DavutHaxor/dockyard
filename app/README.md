# Dockyard client

Flutter desktop client for the Dockyard daemon. Linux is the first target; web
and mobile can be added later with
`fvm flutter create --platforms=web,android,ios,macos,windows .`.

The UI uses Material 3 and a permanent left navigation rail with four sections:
**Overview**, **Containers**, **Metrics**, and **Settings**. There is no login
screen: the server URL and admin token live in Settings, and the client signs in
in the background, retries expired sessions once, and reconnects the WebSocket
with exponential backoff.

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

On first launch, open **Settings**, enter the daemon URL and admin token, then
save. The Overview page links to Settings until a token is configured.

## What the app does

- **Overview**: metric tiles with sparklines, host details, and a container
  preview. It shows a setup prompt when no token is configured.
- **Containers**: search and filter the daemon's container list; start, stop,
  and restart containers with inline progress and error feedback.
- **Metrics**: 60+ sample CPU, memory, and disk trend charts plus system details
  such as load average, uptime, and filesystem usage.
- **Settings**: server URL and admin token form with validation, a live
  connection status card, test-connection action, and token clearing.
- Data arrives over `GET /api/v1/ws`; REST is used for the initial/refresh
  snapshot and container actions.

The admin token is currently stored in local `shared_preferences` and obscured
in the form. Moving it to the OS keyring is tracked as a follow-up; use a
dedicated strong token and a trusted network or TLS reverse proxy.

## Structure

```
lib/
├── main.dart                    entry point; loads SharedPreferences
├── app.dart                     MaterialApp, Material 3 themes, shell
├── api/generated/               reserved for generated API models
├── core/
│   ├── config/                  settings model, validation, persistence
│   ├── models/                  container and metric DTOs
│   ├── network/                 REST client, session exchange, WS URI
│   ├── state/                   live WebSocket state, navigation provider
│   ├── theme/                   light and dark Material 3 themes
│   └── utils/                   byte/percent/time formatters
├── features/
│   ├── shell/presentation/      left NavigationRail and page host
│   ├── overview/presentation/   dashboard and setup prompt
│   ├── containers/presentation/ list, search, filters, actions
│   ├── metrics/presentation/    trend charts and system details
│   └── settings/presentation/   connection form and live status
└── shared/widgets/              reusable presentation widgets
```

State management is Riverpod 2 (`flutter_riverpod`). The settings controller is
a `StateNotifier` backed by `SharedPreferences`; `liveControllerProvider`
recreates the API client and WebSocket connection whenever settings change.
Hand-written models mirror `../api/openapi.yaml`.

## Checks

```bash
fvm flutter analyze
fvm flutter test
fvm flutter build linux --release
```
