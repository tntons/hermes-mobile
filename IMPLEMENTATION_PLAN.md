# Hermes iOS — Implementation Plan (file-level)

> Hand this document to the implementing agent. It expands §6 of the project brief into per-step, file-level tasks with concrete endpoints, Codable types, and acceptance criteria.
>
> **STATUS of the hard unknowns (already resolved by research, do not re-investigate):**
> - The full hermes-webui HTTP/SSE contract has been extracted (see §3 below). Implement against those exact field names.
> - hermes-webui auth is **cookie + CSRF**, there is **no native bearer token**. We therefore ship a thin custom backend (`backend/`) that wraps hermes-webui and exposes **bearer auth** to the phone. See §1.
> - The webui already implements **run-journal resume** (`stream_id` = `run_id`, replay via `after_event_id`). Seamless foreground/background-return works almost for free. APNs is additive (v1.1).

---

## 1. Decision summary (locked — flag the backend Option)

**Backend Option chosen: Option C — "Hermes Mobile Bridge" (custom, full control, reuses hermes-webui wholesale).**

Rationale: the brief's Option A (point phone at hermes-webui directly) is blocked by hermes-webui having **no bearer auth** (cookie + CSRF only — see contract §3.D). The brief's Option B (OpenAI-compatible gateway) loses sessions/workspace/skills/cron. Option C gets both: we run hermes-webui unchanged for all its agent muscle, and put a ~600-line FastAPI bridge in front of it that:

1. Authenticates the iPhone with a single **bearer token** (env `HERMES_MOBILE_TOKEN`).
2. Performs a one-time `POST /api/auth/login` against the webui with the password, caches the `hermes_session` cookie + derives `X-Hermes-CSRF-Token`, and transparently attaches them on every proxied call.
3. Re-exposes the exact webui JSON+SSE contract over bearer (so the iOS `HermesAPI.swift` mirrors webui's routes 1:1).
4. Adds a small **runs registry** (SQLite: `stream_id → status, last_event_id, session_id, device_token`) and fires **APNs** on terminal events (`done` / `apperror` / `cancel`) so backgrounded turns notify the phone. (APNs wiring is v1.1; the hook is built in v1.)
5. Terminates SSE cleanly through buffering proxies (the bridge always streams chunked) and applies a long write deadline so the mobile socket is never prematurely dropped by the webui's 20 s deadline.

This is the fastest path to "seamless backend + stable connection" because **resume is already implemented by the webui**; we just expose it over a stable bearer token.

**Other locked decisions:**
| Area | Decision |
|---|---|
| Min target | iOS 17.0, Xcode 16, Swift 5.10+/6 |
| Architecture | MVVM + `@Observable` + `actor`-isolated services |
| Persistence | SwiftData (cache + `Last-Event-ID` per stream) + Keychain (token) |
| Chat UI | exyte/Chat (SPM) with custom `messageBuilder` cell |
| SSE | launchdarkly/swift-eventsource (LDSwiftEventSource) |
| Secrets | kishikawakatsumi/KeychainAccess |
| Code highlight | Prism.js inside the WebView (no native lib needed for v1); HighlightSwift optional later |
| Markdown/diagrams | marked.js + Prism.js + mermaid.min.js bundled in the WebView |
| Backend lang | Python 3.11 + FastAPI + httpx + sse-starlette + apns2 |
| Crash reporting | Deferred to v2; use `os.Logger` (`subsystem = "com.hermes.mobile"`) for v1 |
| Remote transport | Cloudflare Tunnel (stable HTTPS hostname) fronting the bridge. **No Tailscale requirement on the phone.** |

**v1 scope (ship this — do NOT bleed v2/v3 in):**
First-run (gateway URL + bearer token), session list, streaming chat, hybrid markdown/code/Mermaid rendering, session CRUD, foreground SSE resilience + return-from-background replay.

**v1.1 / v2 (explicitly out of v1):**
APNs push on backgrounded completion, workspace file browser, attachments, profiles switcher, slash-command autocomplete UI, haptics, Face ID, Live Activity, widget.

---

## 2. Architecture (data flow)

```
┌──────────────── iPhone (SwiftUI shell) ────────────────┐
│  HermesApp ─ AppState (@Observable, scenePhase, NWPathMonitor)
│    │
│    ├─ FirstRunView ──Keychain──► gatewayURL, bearerToken, profile
│    ├─ SessionListView ──► SessionListViewModel (@Observable)
│    ├─ ConversationView ──► ConversationViewModel (@Observable)
│    │     ├─ MessageListView (exyte/Chat, custom messageBuilder)
│    │     │     └─ MessageCell
│    │     │          ├─ ToolCallCard (native SwiftUI)        ← tool / tool_complete / approval
│    │     │          └─ MarkdownWebView (WKWebView)          ← token / reasoning / done body
│    │     └─ ComposerView (native keyboard + haptics)
│    ├─ SettingsView
│    │
│    └─ HermesClient (actor)  ◄── owns all network + SSE lifecycle
│          ├─ URLSession (bearer header, JSON)
│          ├─ LDSwiftEventSource (reconnect + Last-Event-ID)
│          └─ SwiftData Repository (cache + lastEventID)
└─────────────────────────────────────────────────────────┘
                         │ HTTPS  (Cloudflare Tunnel → stable *.trycloudflare.com / named hostname)
                         │ Authorization: Bearer <HERMES_MOBILE_TOKEN>
                         ▼
┌──────────── backend/  (FastAPI — "Hermes Mobile Bridge") ────────────┐
│  bearer auth middleware  →  webui_client (httpx, cached cookie+CSRF)  │
│  proxy: /api/* 1:1 to webui                                          │
│  runs registry (SQLite): stream_id → status, last_event_id, device   │
│  SSE forwarder (chunked, no buffering) + APNs hook on terminal evts  │
└──────────────────────────────────────────────────────────────────────┘
                         │ loopback HTTP (127.0.0.1:8787)
                         ▼
                hermes-webui  (unchanged — agent, sessions, workspace, skills, cron)
```

State ownership: one `actor HermesClient` owns all network/SSE (no data races on streaming deltas); per-screen `@Observable` view models hold UI state; `Message` array mutations happen on `@MainActor`.

---

## 3. API contract (baked in — implement against these exact names)

These are the real hermes-webui routes/fields (verified against `master`). The bridge proxies them 1:1 over bearer; the iOS `Codable` structs below match.

### 3.1 Auth model on the phone (post-bridge)
- Header on **every** request: `Authorization: Bearer <HERMES_MOBILE_TOKEN>`.
- No cookie, no CSRF on the phone — the bridge handles those against the webui.
- 401 from the bridge → token wrong/expired → bounce to `FirstRunView`.

### 3.2 Endpoints the iOS client uses (v1)
| Method | Path (on the bridge = identical to webui) | Request | Response (salient fields) |
|---|---|---|---|
| GET | `/health` | — | `{status, active_streams, active_runs, uptime_seconds}` — liveness probe |
| GET | `/api/sessions` | query `include_archived`, `archived_limit`, `archived_offset`, `all_profiles` | `{sessions:[Session.compact], active_profile, server_time, server_tz, archived_count, …}` |
| GET | `/api/session` | query `session_id`, `messages=1`, `msg_limit`, `msg_before`, `resolve_model=1` | `{session: Session.compact + messages:[Message], tool_calls:[ToolCall], todo_state?, _messages_truncated, _messages_offset}` |
| POST | `/api/session/new` | `{workspace?, model?, model_provider?, profile?}` | `{session: Session.compact}` |
| POST | `/api/session/rename` | `{session_id, title}` | `{session}` |
| POST | `/api/session/delete` | `{session_id, worktree_remove?}` | `{ok}` |
| POST | `/api/session/pin` | `{session_id, pinned}` | `{session}` |
| POST | `/api/session/archive` | `{session_id, archived}` | `{session}` |
| POST | `/api/chat/start` | `{session_id, message, attachments?, workspace?, model?, model_provider?, profile?}` | `{stream_id, session_id, turn_id?, effective_model?, error?}` |
| GET | `/api/chat/stream` | query `stream_id`, and on reconnect `after_event_id=<stream_id>:<seq>` | SSE stream (see §3.4) |
| GET | `/api/chat/stream/status` | query `stream_id` | `{active, stream_id, replay_available, journal?}` |
| GET | `/api/chat/cancel` | query `stream_id` | `{ok, cancelled, stream_id}` (note: **GET**) |

> **Note on `after_event_id`:** the webui accepts either the standard `Last-Event-ID` header OR `after_event_id` query param (preferred — robust against proxies that strip headers). The iOS client appends `after_event_id=<lastId>` to the stream URL on every reconnect.

### 3.3 Codable types — `App/Models/HermesModels.swift`

```swift
// All timestamps are Double (unix seconds). IDs are String.
public struct Session: Codable, Identifiable, Hashable {
    public var id: String { session_id }
    public let session_id: String
    public var title: String
    public var workspace: String?
    public var model: String?
    public var model_provider: String?
    public var message_count: Int
    public var created_at: Double
    public var updated_at: Double
    public var last_message_at: Double?
    public var pinned: Bool
    public var archived: Bool
    public var project_id: String?
    public var profile: String?
    public var input_tokens: Int
    public var output_tokens: Int
    public var estimated_cost: Double?
    public var is_streaming: Bool
    public var has_pending_user_message: Bool
    public var active_stream_id: String?
}

public struct SessionListResponse: Codable {
    public let sessions: [Session]
    public let active_profile: String?
    public let server_time: Double?
    public let server_tz: String?
    public let archived_count: Int?
}

public struct SessionDetailResponse: Codable {
    public let session: Session
    public let messages: [Message]
    public let tool_calls: [ToolCallRef]?
    public let todo_state: TodoState?
    public let _messages_truncated: Bool?
}

public struct Message: Codable, Identifiable, Hashable {
    public var id: String { "\(role)-\(timestamp)-\(content_hash)" }   // see impl note
    public var role: Role
    public var content: MessageContent           // String OR content-block array
    public var timestamp: Double
    public var reasoning: String?
    public var attachments: [Attachment]?
    public var tool_calls: [ToolCall]?
    public var tool_call_id: String?
    public var _partial: Bool?
    public var _error: Bool?
    public enum Role: String, Codable { case user, assistant, system, tool }
}

public enum MessageContent: Codable {                 // webui returns either form
    case text(String)
    case blocks([ContentBlock])
    public struct ContentBlock: Codable { let type: String; let text: String? }   // "text" | "image" | ...
}

public struct Attachment: Codable, Hashable { let name: String; let path: String?; let mime: String?; let size: Int?; let is_image: Bool? }

public struct ToolCall: Codable, Identifiable, Hashable {
    public var id: String { "\(name)-\(argsHash)" }
    public var name: String
    public var args: AnyCodable?            // tool-specific JSON; see AnyCodable note
    public var result: AnyCodable?
    public var preview: String?
    public var duration: Double?
    public var is_error: Bool?
}

public struct ToolCallRef: Codable, Hashable { let name: String; let args: AnyCodable?; let result: AnyCodable?; let preview: String? }

public struct ChatStartResponse: Codable {
    public let stream_id: String
    public let session_id: String
    public let turn_id: String?
    public let effective_model: String?
    public let error: String?
}

public struct TodoState: Codable { /* opaque — render best-effort */ public let items: [AnyCodable]? }

// Session CRUD request bodies
public struct NewSessionRequest: Codable { public let workspace: String?; public let model: String?; public let profile: String? }
public struct RenameSessionRequest: Codable { public let session_id: String; public let title: String }
public struct DeleteSessionRequest: Codable { public let session_id: String; public let worktree_remove: Bool? }
public struct PinSessionRequest: Codable { public let session_id: String; public let pinned: Bool }
public struct ArchiveSessionRequest: Codable { public let session_id: String; public let archived: Bool }

// AnyCodable: a tiny dynamic JSON wrapper (the codebase must add one; ~40 lines, see AnyEncodable from Apple's swift-server examples). Used for tool args/result whose shape is tool-specific.
```

### 3.4 SSE event enum — `App/Models/SSEEvent.swift`

Wire format on the stream (one event):
```
id: <stream_id>:<seq>
event: <name>
data: <json>

```
Heartbeat (5 s idle): `": heartbeat"` (a comment — LDSwiftEventSource delivers it via `onComment` / `onOpened`; ignore).

```swift
public enum SSEEvent {
    case token(text: String)                                 // event:"token"   data:{"text"}
    case reasoning(text: String)                             // event:"reasoning"
    case interimAssistant(text: String, alreadyStreamed: Bool)
    case tool(ToolEvent)                                     // event:"tool"        -> tool.started
    case toolComplete(ToolCompleteEvent)                     // event:"tool_complete" -> tool.completed
    case approval(ApprovalEvent)
    case clarify(ClarifyEvent)
    case metering(MeteringEvent)                             // ≤10 Hz; ignore for v1 UI
    case contextStatus(AnyCodable)
    case compressing
    case compressed(CompressedEvent)                         // session id may rotate
    case warning(WarningEvent)
    case todoState(AnyCodable)
    case stateSaved(AnyCodable)
    case goal(GoalEvent)
    case goalContinue(GoalEvent)
    case done(DoneEvent)                                     // TERMINAL success
    case streamEnd                                            // TERMINAL always after done
    case cancel(CancelEvent)                                 // TERMINAL
    case appError(AppErrorEvent)                             // TERMINAL failure
    case keepAlive                                            // comment heartbeat

    public struct ToolEvent        { let name: String; let preview: String?; let args: AnyCodable? }
    public struct ToolCompleteEvent{ let name: String; let preview: String?; let args: AnyCodable?; let duration: Double?; let is_error: Bool? }
    public struct ApprovalEvent    { let command: String; let description: String; let pattern_key: String?; let pattern_keys: [String]?; let choices: [String]; let allow_permanent: Bool?; let run_id: String?; let approval_id: String? }
    public struct ClarifyEvent     { let question: String; let choices_offered: [String]?; let timeout_seconds: Int? }
    public struct CompressedEvent  { let old_session_id: String; let new_session_id: String?; let continuation_session_id: String? }
    public struct WarningEvent     { let type: String?; let message: String }
    public struct GoalEvent        { let state: String?; let message: String?; let message_key: String? }
    public struct DoneEvent        { let session: SessionDetailResponse?; let usage: Usage?
                                     let terminal_state: String?; let terminal_reason: String? }
    public struct CancelEvent      { let message: String?; let type: String?; let status: String?; let session_id: String? }
    public struct AppErrorEvent    { let label: String?; let type: String; let message: String; let hint: String?; let details: String?; let session_id: String?
                                     let terminal_state: String?; let terminal_reason: String? }
    public struct MeteringEvent    { let usage: AnyCodable?; let estimated: Bool? }
    public struct Usage            { let input_tokens: Int?; let output_tokens: Int?; let estimated_cost: Double? }
}

public enum TerminalState: Equatable {
    case success, cancelled, error(String)      // derived from done / cancel / apperror
}
```

> `stream_end` is always emitted after `done` — the client treats **both** `done` and `stream_end` as "stop the spinner"; `cancel`/`apperror` are terminal failures. Resume terminates at the first terminal event in the journal.

### 3.5 Resume semantics (critical — this is what makes the connection "seamless")
- `POST /api/chat/start` → `{stream_id}`. Persist `stream_id` + `session_id` in SwiftData.
- Open `GET /api/chat/stream?stream_id=<id>`. Track the **last `id:` line** seen (format `<stream_id>:<seq>`).
- On any disconnect (network change, app foregrounded after background, 20 s webui write-deadline drop), LDSwiftEventSource auto-reconnects; the client appends `&after_event_id=<lastId>` to the URL. The webui **run journal** replays every missed event, then continues live. No token loss.
- If the run already finished while the phone was disconnected, the journal replay still delivers the full event log (ending in `done`/`stream_end`), so the conversation ends in a consistent state.
- The agent worker is a server-side daemon thread independent of the SSE socket, so **the turn keeps running while the phone is backgrounded.** This is the key fact that makes iOS backgrounding survivable even without APNs.

---

## 4. Repository layout (monorepo)

```
hermes-mobile/
├─ IMPLEMENTATION_PLAN.md            ← this file
├─ AGENTS.md                         ← build/test commands for the implementing agent (see §8)
├─ backend/                          ← Hermes Mobile Bridge (FastAPI)
│  ├─ pyproject.toml
│  ├─ Dockerfile
│  ├─ docker-compose.yml             ← runs webui + bridge + (optional) cloudflared
│  ├─ .env.example
│  └─ hermes_bridge/
│     ├─ __init__.py
│     ├─ main.py                     ← FastAPI app, lifespan, route mounting
│     ├─ config.py                   ← pydantic-settings (env)
│     ├─ auth.py                     ← bearer middleware
│     ├─ webui_client.py             ← httpx.AsyncClient, cached cookie + CSRF
│     ├─ proxy.py                    ← generic pass-through for /api/* (JSON)
│     ├─ sse_proxy.py                ← SSE forwarder (chunked, no buffering), tracks last_event_id
│     ├─ runs.py                     ← SQLite runs registry (stream_id, status, last_event_id, device_token)
│     ├─ apns.py                     ← apns2 client + send() (hook called from sse_proxy on terminal events)
│     └─ device_tokens.py            ← POST /mobile/device  (register push token)
└─ ios/
   └─ Hermes.xcodeproj               ← Xcode 16 project (create via `xcodegen` or manually; see Phase 0)
      └─ Hermes/
         ├─ HermesApp.swift
         ├─ App/
         │  ├─ Core/
         │  │  ├─ AppState.swift            ← @Observable: authState, scenePhase, networkMonitor
         │  │  ├─ HermesClient.swift        ← actor: all HTTP + SSE lifecycle
         │  │  ├─ APIConfig.swift           ← gatewayURL + token from Keychain
         │  │  └─ AnyCodable.swift
         │  ├─ Networking/
         │  │  ├─ HermesAPI.swift           ← endpoint enum + request builders
         │  │  ├─ APIError.swift
         │  │  ├─ SSEEventHandler.swift     ← LDSwiftEventSource delegate → SSEEvent parsing
         │  │  └─ EventSource+Config.swift
         │  ├─ Models/
         │  │  ├─ HermesModels.swift        ← §3.3
         │  │  ├─ SSEEvent.swift            ← §3.4
         │  │  └─ ChatMessage.swift         ← UI-facing model (wraps Message + streaming state)
         │  ├─ Persistence/
         │  │  ├─ KeychainStore.swift       ← KeychainAccess wrapper
         │  │  ├─ HermesStore.swift         ← SwiftData container + DAOs
         │  │  └─ Models/  (SwiftData @Model: Session, Message, StreamCursor)
         │  ├─ Features/
         │  │  ├─ FirstRun/FirstRunView.swift + FirstRunViewModel.swift
         │  │  ├─ Sessions/SessionListView.swift + SessionListViewModel.swift
         │  │  ├─ Conversation/
         │  │  │  ├─ ConversationView.swift + ConversationViewModel.swift
         │  │  │  ├─ MessageListView.swift         ← exyte/Chat adapter
         │  │  │  ├─ MessageCell.swift              ← picks ToolCallCard vs MarkdownWebView
         │  │  │  ├─ ToolCallCard.swift
         │  │  │  └─ ComposerView.swift
         │  │  └─ Settings/SettingsView.swift
         │  ├─ Rendering/
         │  │  ├─ MarkdownWebView.swift            ← WKUIViewRepresentable
         │  │  ├─ WebViewPool.swift                ← optional pool (1 per visible cell)
         │  │  ├─ WebViewConfig.swift              ← hide accessory bar, keyboard inset KVO
         │  │  └─ Resources/
         │  │     ├─ renderer.html                 ← shell: loads marked+prism+mermaid, exposes window.render(md)
         │  │     ├─ marked.min.js
         │  │     ├─ prism-core.min.js + prism-*.js (lang components)
         │  │     ├─ mermaid.min.js
         │  │     ├─ github-markdown.css           ← copied/adapted from hermes-webui/static
         │  │     └─ hermes-mobile.css             ← ported polish (safe-area, 44pt, 16pt font, --keyboard-inset)
         │  ├─ Haptics/HapticManager.swift
         │  └─ Logging/Logger+.swift               ← os.Logger subsystem "com.hermes.mobile"
         ├─ Info.plist                              ← ATS (NSAllowsLocalNetworking for dev), UISupportedInterfaceOrients
         ├─ Hermes.entitlements                     ← Keychain sharing group (later: Push, App Groups)
         └─ Assets.xcassets
```

---

## 5. Phased build plan (file-level)

Each phase has: **Files**, **What each does**, **Acceptance**. Do not start the next phase until the current one's acceptance passes end-to-end on a physical device (or simulator where noted).

### Phase 0 — Environment & contract (0.5 day)
**Goal:** repo skeleton, deps wired, contract file committed, webui running locally.

**Tasks**
1. `git init` the monorepo; add `.gitignore` (Swift/Xcode/Python/node/`.env`/`*.p8`).
2. Write `AGENTS.md` at repo root with the exact build/test commands (see §8) — the implementing agent reads this first.
3. Create `ios/Hermes.xcodeproj` (iOS 17, SwiftUI lifecycle, bundle id `com.hermes.mobile`). Add SPM deps (pin versions):
   - `https://github.com/exyte/Chat` — `from: "3.1.2"` (verify latest tag at impl time)
   - `https://github.com/launchdarkly/swift-eventsource` — `from: "3.0.0"`
   - `https://github.com/kishikawakatsumi/KeychainAccess` — `from: "4.2.2"`
   - (optional, v1.1) `https://github.com/appstefan/HighlightSwift` — `from: "1.3.0"`
4. Create `backend/` FastAPI skeleton with `pyproject.toml` (deps: `fastapi`, `uvicorn[standard]`, `httpx`, `sse-starlette`, `apns2`, `pydantic-settings`, `anyio`).
5. Run hermes-webui locally (`git clone nesquena/hermes-webui && python3 bootstrap.py`); `curl http://127.0.0.1:8787/health` must return `{"status":"ok"}`.
6. Commit `ios/.../App/Models/HermesModels.swift` and `SSEEvent.swift` from §3.3/§3.4 verbatim. These are the **single source of truth** for the transport layer.

**Acceptance**
- `xcodebuild -scheme Hermes -destination 'platform=iOS Simulator,name=iPhone 16' build` succeeds with all SPM deps resolving.
- `uv run uvicorn hermes_bridge.main:app --reload` boots the bridge skeleton and `GET /health` returns 200.
- `HermesModels.swift` compiles; decode the sample JSON fixtures in `backend/tests/fixtures/` (grab 2–3 real responses from the running webui) without error.

---

### Phase 1 — Backend bridge: bearer auth + sessions proxy (1 day)
**Goal:** the phone can authenticate with a bearer token and list sessions through the bridge. DoD: `curl -H "Authorization: Bearer $TOKEN" https://<bridge>/api/sessions` returns the session list.

**Files**
- `backend/hermes_bridge/config.py` — `Settings(BaseSettings)`: `webui_base_url` (default `http://127.0.0.1:8787`), `webui_password: SecretStr`, `mobile_token: SecretStr`, `session_ttl_seconds`, `apns_team_id`, `apns_key_id`, `apns_key_path`, `apns_topic` (all APNs fields optional for v1).
- `backend/hermes_bridge/webui_client.py` — singleton `WebUIClient`:
  - Holds an `httpx.AsyncClient` and lazily performs `POST /api/auth/login {"password": ...}`; stores the `hermes_session` cookie; derives `X-Hermes-CSRF-Token` by calling `GET /api/auth/status` (the webui exposes the CSRF token to authenticated JS — mirror that call) **or** re-derives via the documented derivation (HMAC of the server-side token). Implement the simplest working path first: read the CSRF token from the webui's authenticated status endpoint. Document which path is used.
  - Auto-re-login on 401 from the webui.
- `backend/hermes_bridge/auth.py` — FastAPI dependency `require_bearer(authorization=Header())` comparing to `settings.mobile_token`; 401 on mismatch.
- `backend/hermes_bridge/proxy.py` — generic `proxy(request: Request, path: str)` that forwards method+body+query to the webui via `WebUIClient`, copying JSON back. Mount under `/api/{path:path}` and `/health`.
- `backend/hermes_bridge/main.py` — wire lifespan (init `WebUIClient`, APNs client if configured), mount routes, add `X-Accel-Buffering: no` + `Cache-Control: no-cache` to all SSE responses globally.
- `backend/Dockerfile`, `backend/docker-compose.yml` (services: `webui`, `bridge`; bridge depends_on webui healthcheck; optional `cloudflared` tunnel service for stable hostname).
- `backend/.env.example` documenting every var.

**Acceptance**
- With `HERMES_WEBUI_PASSWORD` set on the webui and `HERMES_MOBILE_TOKEN` set on the bridge: `curl -H "Authorization: Bearer $HERMES_MOBILE_TOKEN" http://127.0.0.1:8080/api/sessions` returns the same JSON as a browser session.
- Wrong/missing bearer → 401.
- Bridge survives a webui restart by re-logging in on next request (no manual restart).
- Cloudflare Tunnel (run `cloudflared tunnel --url http://localhost:8080` locally) yields a stable HTTPS hostname reachable from the phone's cell network.

---

### Phase 2 — First-run + Keychain + session list (1 day)
**Goal:** install on iPhone, save gateway URL + bearer token to Keychain, list sessions. DoD: real sessions from your Hermes render in a native list.

**Files**
- `ios/.../App/Persistence/KeychainStore.swift` — wrapper over KeychainAccess; keys: `gatewayURL`, `bearerToken`, `profile`, `deviceToken`. Survives reinstall (store in keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- `ios/.../App/Core/APIConfig.swift` — reads Keychain; exposes `gatewayURL: URL?` and `bearerToken: String?`. `AppSwift` decides root view: `FirstRunView` if nil, else `SessionListView`.
- `ios/.../App/Core/HermesClient.swift` (actor) —
  - `init(config: APIConfig)` builds a `URLSession` with a custom `Authorization: Bearer` header via `URLRequest` modifier (not a global default — keep it per-request so wrong-token swaps are clean).
  - `func sessions(includeArchived: Bool) async throws -> [Session]` → `GET /api/sessions`.
  - `func sessionDetail(id:) async throws -> SessionDetailResponse`.
  - `func ping() async throws -> Void` → `GET /health` (used by FirstRunView to validate the URL).
- `ios/.../App/Networking/HermesAPI.swift` — `enum HermesAPI` with the v1 endpoints from §3.2 as `func url(base: URL) -> URL` builders + `Request` value types. Centralizes URL construction.
- `ios/.../App/Features/FirstRun/FirstRunView.swift` + `FirstRunViewModel` — three fields (Gateway URL, Bearer Token, optional Profile), a "Test connection" button (calls `ping()`), Save → Keychain, then flip `AppState.rootView`.
- `ios/.../App/Features/Sessions/SessionListView.swift` + `SessionListViewModel` — list of `Session` (title, snippet of last message, timestamp via `.relative` FormatStyle, pin badge). Pull-to-refresh. "+ New session" button → `POST /api/session/new`. Swipe actions: rename / pin / archive / delete.
- `ios/.../App/Core/AppState.swift` (`@Observable`) — `authState: .unconfigured / .configured`, `scenePhase`, an `NWPathMonitor` wrapper exposing `isOnline`.

**Acceptance**
- Install on a physical iPhone via Xcode (follow BUILD_TO_IPHONE flow — signing, devicectl).
- Enter bridge HTTPS URL + bearer token on first launch; "Test connection" shows ✓.
- Kill & relaunch the app: still logged in (Keychain survived).
- Session list shows real sessions; pull-to-refresh updates timestamps.
- Wrong token → FirstRunView re-shown with an error.

---

### Phase 3 — Streaming chat, native shell, resilience (2–3 days)
**Goal:** send a message, watch tokens stream, survive wifi↔cellular switch and a short background excursion. DoD of the brief's §9.

**Files**
- `ios/.../App/Networking/SSEEventHandler.swift` — implements `EventSourceDelegate` (LDSwiftEventSource). On each event: parse `event:` + `data:` into `SSEEvent` (§3.4); deliver to a `Continuation`/async stream the view model consumes on `@MainActor`. Track `lastEventID` from the `id:` line; expose it so the URL can be rebuilt with `after_event_id` on reconnect.
- `ios/.../App/Networking/EventSource+Config.swift` — configures `EventSource.Configuration`: `headers = ["Authorization": "Bearer \(token)"]`, `reconnectTime` = base 1 s with backoff, `maxReconnectTime` = 30 s, `method = .get`. Verify LDSwiftEventSource sends `Last-Event-ID` automatically; additionally inject `after_event_id` into the URL query to be robust behind the bridge.
- `ios/.../App/Core/HermesClient.swift` — add:
  - `func startTurn(sessionID:, message:, model:) async throws -> ChatStartResponse` → `POST /api/chat/start`.
  - `func stream(streamID:, lastEventID:) -> AsyncThrowingStream<SSEEvent, Error>` — opens the `EventSource`, yields parsed events, terminates on `done`/`stream_end`/`cancel`/`apperror`.
  - `func cancel(streamID:) async throws` → `GET /api/chat/cancel?stream_id=`.
- `ios/.../App/Features/Conversation/ConversationViewModel.swift` (`@Observable`, `@MainActor`):
  - Holds `messages: [ChatMessage]` (UI model wrapping `Message` + `streamingText: String` + `toolCallsInProgress: [ToolCall]` + `terminalState`).
  - `func send(_ text: String)` — append user message, call `startTurn`, iterate `stream`; on `token` → append to active assistant message's `streamingText` (throttled to ~15 Hz via a `Task` that coalesces deltas and calls `setNeedsBodyUpdate` on the cell); on `tool`/`tool_complete` → insert/update `ToolCallCard`s; on terminal → mark message final, persist to SwiftData.
  - On `AppState.scenePhase == .active` after backgrounding: if a turn is in flight, the `EventSource` auto-reconnects (LDSwiftEventSource) with `after_event_id`; the journal replays missed events. No explicit replay call needed.
  - On `NWPathMonitor` change (wifi↔cellular): force-reconnect the `EventSource` with `after_event_id`.
- `ios/.../App/Features/Conversation/MessageListView.swift` — adapter around exyte/Chat's `ChatView` with a custom `messageBuilder` that returns our `MessageCell`. Map `ChatMessage` ↔ exyte's `Message` via a thin adapter (we keep our own model as the source of truth).
- `ios/.../App/Features/Conversation/MessageCell.swift` — SwiftUI cell that lays out: timestamp, role, then a vertical stack of **parts**: native `ToolCallCard` for each tool call, and a `MarkdownWebView` for the assistant text body. Re-renders the WebView only when `streamingText` changes past a debounce OR on terminal.
- `ios/.../App/Features/Conversation/ComposerView.swift` — `TextField` with 16 pt font (prevents iOS zoom-on-focus), Send + Stop buttons (Stop calls `cancel`), keyboard-tracking via `.scrollDismissKeyboard(.interactively)` + `SafeAreaInset` reading keyboard height.
- `ios/.../App/Persistence/HermesStore.swift` — SwiftData container; persist finalized `Message`s and a `StreamCursor` entity `(stream_id, session_id, last_event_id, terminal_state)` so resume survives an app kill.
- `ios/.../App/Haptics/HapticManager.swift` — light impact on send, success on terminal `done`, warning on `apperror`/`approval`.

**Acceptance (brief §9 verbatim checks)**
- Send a message → tokens stream visibly.
- Toggle wifi↔cellular mid-stream with app in foreground → stream resumes from `Last-Event-ID` without losing the turn (verify by diffing token count against a control run in the browser webui).
- Background the app for 10 s during a short turn → return → state is consistent (journal replay filled the gap, message ended in `done`).
- Stop button cancels the turn (terminal `cancel` event received, partial assistant text persisted).

---

### Phase 4 — Hybrid content rendering (2 days)
**Goal:** markdown, fenced code blocks (Prism-highlighted), and Mermaid diagrams render correctly in the WebView. DoD: send prompts that return each, all render.

**Files**
- `ios/.../App/Rendering/Resources/renderer.html` — minimal shell:
  ```html
  <!doctype html><html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <link rel="stylesheet" href="github-markdown.css">
    <link rel="stylesheet" href="prism-*.css">
    <link rel="stylesheet" href="hermes-mobile.css">
  </head><body><div id="root"></div>
    <script src="marked.min.js"></script>
    <script src="prism-core.min.js"></script>
    <script src="prism-*.min.js"></script>   <!-- python, javascript, bash, json, sql, swift, ... -->
    <script src="mermaid.min.js"></script>
    <script>
      mermaid.initialize({ startOnLoad: false, theme: 'dark', securityLevel: 'loose' });
      const root = document.getElementById('root');
      window.render = function(md, theme) {
        root.innerHTML = marked.parse(md || '');
        // highlight code
        root.querySelectorAll('pre code').forEach(b => Prism.highlightElement(b));
        // mermaid
        const blocks = root.querySelectorAll('pre code.language-mermaid');
        blocks.forEach((b, i) => {
          const id = 'mmd-' + i; const div = document.createElement('div'); div.id = id; b.parentElement.replaceWith(div);
          mermaid.render(id, b.textContent).then(({svg}) => { div.innerHTML = svg; });
        });
        // report measured height back to Swift
        window.webkit?.messageHandlers?.heightChange?.postMessage(document.body.scrollHeight);
      };
    </script>
  </body></html>
  ```
- `ios/.../App/Rendering/Resources/hermes-mobile.css` — **copy/adapt from hermes-webui `static/`** (do NOT rewrite). Required rules:
  - `:root { --keyboard-inset: 0px; }` and JS that sets it from `visualViewport.offsetTop`/`height` (so the composer rides the keyboard — owned natively here, but the CSS must not fight it).
  - `body { margin: 0; padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left); }` (edge-to-edge renderer owns the insets).
  - `input, textarea, button { font-size: 16px; }` (kills iOS zoom-on-focus).
  - All interactive elements `min-height: 44px; min-width: 44px;`.
  - Inline sibling-asset `url()` refs resolved to bundled `Bundle.main.url(forResource:)` paths (inject a `<base>` or rewrite at load) so fonts/images don't render as tofu.
- `ios/.../App/Rendering/MarkdownWebView.swift` — `UIViewRepresentable` wrapping `WKWebView`:
  - `configuration.userContentController` adds a script handler `heightChange` → resizes the SwiftUI cell (`@State var intrinsicHeight`).
  - Loads `renderer.html` from bundle once; subsequent updates via `evaluateJavaScript("render(\(jsonEncodedMarkdown), '\(theme)')")`.
  - `configuration.defaultWebpagePreferences.preferredContentMode = .mobile`.
  - Disable scrolling inside the WebView (`scrollView.isScrollEnabled = false`) — the outer native scroll owns layout; the cell sizes to content height.
- `ios/.../App/Rendering/WebViewConfig.swift` —
  - **Hide the WKWebView keyboard accessory bar (prev/next/done)** at the native layer: swizzle/remove `inputAccessoryView` on a `WKWebView` subclass returning `nil`. This is the documented fix; keep it isolated in this file.
  - KVO `visualViewport` → post `--keyboard-inset` into the page (only relevant if the composer itself were inside the WebView; we keep it native, so this is for any inline `<input>` the markdown might surface, e.g., approval forms — v1 keeps approval forms native).
- `ios/.../App/Rendering/WebViewPool.swift` (optional) — pool of 3 pre-warmed WebViews reused across cells (WKWebView init is ~50 ms; pooling smooths scrolling). Skip if exyte/Chat recycling makes it unnecessary.
- Copy the JS/CSS assets from hermes-webui `static/` into `Resources/` (vendored, pinned versions; record the commit SHA in a `Resources/UPSTREAM.txt`).

**Acceptance**
- Ask Hermes: "Write a markdown doc with headings, a table, a fenced Python code block, and a Mermaid flowchart." All four render correctly; code is Prism-highlighted; Mermaid is an SVG.
- Code-block copy button works (add a small native "Copy" affordance in `MessageCell` that calls `UIPasteboard.general.string = code`).
- No tofu fonts; no iOS zoom on focusing any inline field.
- Tap a `workspace://` link in rendered markdown → native handler calls `GET /api/file` (v2; for v1 just route to a placeholder sheet).
- Rotate device → content reflows and height updates.

---

### Phase 5 — Sessions CRUD polish + Settings (1–2 days)
**Goal:** full v1 session management + a usable Settings screen.

**Files**
- `ios/.../App/Features/Sessions/SessionListView.swift` — finish swipe actions: rename (`POST /api/session/rename`), pin (`/api/session/pin`), archive (`/api/session/archive`), delete (`/api/session/delete`). Group by Today / Yesterday / Earlier (collapsible) mirroring the webui sidebar.
- `ios/.../App/Features/Settings/SettingsView.swift` —
  - Display gateway URL + masked token + active profile.
  - "Edit connection" → reopen `FirstRunView` prefilled.
  - "Sign out" → wipe Keychain → `FirstRunView`.
  - Toggles: theme (system/dark/light) — persisted; APNs permission (v1.1).
- `ios/.../App/Models/ChatMessage.swift` — finalize the UI model adapter; ensure SwiftData round-trips finalized messages so offline scroll works.

**Acceptance**
- Create / rename / pin / archive / delete all work and the list updates optimistically + reconciles with server response.
- Offline launch shows the last-known session list from SwiftData (read-through cache).

---

### Phase 6 — Backgrounding story (already 90% solved; wire the remaining 10%)
**Goal:** foreground-return always consistent; (v1.1) APNs notifies on backgrounded completion.

**What's already free (verify, don't build):** the webui run worker is a daemon thread that survives client disconnects; the run journal replays via `after_event_id`; LDSwiftEventSource auto-reconnects on foreground. So returning to the app always lands in a consistent state.

**Files (v1 — wiring only)**
- `ios/.../App/Core/HermesClient.swift` — on `scenePhase == .background`: stop trying to keep the SSE open (let the OS suspend it); persist `StreamCursor(stream_id, last_event_id)` to SwiftData. On `.active`: if a non-terminal `StreamCursor` exists, reconnect `GET /api/chat/stream?stream_id=&after_event_id=` — the journal replays and the turn finalizes.
- Register a `BGAppRefreshTask` (`com.hermes.mobile.refresh`) **only** to opportunistically refresh the session list (never to hold a stream open). Document in `App/Core/BackgroundTasks.swift`.

**Files (v1.1 — APNs; build after v1 ships)**
- `backend/hermes_bridge/device_tokens.py` — `POST /mobile/device {device_token, session_id?}` → store against the active run.
- `backend/hermes_bridge/apns.py` — `apns2` client; `send(device_token, payload)` with a thread ID per session.
- `backend/hermes_bridge/sse_proxy.py` — when forwarding a terminal event (`done`/`apperror`/`cancel`) and a `device_token` is registered for that `stream_id`, fire APNs (best-effort, non-blocking) **after** the event is forwarded to any live client.
- iOS: request authorization on first send, register remote push, POST token to `/mobile/device` at app launch.

**Acceptance (v1)**
- Start a 60 s turn, background the app at 5 s, return at 70 s → the assistant message is complete and matches the browser run. No duplicate tokens, no lost tokens.
- Kill the app from the app switcher mid-turn → relaunch → conversation rehydrates from SwiftData + journal replay, terminates correctly.

**Acceptance (v1.1)**
- Background a long turn → phone receives a push titled with the session name when it completes.

---

## 6. Hard rules for the implementing agent (do not violate)

1. **Do not rewrite markdown/code/diagram rendering in Swift.** It lives in the WebView (`renderer.html`). This is the single biggest trap.
2. **Do not roll your own SSE parser.** Use LDSwiftEventSource; only parse `event:`/`data:`/`id:` into `SSEEvent`.
3. **Do not put streaming state in SwiftUI structs without `@MainActor`.** All `messages` mutations happen on the main actor.
4. **Do not skip the `after_event_id` query param.** It is what makes resume robust behind the bridge.
5. **Do not require Tailscale on the phone.** Cloudflare Tunnel gives the stable HTTPS hostname.
6. **Do copy `hermes-mobile.css` from `hermes-webui/static/`.** It is the result of many commits of mobile polish; record the upstream commit SHA in `Resources/UPSTREAM.txt`.
7. **Do pin SPM versions.** Note any 0.x library explicitly.
8. **Do keep the webui unchanged.** All phone-specific logic lives in the bridge.
9. **Do decode every webui response defensively** (`optional` everywhere — fields drift between versions).
10. **Do not implement v2/v3 features** (workspace browser, attachments, profiles UI, slash commands, Face ID, Live Activity, widgets) in v1.

---

## 7. Verification — Definition of Done (overall, brief §9)

- [ ] App installs on a physical iPhone via Xcode/devicectl.
- [ ] First-run saves token to Keychain; survives reinstall of app data.
- [ ] List sessions; send a message; watch tokens stream.
- [ ] Render markdown + a fenced code block + a Mermaid diagram correctly in the WebView.
- [ ] Foreground: toggle wifi↔cellular mid-stream → stream resumes without losing the turn.
- [ ] Background during a short turn → return → state is consistent (journal replay).
- [ ] No WebView keyboard accessory bar; composer tracks the keyboard; tap targets ≥ 44 pt.
- [ ] Wrong bearer token → clear 401 + return to FirstRunView.
- [ ] `os.Logger` spans (`com.hermes.mobile.network`, `.sse`, `.render`) emit structured logs visible in Console.app.

---

## 8. AGENTS.md (commands the implementing agent must run)

Create this file at the repo root so the implementing agent knows the build/test commands:

````markdown
# Build commands

## iOS (run from `ios/`)
- Build:              `xcodebuild -scheme Hermes -destination 'generic/platform=iOS' build`
- Run in simulator:   `xcodebuild -scheme Hermes -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Lint:               `xcodebuild -scheme Hermes clean build` (treat warnings as errors: `HERMES_TREAT_WARNINGS_AS_ERRORS=YES`)

## Backend (run from `backend/`)
- Install:            `uv sync`
- Run (dev):          `uv run uvicorn hermes_bridge.main:app --reload --port 8080`
- Tests:              `uv run pytest`
- Lint/format:        `uv run ruff check . && uv run ruff format --check .`

## Integration smoke (requires webui running on :8787)
- `curl -H "Authorization: Bearer $HERMES_MOBILE_TOKEN" http://127.0.0.1:8080/health`
- `curl -H "Authorization: Bearer $HERMES_MOBILE_TOKEN" http://127.0.0.1:8080/api/sessions`
````

---

## 9. Reference material the implementing agent should read (in order)

1. **This document** (§3 contract is authoritative — do not re-fetch the webui unless a field is missing).
2. hermes-webui `ARCHITECTURE.md` + `docs/remote-access.md` — deployment model, SSE buffering notes.
3. exyte/Chat README — its `Message` model + `messageBuilder` signature (this dictates the adapter in `MessageListView.swift`).
4. launchdarkly/swift-eventsource README — confirm `Last-Event-ID` behavior and the `Configuration` knobs.
5. kishikawakatsumi/KeychainAccess README — Keychain API surface.
6. hermes-webui `static/*.css` + `static/*.js` — source for `hermes-mobile.css` and the renderer asset versions.
7. (v1.1 only) Apple APNs docs + `apns2` README.

---

## 10. Risk register (flag these early if they bite)

| Risk | Mitigation |
|---|---|
| `X-Hermes-CSRF-Token` derivation is undocumented/opaque | Use the authenticated endpoint the webui's own JS uses to read it; if none, perform login + read the `Set-Cookie` and compute the HMAC per the contract note. If both fail, fall back to disabling password auth on the webui and relying on bearer-only at the bridge (loopback-only webui binding). |
| LDSwiftEventSource doesn't send `Last-Event-ID` reliably | Always also set `after_event_id` in the URL query (already specified). |
| exyte/Chat model mismatch | Keep `ChatMessage` as source of truth; write a thin `ExyteMessageAdapter`. |
| Mermaid in a pooled/visible WebView flashes on re-render | Render Mermaid lazily (only when cell is on-screen and message is terminal); debounce streaming re-renders to terminal-only for diagrams. |
| Cloudflare Tunnel URL rotates on free tier | Use `cloudflared tunnel` with a named tunnel + your own hostname for a stable URL; or run on a small VPS with a real domain + Caddy/Let's Encrypt. |
| Webui 20 s SSE write deadline drops long-idle mobile sockets | Bridge sets its own longer write deadline and re-establishes the upstream; the phone reconnects with `after_event_id` regardless. |

---

**End of plan.** Phase 0 → Phase 5 is v1 (≈7–10 days of focused work). Phase 6 v1.1 (APNs) ≈1 extra day. Everything else is v2/v3.
