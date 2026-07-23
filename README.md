# JARVIS

JARVIS is a cloud-hosted personal secretary controlled from an iPhone. The
user-facing product is JARVIS; Hermes Agent remains the internal agent engine.

```text
JARVIS iPhone App
  ↓ HTTPS
Cloudflare named tunnel
  ↓
JARVIS Mobile Bridge
  ↓ private Docker network
Hermes Agent Gateway/WebUI runtime
```

The computer is used for development and deployment only. The runtime belongs
on the server hosting the agent, bridge, and tunnel.

## Current Phase 1 stack

- SwiftUI iOS 17 app in `ios/JARVIS/`.
- FastAPI bridge in `backend/jarvis_bridge/`.
- Upstream-compatible Hermes Agent/WebUI container named `jarvis-agent`.
- Bearer authentication from the phone to `jarvis-bridge`.
- SQLite run registry for SSE resume and terminal state.
- Optional named Cloudflare Tunnel service named `jarvis-cloudflared`.
- Default upstream profile: `jarvis`.

Internal compatibility identifiers such as `WEBUI_PASSWORD`,
`HERMES_WEBUI_PASSWORD`, `MOBILE_TOKEN`, `/api/*`, and `hermes_session` remain
unchanged because the upstream runtime depends on them.

## Development

See `AGENTS.md` for commands and `HANDOFF.md` for the current verification
record. The authoritative migration scope is in `IMPLEMENTATION_PLAN.md`.

```bash
cd backend && uv sync && uv run pytest -q
cd ../ios && xcodebuild -project JARVIS.xcodeproj -scheme JARVIS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Do not delete the legacy WebUI bridge until the later API-server replacement
passes its complete migration suite.
