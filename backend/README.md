# Hermes Mobile Bridge

Thin FastAPI wrapper that authenticates the Hermes iOS app via a single bearer
token and proxies every call (1:1) to a running [hermes-webui](https://github.com/nesquena/hermes-webui)
on `127.0.0.1:8787`.

```
iPhone  ── Bearer ──►  bridge (:8080)  ── cookie+CSRF ──►  webui (:8787)
```

## Run

```bash
cp .env.example .env   # edit WEBUI_PASSWORD + MOBILE_TOKEN
uv sync
uv run uvicorn hermes_bridge.main:app --reload --port 8080
```

Or with Docker (also runs the webui side-by-side):

```bash
export WEBUI_PASSWORD=$(openssl rand -hex 16)
export MOBILE_TOKEN=$(openssl rand -hex 32)
HERMES_HOME=$PWD/hermes-home docker compose up -d --build
```

## Why this exists

[hermes-webui](https://github.com/nesquena/hermes-webui) only supports
cookie+CSRF auth. We want a stable bearer token the iPhone can put in
Keychain and present from anywhere. The bridge performs one
`POST /api/auth/login` at boot, caches the `hermes_session` cookie + CSRF
token, and re-attaches them on every proxied call.

It also adds the two pieces the iOS backgrounding story needs:
1. A **runs registry** (SQLite) that records `stream_id → last_event_id` so
   the phone can resume a long turn after being backgrounded/disconnected.
2. **APNs hooks** that fire a push when a turn ends, while the phone is
   away from the SSE socket.

## Endpoints exposed

- Every webui route under `/api/*` (proxy, JSON)
- `/api/chat/start`, `/api/chat/stream`, `/api/chat/stream/status`,
  `/api/chat/cancel` (pass-through, with APNs hook on terminal events)
- `/health` (proxy of webui's `/health`)
- `/mobile/device` (register APNs device token)
- `/__bridge/health` (ungated Docker liveness)

## Smoke

```bash
export HERMES_MOBILE_TOKEN=$(grep MOBILE_TOKEN .env | cut -d= -f2)
curl -fsSL -H "Authorization: Bearer $HERMES_MOBILE_TOKEN" \
     http://127.0.0.1:8080/health | jq
curl -fsSL -H "Authorization: Bearer $HERMES_MOBILE_TOKEN" \
     http://127.0.0.1:8080/api/sessions | jq '.sessions | length'
```

## HTTPS for the phone

In production put this behind a Cloudflare Tunnel (free, stable hostname,
real TLS). Local dev: `cloudflared tunnel --url http://localhost:8080`.
