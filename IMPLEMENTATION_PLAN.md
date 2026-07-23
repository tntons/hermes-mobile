# JARVIS implementation plan

## 0. Scope and non-negotiable boundaries

JARVIS is the user-facing iPhone secretary product. Hermes Agent remains the
upstream engine and keeps its existing provider integrations, memory, skills,
tool loop, WebUI/API contract, and environment variables.

This runbook covers Phase 0 (protect and stabilize) and Phase 1 (JARVIS
product rebrand). Email, calendar, tasks, reminders, scheduled jobs, and
production notifications are later workflow phases; this migration only
prepares their ownership boundary.

Do not:

- fork or rewrite the upstream Hermes Agent source;
- rename `WEBUI_*`, `HERMES_WEBUI_PASSWORD`, `MOBILE_TOKEN`, `HERMES_HOME`,
  `hermes_session`, `X-Hermes-CSRF-Token`, or upstream `/api/*` fields;
- change `com.hermes.mobile` before a tested Keychain migration exists;
- expose `jarvis-agent` directly to the internet or the iPhone;
- delete the legacy bridge or rollback branch before the later API-server path
  passes its migration suite;
- reset, discard, or overwrite unrelated user worktree changes.

## Phase 0 — protect and stabilize

### 0.1 Capture the starting state

Run from the repository root and save the current branch, worktree status, and
recent commits in the handoff record:

```bash
git status --short --branch
git log --oneline --decorate -8
git diff --stat
```

Treat all pre-existing uncommitted changes as user-owned. Do not use
`git reset --hard`, `git checkout --`, or broad deletion commands.

### 0.2 Create the rollback and migration branches

Create a rollback branch at the last known Hermes commit, then create the
migration branch from the current worktree state:

```bash
git branch legacy/hermes-baseline <baseline-commit>
git push origin legacy/hermes-baseline
git switch -c codex/jarvis-migration
```

Record the exact baseline SHA in `docs/ROLLBACK_BASELINE.md` and `HANDOFF.md`.
The baseline must retain the original paths (`ios/Hermes.xcodeproj`,
`ios/Hermes/`, and `backend/hermes_bridge/`) and the original bridge contract.

### 0.3 Verify the original Hermes iOS build

Build the preserved branch from a temporary worktree so the migration worktree
is not changed:

```bash
xcodebuild -project Hermes.xcodeproj -scheme Hermes \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Record success or the exact failure in the rollback documentation. A physical
device build is not required at this stage; it requires a local Apple team.

### 0.4 Stabilize the backend quality gate

Run from `backend/`:

```bash
uv sync
uv run pytest -q
uv run ruff check .
uv run ruff format --check .
```

Fix lint and formatting failures before the product rename. Keep the bridge
behavior compatible while doing so. The SSE client must put the configured
read/write deadline on the HTTPX request itself, not on an unsupported
`AsyncClient.send` argument.

### 0.5 Expand bridge regression coverage

The bridge test suite must cover the migration risks, not only importability:

1. bearer missing/invalid responses and unauthenticated liveness;
2. WebUI login, cookie capture, CSRF header forwarding, and JSON pass-through;
3. one-time upstream 401 re-authentication;
4. JARVIS metadata and version responses;
5. profile and personality defaulting, explicit override preservation, and no
   rewriting of the user message;
6. chat-start run registration;
7. SSE event forwarding, `after_event_id` resume, cursor persistence, and
   terminal-state persistence;
8. session listing and upstream health proxy behavior.

Use isolated temporary SQLite paths in tests. Do not use the developer's
runtime database as a test fixture.

### 0.6 Record the rollback contract

Create `docs/ROLLBACK_BASELINE.md` containing:

- baseline commit and both local/remote branch names;
- preserved iOS and bridge paths;
- bearer, cookie/CSRF, `/health`, and `/api/*` contract details;
- safe inspection commands;
- the rule that the branch remains until the API-server replacement is proven.

### 0.7 Phase 0 exit gate

Phase 0 is complete only when:

- the rollback branch is pinned and pushed;
- the original Hermes simulator build succeeds;
- backend tests, Ruff lint, and Ruff format checks pass;
- the expanded bridge tests cover re-authentication and SSE/run recovery;
- the rollback contract is documented;
- the migration worktree contains no accidental destructive changes.

## Phase 1 — rebrand the product as JARVIS

### 1.1 Rename the iOS product layer

Rename the application-owned Xcode and Swift surface:

- `ios/Hermes.xcodeproj` → `ios/JARVIS.xcodeproj`;
- `ios/Hermes/` → `ios/JARVIS/`;
- target and shared scheme → `JARVIS`;
- `HermesApp` → `JarvisApp`;
- `HermesClient` → `JarvisClient`;
- `HermesAPI` → `JarvisAPI`;
- Hermes model/store/state/theme/log symbols → Jarvis equivalents;
- entitlements and project group paths → JARVIS paths.

Preserve the upstream wire model names and JSON keys. Add `personality` to the
local session model only as a forward-compatible decoded field.

### 1.2 Apply visible JARVIS branding

Update the application-facing surface:

- `CFBundleDisplayName`, `PRODUCT_NAME`, onboarding, settings, errors, demo
  copy, logs, and diagnostics say JARVIS;
- use the JARVIS graphite/green visual system;
- add `AppIcon` plus the source SVG under `ios/JARVIS/Branding/`;
- add `LaunchLogo` and wire it to `UILaunchScreen`;
- compile the asset catalog with `actool`;
- keep the app’s actual product name and generated `.app` name JARVIS.

### 1.3 Preserve release and Keychain compatibility

During development, keep all of the following unchanged:

- `PRODUCT_BUNDLE_IDENTIFIER = com.hermes.mobile`;
- Keychain service and fallback UserDefaults suite;
- existing Keychain keys and migration data;
- APNs topic and background-task identifier;
- upstream bearer/API field names.

Do not change the bundle identifier until a release task implements and tests a
one-time read/migrate/write flow for existing Keychain values.

### 1.4 Rename the bridge package and metadata

Move `backend/hermes_bridge/` to `backend/jarvis_bridge/` and update:

- `pyproject.toml` package/project metadata;
- FastAPI title, description, version response, and logger names;
- Dockerfile imports and startup command;
- bridge-facing error and diagnostic text.

Keep the upstream WebUI client internals (`hermes_session`, CSRF header,
`WEBUI_PASSWORD`, and upstream URLs) intact.

### 1.5 Wire the JARVIS profile and secretary persona

Add settings with these defaults:

```text
JARVIS_PROFILE=jarvis
JARVIS_PERSONALITY=jarvis
```

When a mobile request omits `profile` or `personality`, the bridge adds the
configured default. Explicit values remain unchanged. The original user
message must pass through unchanged.

Because upstream `/api/session/new` does not consume `personality` directly,
the bridge applies it through `/api/personality/set` after creating a session
and before starting a chat turn.

Store the actual secretary instructions in:

```text
backend/deployment/jarvis-profile/config.yaml
```

The persona should be concise, discreet, action-oriented, and clear about
confirmation before external side effects. It must not claim tool actions
succeeded without a confirmed tool result.

### 1.6 Make deployment self-contained and private

Rename the Compose runtime services:

- `jarvis-agent` — upstream Hermes Agent/WebUI image, private only;
- `jarvis-bridge` — JARVIS FastAPI bridge, the only published local port;
- `jarvis-cloudflared` — optional named Cloudflare Tunnel service.

Add the non-public `jarvis-profile-init` helper. On first startup it copies
the tracked JARVIS profile into the mounted Hermes home only when the target
file is absent; it never overwrites operator-managed configuration.

Required topology:

```text
iPhone → HTTPS/Cloudflare Tunnel → jarvis-bridge → private jarvis-agent
```

The agent must have no host-published port. The bridge must bind the local
development port only to `127.0.0.1`.

### 1.7 Update documentation and handoff

Keep these synchronized with the implementation:

- `README.md` — product and runtime overview;
- `AGENTS.md` — current commands and compatibility rules;
- `HANDOFF.md` — current status and verification record;
- `DESIGN_SYSTEM.md` — JARVIS visual language;
- `backend/README.md` — local/Docker deployment;
- `docs/PROJECT_CONTEXT.md`, `docs/CURRENT_STATE.md`, `docs/DECISIONS.md`, and
  `docs/NEXT_STEPS.md` — durable context;
- `docs/ROLLBACK_BASELINE.md` — rollback evidence.

Document the real-runtime and named-tunnel smoke test as an operator step when
credentials are not available in the development workspace.

### 1.8 Phase 1 acceptance gates

Backend:

```bash
cd backend
uv run pytest -q
uv run ruff check .
uv run ruff format --check .
python3 -m py_compile jarvis_bridge/*.py tests/*.py
WEBUI_PASSWORD=test MOBILE_TOKEN=test docker compose config
```

iOS:

```bash
cd ios
xcodebuild -resolvePackageDependencies -project JARVIS.xcodeproj -scheme JARVIS
xcrun actool --compile <temporary-output> --platform iphonesimulator \
  --minimum-deployment-target 17.0 --app-icon AppIcon Assets.xcassets
xcodebuild -project JARVIS.xcodeproj -scheme JARVIS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

The JARVIS target must compile with `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
The preserved Hermes target must also remain buildable from
`legacy/hermes-baseline`.

Static compatibility audit:

- `com.hermes.mobile`, Keychain service, APNs topic, and background-task
  identifiers remain unchanged;
- no product-layer `HermesApp`, `HermesClient`, `HermesAPI`, old project path,
  or old bridge package remains on `main`;
- user messages are not rewritten;
- only the bridge publishes a host port;
- the profile template parses and the seeder is non-destructive.

## Merge and release-point procedure

After all Phase 0/1 gates pass:

```bash
git switch main
git merge --ff-only codex/jarvis-migration
git push origin main
```

Confirm that `main` contains JARVIS and `legacy/hermes-baseline` still points
to the exact recorded baseline SHA. Before the eventual release bundle-ID
change, create a separate migration plan for Keychain compatibility, signing,
APNs production, Cloudflare DNS, and device smoke tests.

## Explicitly deferred

- Gmail and Google Calendar connectors;
- JARVIS task/reminder data model and scheduled jobs;
- production APNs implementation;
- API-server replacement for the WebUI bridge;
- final bundle identifier and Keychain namespace migration;
- production Cloudflare Tunnel credentials and hostname.
