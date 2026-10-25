# WebSocket protocol

Connect to `GET /api/v1/ws` and authenticate with either:

- `Authorization: Bearer <session-jwt>` (desktop clients), or
- `?token=<session-jwt>` (browser clients, which cannot set headers during the
  upgrade).

The connection is server-to-client only. Messages sent by the client are
ignored; commands stay on REST so they are easy to retry and reason about.

## Envelope

Every text frame is a JSON object:

```json
{ "type": "metrics", "data": { } }
```

`type` is one of `snapshot`, `metrics`, or `containers`.

## Events

### `snapshot`

Sent immediately after the connection opens. It replaces client state, so a
reconnect does not need a separate history fetch.

```json
{
  "type": "snapshot",
  "data": {
    "metrics": {
      "timestamp": "2026-10-25T12:00:00Z",
      "cpu_percent": 12.4,
      "cpu_count": 8,
      "load_1": 0.42,
      "load_5": 0.38,
      "load_15": 0.31,
      "uptime_seconds": 86400,
      "memory": {
        "total_bytes": 17179869184,
        "used_bytes": 6871947673,
        "available_bytes": 10307921511,
        "percent": 40
      },
      "disk": {
        "path": "/",
        "total_bytes": 511101108224,
        "used_bytes": 204440443289,
        "free_bytes": 306660664935,
        "percent": 40
      }
    },
    "history": [],
    "containers": []
  }
}
```

`metrics` is `null` until the first sample is collected. `history` is the
in-memory window, oldest first (at most `DOCKYARD_HISTORY_SIZE` samples).
`containers` is the same shape as `GET /api/v1/containers`; it is empty if the
Docker Engine is unreachable.

### `metrics`

Sent every `DOCKYARD_METRICS_INTERVAL` (default 2s). `data` is one
`MetricsSample` object, exactly as returned by `GET /api/v1/metrics`.

### `containers`

Sent when the container list differs from the previous poll (default every 5s).
`data` is an array of container objects, the same shape as the `containers`
field above. Actions such as start/stop eventually show up here when the
watcher observes the new state.

## Client behavior

- Treat `snapshot` as authoritative and replace local state.
- Keep at most the `history` window from the snapshot; append subsequent
  `metrics` events.
- Reconnect with exponential backoff. A new connection always begins with a
  fresh snapshot, so no events need to be replayed.
- Slow clients may miss events: the hub drops them rather than blocking the
  server. The next sample is at most one interval away.
