# API contract

This directory is the single source of truth for everything the client and
daemon exchange. It deliberately contains no language-specific code.

| File | Contents |
| --- | --- |
| `openapi.yaml` | REST endpoints, auth, request/response schemas |
| `websocket.md` | WS connection, envelope, event types, client behavior |

## Rules

1. Change the contract before changing either implementation.
2. Go DTOs live with their handlers in `daemon/internal/api` and
   `daemon/internal/docker`. Keep them in sync with the spec through review and
   contract tests.
3. Dart models will be generated from `openapi.yaml` into
   `app/lib/api/generated/`; that directory is never hand-edited.
4. Additive changes are preferred. Breaking changes bump the version in the
   path (`/api/v1`) and are called out in the README.
5. Every action endpoint documents its failure modes (container not found,
   Docker unavailable, timeout, auth failure).

## Generating the Dart client

Planned command (once the client screens exist):

```bash
openapi-generator-cli generate \
  -i api/openapi.yaml \
  -g dart \
  -o app/lib/api/generated
```

The WebSocket protocol is described by hand in `websocket.md` because OpenAPI
cannot express server-pushed events. Its envelope is small on purpose.

See [../docs/layout.md](../docs/layout.md) for how the contract fits into the
rest of the repository.
