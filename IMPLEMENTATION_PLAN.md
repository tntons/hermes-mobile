# JARVIS implementation plan

## Product direction

JARVIS is the user-facing iPhone secretary product. Hermes Agent remains the
underlying engine and keeps its existing API, environment variables, memory,
skills, provider integrations, and WebUI contract.

The current migration covers Phase 0 and Phase 1 only. Email, calendar, tasks,
reminders, scheduled jobs, and production notifications are later phases.

## Phase 0 — protect and stabilize

1. Keep `legacy/hermes-baseline` pinned to the original Hermes commit and work
   on `codex/jarvis-migration`.
2. Preserve any pre-existing worktree changes; never reset or discard them.
3. Run the existing iOS compile gate with signing disabled and document the
   local-team requirement for device builds.
4. Fix backend Ruff lint and formatting failures.
5. Expand bridge tests around bearer auth, WebUI proxying, re-authentication,
   SSE resume, run state, and liveness routes.
6. Require `pytest`, `ruff check`, and `ruff format --check` to pass before
   rebranding work is accepted.
7. Record the current bridge and API contract as the rollback baseline.

## Phase 1 — JARVIS product rebrand

### iOS

- Rename the project, target, scheme, source directory, and application-facing
  Swift types to JARVIS/Jarvis.
- Set the display name and visible copy to JARVIS.
- Add the JARVIS icon and validate the asset catalog with `actool`.
- Keep `com.hermes.mobile`, Keychain service, fallback suite, Keychain keys,
  and APNs topic unchanged until the release migration.
- Preserve upstream-compatible route and Codable field names.

### Bridge and deployment

- Rename `backend/hermes_bridge` to `backend/jarvis_bridge`.
- Update package, FastAPI, logger, Dockerfile, and API metadata to JARVIS.
- Rename Compose services to `jarvis-agent`, `jarvis-bridge`, and the optional
  `jarvis-cloudflared`.
- Keep the upstream Hermes image, `WEBUI_*` configuration, cookie/CSRF names,
  and `/api/*` contract unchanged.
- Default missing session/chat profiles to the upstream-supported `jarvis`
  profile using `JARVIS_PROFILE`; preserve explicit profiles.
- Default missing session/chat personalities to `jarvis` using
  `JARVIS_PERSONALITY`; persist them through the upstream personality endpoint.
- Provide the actual secretary system instructions in
  `backend/deployment/jarvis-profile/config.yaml`. Install that file into the
  deployed Hermes profile; do not rewrite bridge user messages or upstream
  source.

### Documentation

- Keep `README.md`, `AGENTS.md`, `HANDOFF.md`, `DESIGN_SYSTEM.md`, and
  `backend/README.md` consistent with the JARVIS architecture.
- Record technical Hermes names as upstream compatibility identifiers.
- Keep the WebUI bridge until the later API-server migration passes its full
  migration suite.

## Acceptance gates

Backend:

```bash
cd backend
uv run pytest -q
uv run ruff check .
uv run ruff format --check .
```

iOS:

```bash
cd ios
xcodebuild -resolvePackageDependencies -project JARVIS.xcodeproj -scheme JARVIS
xcodebuild -project JARVIS.xcodeproj -scheme JARVIS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Integration must verify JARVIS metadata, profile/personality defaulting, session
listing, chat start, SSE resume, Keychain compatibility, and private Docker
service boundaries.
