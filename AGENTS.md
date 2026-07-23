# JARVIS repository instructions

Read `HANDOFF.md` and `IMPLEMENTATION_PLAN.md` before changing architecture or
deployment. `legacy/hermes-baseline` is the rollback branch for the original
Hermes-branded project. Do not reset, delete, or overwrite user changes.

## iOS

Run from `ios/`. The product is JARVIS, but the release bundle identifier and
Keychain service remain `com.hermes.mobile` until the release migration.

```bash
xcodebuild -resolvePackageDependencies -project JARVIS.xcodeproj -scheme JARVIS
xcodebuild -project JARVIS.xcodeproj -scheme JARVIS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

For a real device, set the development team locally in Xcode; never commit a
personal team identifier.

## Backend

Run from `backend/`. Requires Python 3.11+ and `uv`.

```bash
uv sync
uv run uvicorn jarvis_bridge.main:app --reload --port 8080
uv run pytest -q
uv run ruff check .
uv run ruff format --check .
```

## Runtime boundaries

- `backend/jarvis_bridge/` owns the JARVIS-facing bearer bridge.
- `ios/JARVIS/` owns the JARVIS SwiftUI app.
- `jarvis-agent` is still the upstream Hermes Agent/WebUI runtime.
- Preserve upstream names such as `WEBUI_*`, `HERMES_WEBUI_PASSWORD`,
  `MOBILE_TOKEN`, `/api/*`, and `hermes_session` where the dependency requires
  them.
- Keep the agent private behind the bridge and Cloudflare Tunnel.
- Never commit `.env`, bearer tokens, APNs keys, tunnel tokens, or runtime data.
