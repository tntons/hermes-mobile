# Build commands

## iOS (run from `ios/`)

> Requires Xcode 16+, iOS 17 SDK, Swift 5.10+. Open `Hermes.xcodeproj` in Xcode for day-to-day work.

- Open project:        `open Hermes.xcodeproj`
- Build (CLI):         `xcodebuild -scheme Hermes -destination 'generic/platform=iOS' build`
- Build (simulator):   `xcodebuild -scheme Hermes -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Clean:               `xcodebuild -scheme Hermes clean`
- Tests (unit):        `xcodebuild -scheme Hermes -destination 'platform=iOS Simulator,name=iPhone 16' test`
- Treat warnings as errors (in scheme → Build Settings → `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`).

### SPM dependencies (declared in Xcode; pin to versions in `Package.resolved`)
- `launchdarkly/swift-eventsource`
- `kishikawakatsumi/KeychainAccess`
- (v1.1) `appstefan/HighlightSwift`

> **Note:** the plan originally suggested `exyte/Chat` for the message list, but the
> implementation uses a native `LazyVStack` (`MessageListView.swift`) for v1 to avoid
> the ExyteChat 3.x → GiphyUISDK → Swift 6.1 dependency chain that breaks Xcode 15
> builds. If you prefer ExyteChat, pin to `2.x` (the last 0.x-ish line).

### First-time install on a real iPhone
Follow the standard "Trust this Mac" + signing flow:
1. Set a development team in the Hermes target → Signing & Capabilities.
2. Connect iPhone, choose it as the run destination.
3. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID.
4. Build & Run from Xcode.

## Backend (run from `backend/`)

> Requires Python 3.11+ and [uv](https://docs.astral.sh/uv/).

- Install deps:        `uv sync`
- Run (dev, reload):   `uv run uvicorn hermes_bridge.main:app --reload --port 8080`
- Tests:               `uv run pytest -q`
- Lint:                `uv run ruff check .`
- Format check:        `uv run ruff format --check .`

### Backend env (copy `.env.example` → `.env`)

```
WEBUI_BASE_URL=http://127.0.0.1:8787
WEBUI_PASSWORD=changeme                 # the HERMES_WEBUI_PASSWORD on hermes-webui
MOBILE_TOKEN=long-random-hex            # the bearer the phone stores in Keychain
RUNS_DB_PATH=./runs.sqlite
# APNs (v1.1, optional)
APNS_TEAM_ID=
APNS_KEY_ID=
APNS_KEY_PATH=/secrets/AuthKey_XXXX.p8
APNS_TOPIC=com.hermes.mobile
APNS_USE_SANDBOX=1
```

### Integration smoke (requires a running hermes-webui on :8787)

```bash
export HERMES_MOBILE_TOKEN=$(grep MOBILE_TOKEN backend/.env | cut -d= -f2)
curl -s -H "Authorization: Bearer $HERMES_MOBILE_TOKEN" http://127.0.0.1:8080/health | jq
curl -s -H "Authorization: Bearer $HERMES_MOBILE_TOKEN" http://127.0.0.1:8080/api/sessions | jq '.sessions | length'
```

### Public HTTPS for the phone (no Tailscale)

Local development:
```bash
cloudflared tunnel --url http://localhost:8080   # prints a stable https://*.trycloudflare.com
```

Production: configure a named Cloudflare Tunnel (free) → your own hostname → Cloudflare Origin Certificate on the bridge.

## Layout reminder

- `IMPLEMENTATION_PLAN.md` — the plan, authoritative.
- `backend/hermes_bridge/` — FastAPI bridge (your own, controllable).
- `ios/Hermes/` — SwiftUI app.
- `ios/Hermes/App/Rendering/Resources/UPSTREAM.txt` — record the upstream hermes-webui commit SHA whenever JS/CSS assets are vendored.