# JARVIS migration handoff

## Current state

The repository has been migrated from the Hermes-branded mobile product to
JARVIS. The JARVIS implementation is now on `main`; it was built on
`codex/jarvis-migration` before the fast-forward merge.
`legacy/hermes-baseline` is pinned to the original `main` commit
`5be05e97ee6dc58bbdedfdff3ee35102028fe61a` and is the rollback baseline.

## Architecture

```text
iPhone JARVIS app
  → bearer HTTPS
  → jarvis-bridge (FastAPI)
  → private jarvis-agent container
  → upstream Hermes Agent/WebUI runtime
```

The bridge owns mobile authentication, SSE forwarding/resume, run tracking,
and product metadata. Hermes Agent remains upstream and is not forked.

## Implemented in this migration

- Backend package renamed to `jarvis_bridge`.
- FastAPI metadata and bridge version identify JARVIS.
- Default upstream profile and personality selection is `jarvis` when a request
  does not provide an explicit value. The bridge persists the personality via
  the upstream `/api/personality/set` route because `/api/session/new` does not
  consume that field directly.
- Backend regression suite expanded to 10 tests.
- Ruff lint and format checks pass.
- iOS project, target, scheme, source paths, and application-facing Swift types
  are renamed to JARVIS/Jarvis.
- `CFBundleDisplayName` is `JARVIS`.
- Bundle identifier, Keychain service, APNs topic, and upstream environment
  names remain compatible with the existing Hermes installation.
- JARVIS app icon added at
  `ios/JARVIS/Assets.xcassets/AppIcon.appiconset/icon.png`.
- Docker services are `jarvis-agent` and `jarvis-bridge`; Cloudflare is
  documented as `jarvis-cloudflared`.
- The tracked upstream persona template is
  `backend/deployment/jarvis-profile/config.yaml`; it must be installed into
  the mounted Hermes home before deployment.
- Root, backend, design-system, handoff, and agent documentation updated.

## Verification record

Passed:

- `backend/uv run pytest -q` — 10 passed.
- `backend/uv run ruff check .` — passed.
- `backend/uv run ruff format --check .` — passed.
- `backend/python3 -m py_compile jarvis_bridge/*.py tests/*.py` — passed.
- `ios/xcodebuild -resolvePackageDependencies -project JARVIS.xcodeproj -scheme JARVIS` — passed.
- `ios/actool` compilation of the JARVIS asset catalog — passed.
- Fresh derived-data simulator build of the JARVIS target with signing disabled — passed.

The physical-device build still requires a developer team configured locally.
There is no iOS unit-test target yet; the existing scheme has an empty test
action, so simulator compile and runtime smoke checks are the current iOS gate.

## Important compatibility rules

- Do not rename `WEBUI_*`, `HERMES_WEBUI_PASSWORD`, `MOBILE_TOKEN`,
  `HERMES_HOME`, `hermes_session`, or upstream `/api/*` field names.
- Do not change `com.hermes.mobile` until the release Keychain migration is
  designed and tested.
- Do not delete the WebUI bridge until the future API-server replacement has
  passed all migration tests.
- Never commit secrets, `.env`, APNs keys, tunnel tokens, SQLite runtime data,
  or personal signing identifiers.
