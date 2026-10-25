# API contract

This directory is the single source of truth for everything the client and
daemon exchange. It deliberately contains no language-specific code.

Planned files:

| File | Contents |
| --- | --- |
| `openapi.yaml` | REST endpoints, auth, request/response schemas |
| `websocket.md` | WS connection, envelope, event types, subscription rules |

## Rules

1. Change the contract before changing either implementation.
2. Dart models are generated from the spec into `app/lib/api/generated/` and
   never hand-edited.
3. Go DTOs live beside the handlers in `daemon/internal/api` and are kept in
   sync with the spec through review and contract tests.
4. Additive changes are preferred. Breaking changes bump the API version in the
   path (`/api/v1`) and are called out in the README.
5. Every action endpoint documents its failure modes (container not found,
   Docker error, auth failure).

See [../docs/layout.md](../docs/layout.md) for how the contract fits into the
rest of the repository.
