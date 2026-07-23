# JARVIS Mobile Bridge

FastAPI bridge for the JARVIS iPhone app. The phone uses bearer authentication
over HTTPS; the bridge keeps the upstream Hermes Agent/WebUI contract private
and handles its cookie + CSRF session internally.

```text
iPhone → Cloudflare Tunnel → jarvis-bridge → private jarvis-agent
                              bearer          upstream Hermes runtime
```

The upstream runtime remains Hermes internally. Names such as `WEBUI_PASSWORD`,
`MOBILE_TOKEN`, `HERMES_WEBUI_PASSWORD`, and `/api/*` are compatibility
identifiers and must not be renamed in the upstream integration.

## Local run

```bash
cp .env.example .env
# Set WEBUI_PASSWORD, MOBILE_TOKEN, and optionally JARVIS_PROFILE or
# JARVIS_PERSONALITY.
uv sync
uv run uvicorn jarvis_bridge.main:app --reload --port 8080
```

## Docker run

```bash
export WEBUI_PASSWORD=$(openssl rand -hex 16)
export MOBILE_TOKEN=$(openssl rand -hex 32)
docker compose up -d --build
```

The Compose services are named `jarvis-agent`, `jarvis-bridge`, and the
optional `jarvis-cloudflared`. Only the bridge publishes a local port; the
agent remains on the private Docker network.

## Endpoints

- `/health` — authenticated upstream health proxy.
- `/api/*` — authenticated upstream-compatible JSON routes.
- `/api/chat/stream` — authenticated SSE proxy with resume support.
- `/mobile/device` — authenticated APNs device registration.
- `/mobile/approvals` — authenticated list/detail/one-action approval API.
- `/__bridge/health` — unauthenticated container liveness probe.
- `/__bridge/version` — unauthenticated JARVIS bridge metadata.

When a session or chat-start request omits `profile`, the bridge selects the
upstream-supported profile named by `JARVIS_PROFILE` (default: `jarvis`). It
does not rewrite user messages or fork the Hermes Agent source. When
`personality` is omitted, it selects `JARVIS_PERSONALITY` (default: `jarvis`)
and persists that selection through the upstream personality endpoint.

The Compose stack seeds the default persona automatically when the profile is
missing. For a manual install or an explicit profile refresh:

```bash
mkdir -p "$HERMES_HOME/profiles/jarvis"
cp deployment/jarvis-profile/config.yaml "$HERMES_HOME/profiles/jarvis/config.yaml"
```

See `deployment/jarvis-profile/README.md` for the profile ownership boundary.

Secretary side effects are approval-gated. JARVIS records upstream approval
events in the existing runs SQLite database and exposes only one-action
`approve` or `deny` decisions. Approvals expire after 900 seconds by default;
configure `JARVIS_APPROVAL_TTL_SECONDS` to change that window. Session-wide and
permanent grants are not exposed by the mobile flow.

Phase 2 includes an in-memory task contract for deterministic tests only. Gmail,
Google Calendar, durable task storage, scheduled jobs, and production APNs are
still deferred until the connector phase.

## Verification

```bash
uv run pytest -q
uv run ruff check .
uv run ruff format --check .

curl -fsSL -H "Authorization: Bearer $MOBILE_TOKEN" \
  http://127.0.0.1:8080/health | jq
curl -fsSL -H "Authorization: Bearer $MOBILE_TOKEN" \
  http://127.0.0.1:8080/api/sessions | jq '.sessions | length'
```

For phone access, use a named Cloudflare Tunnel pointing at
`http://jarvis-bridge:8080` from the tunnel container, or at
`http://127.0.0.1:8080` during local development.
