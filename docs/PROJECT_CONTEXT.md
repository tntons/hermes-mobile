# JARVIS project context

JARVIS is a SwiftUI iPhone client and FastAPI bridge for an upstream Hermes
Agent/WebUI runtime. The computer is a development/deployment host; the
runtime is intended to run behind a named Cloudflare Tunnel.

## Structure

- `ios/JARVIS/` — SwiftUI app, networking, SSE client, persistence, and UI.
- `backend/jarvis_bridge/` — bearer authentication, WebUI proxy, SSE proxy,
  run registry, and optional APNs hooks.
- `backend/docker-compose.yml` — private agent/bridge deployment topology.
- `HANDOFF.md` — current migration state and verification record.
- `IMPLEMENTATION_PLAN.md` — authoritative Phase 0/1 plan.

## Contracts

The phone sends `Authorization: Bearer <MOBILE_TOKEN>` to the bridge. The
bridge owns the upstream cookie + CSRF session and preserves upstream `/api/*`
routes and JSON/SSE field names. Missing chat/session profiles default to the
upstream profile selected by `JARVIS_PROFILE`.
