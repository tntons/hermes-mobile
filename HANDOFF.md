# Hermes iOS — Build Status & Handoff

Last updated while waiting for Xcode 16+ install.

## What's done

### Plan
- `IMPLEMENTATION_PLAN.md` — full file-level plan, real hermes-webui API contract baked in.

### Backend (Hermes Mobile Bridge — FastAPI) — **verified, tests pass**
- `backend/pyproject.toml` — uv-managed; Python 3.12.
- `backend/hermes_bridge/`
  - `config.py` — pydantic-settings, fail-closed when `MOBILE_TOKEN` empty
  - `auth.py` — bearer auth dependency (constant-time compare)
  - `webui_client.py` — httpx async client with cookie+CSRF caching + auto-re-login
  - `runs.py` — SQLite runs registry (stream_id → last_event_id, device_token)
  - `sse_proxy.py` — chunked SSE forwarder with APNs hook on terminal events
  - `proxy.py` — generic JSON pass-through (`/api/*`)
  - `apns.py` — APNs client (v1.1, optional extra)
  - `main.py` — FastAPI app, lifespan, route mounting
- `backend/tests/test_proxy.py` — **5/5 passing** under `uv run --with pytest --with respx --with fastapi --with httpx --with sse-starlette --with pydantic-settings --with anyio pytest tests/`
- Smoke: bridge returns 401 on missing/wrong bearer, 502 on upstream unreachable, 200 on `/__bridge/health` and `/__bridge/version`.

### iOS App (SwiftUI, iOS 17) — **all source files written, SPM packages resolve**
- 27 Swift files across `ios/Hermes/App/{Core,Networking,Models,Persistence,Features,Rendering,Haptics,Logging}`.
- 3 resource files in `Rendering/Resources/` (`renderer.html`, `hermes-mobile.css`, `UPSTREAM.txt`).
- `ios/Hermes.xcodeproj/project.pbxproj` — **plutil-lint passes**; SPM deps resolve to **KeychainAccess 4.2.2** and **LDSwiftEventSource 3.3.0** only (ExyteChat removed — see "decisions" below).
- `ios/Hermes/Info.plist` + `Hermes.entitlements` + `Assets.xcassets/` — all plutil-clean.

## What's NOT done — blocks

### iOS Xcode build
- **Blocked**: this machine has Xcode 15.4. The SPM deps themselves are now Swift 5.10-compatible, so a fresh `xcodebuild` after the Xcode 16 install should succeed. The previous failure was transitive (ExyteChat → GiphyUISDK → Swift 6.1 requirement) which is no longer relevant since ExyteChat was removed.
- **To verify after Xcode install**:
  ```bash
  cd ios && xcodebuild build -scheme Hermes -destination 'generic/platform=iOS Simulator,name=iPhone 16'
  ```
  Expected: `** BUILD SUCCEEDED **`.

## Decisions made along the way

1. **Backend Option C (custom bridge) — kept as planned**, since hermes-webui has no bearer auth. Verified working.
2. **Dropped ExyteChat** — kept `MessageListView` as a native `LazyVStack`. The plan's note at the top of the file documents this. Saved us from ExyteChat 3.x's GiphyUISDK → Swift 6.1 dependency chain.
3. **Dropped the `exyte/Chat` SPM package** — no longer needed since we're not using it. The plan's §6 stated this would be Phase 0 cleanup if the ExyteChat pinning became problematic.
4. **Moved `apns2` to optional extra** `[apns]` — incompatible with the modern `h2` chain on Python 3.12. Use `uv sync --extra apns` when you're ready to wire APNs in v1.1.
5. **Pinned Python to <3.13** via `uv sync --python 3.12` — `hyperframe` 5.x (a transitive of `apns2`) uses removed `collections.MutableSet` on 3.10+.

## How to run after Xcode 16 install

```bash
# 1. Open the iOS project in Xcode (the .pbxproj is hand-built; should open cleanly)
open ios/Hermes.xcodeproj
# Set your Development Team in Signing & Capabilities, connect iPhone, ⌘R.

# 2. Run hermes-webui locally (any host)
git clone https://github.com/nesquena/hermes-webui
cd hermes-webui
HERMES_WEBUI_PASSWORD=changeme python3 bootstrap.py   # binds :8787

# 3. Start the bridge
cd backend
cp .env.example .env
# Edit: WEBUI_PASSWORD=changeme, MOBILE_TOKEN=$(python3 -c 'import secrets;print(secrets.token_hex(32))')
uv sync
uv run uvicorn hermes_bridge.main:app --reload --port 8080

# 4. Expose the bridge to the iPhone
cloudflared tunnel --url http://localhost:8080
# → prints a stable https://*.trycloudflare.com URL

# 5. On the iPhone, paste the URL + MOBILE_TOKEN in FirstRun. Done.
```

## Remaining polish (not blocked by Xcode)

- [ ] **Approve / Clarify handlers** — UI buttons render but don't POST to `/api/approval/respond` or `/api/clarify/respond` yet. Wire in `MessageCell.swift`.
- [ ] **Workspace file browser** — v2 feature; skip for v1.
- [ ] **APNs** — wire up `POST /mobile/device` in v1.1 (backend route already exists; iOS needs to register for remote push and POST the token).
- [ ] **Renderer asset vendoring** — currently loads marked/Prism/mermaid from jsDelivr CDN. To support offline, copy the JS into `Rendering/Resources/` and update `<script src>` to relative (instructions in `Resources/UPSTREAM.txt`).
- [ ] **SessionList swipe actions** — rename and delete UI buttons work; pin/archive are visible but don't persist optimistically yet (look at `SessionListViewModel.swift` for the trivial fix).

## Next command to run after Xcode 16 lands

```bash
cd ios && xcodebuild -resolvePackageDependencies -project Hermes.xcodeproj -scheme Hermes && \
xcodebuild build -scheme Hermes -destination 'generic/platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -40
```

If it fails, post the last 40 lines and I'll fix.

## Verification record

- `pytest tests/` — 5 passed, 0 failed (backend bridge + bearer + JSON pass-through).
- `xcodebuild -resolvePackageDependencies` — SPM resolves to KeychainAccess 4.2.2 + LDSwiftEventSource 3.3.0.
- `plutil -lint` — pbxproj + Info.plist + entitlements + 3 asset catalogs: all OK.
- `python3 -m py_compile hermes_bridge/*.py tests/*.py` — clean.
- Bridge live smoke (TestClient + env): 401 on missing bearer ✓, 401 on wrong bearer ✓, 200 on `/__bridge/health` and `/__bridge/version` ✓, 502 on upstream unreachable ✓.
- Full iOS `xcodebuild build` — **NOT VERIFIED** (waiting on Xcode 16+ install).