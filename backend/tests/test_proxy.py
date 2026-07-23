"""Exercise the JARVIS bridge against a stub upstream Hermes WebUI."""

from __future__ import annotations

import json

import pytest
import respx
from fastapi.testclient import TestClient

from jarvis_bridge.config import Settings
from jarvis_bridge.main import app


@pytest.fixture()
def settings(monkeypatch: pytest.MonkeyPatch, tmp_path) -> Settings:
    monkeypatch.setenv("WEBUI_BASE_URL", "http://webui.test")
    monkeypatch.setenv("WEBUI_PASSWORD", "secret")
    monkeypatch.setenv("MOBILE_TOKEN", "phone-token-hex")
    monkeypatch.setenv("RUNS_DB_PATH", str(tmp_path / "runs.sqlite"))
    # Re-import settings each test (pydantic-settings caches).
    from jarvis_bridge import config as cfg

    cfg._settings = None  # type: ignore[attr-defined]
    return cfg.get_settings()


@pytest.fixture()
def client(settings: Settings):
    # Reset the module-level singletons so each test gets a fresh client.
    from sse_starlette.sse import AppStatus

    from jarvis_bridge import apns as apns_mod
    from jarvis_bridge import approvals as approvals_mod
    from jarvis_bridge import runs as runs_mod
    from jarvis_bridge import webui_client as wc

    wc._client = None
    runs_mod._registry = None
    apns_mod._apns = None
    approvals_mod._registry = None
    # sse-starlette keeps this event at module scope; reset it between the
    # per-test TestClient event loops so independent SSE tests do not share an
    # asyncio primitive bound to a prior loop.
    AppStatus.should_exit_event = None
    AppStatus.should_exit = False
    with TestClient(app) as c:
        yield c


@respx.mock
def test_login_then_sessions_pass_through(client, settings):
    # 1) webui login
    respx.post("http://webui.test/api/auth/login").mock(
        return_value=respx.MockResponse(status_code=200, json={"ok": True})
    )
    # httpx is initialized lazily, so this triggers login on first call.
    respx.get("http://webui.test/api/sessions").mock(
        return_value=respx.MockResponse(
            status_code=200,
            json={
                "sessions": [
                    {
                        "session_id": "abc123def456",
                        "title": "hello",
                        "workspace": None,
                        "model": None,
                        "model_provider": None,
                        "message_count": 0,
                        "created_at": 0.0,
                        "updated_at": 0.0,
                        "last_message_at": None,
                        "pinned": False,
                        "archived": False,
                        "project_id": None,
                        "profile": None,
                        "input_tokens": 0,
                        "output_tokens": 0,
                        "estimated_cost": None,
                        "is_streaming": False,
                        "has_pending_user_message": False,
                        "active_stream_id": None,
                    }
                ],
                "active_profile": None,
            },
        )
    )

    r = client.get("/api/sessions", headers={"Authorization": "Bearer phone-token-hex"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["sessions"][0]["title"] == "hello"


@respx.mock
def test_missing_bearer_is_401(client, settings):
    r = client.get("/api/sessions")
    assert r.status_code == 401
    assert r.headers.get("www-authenticate", "").lower().startswith("bearer")


@respx.mock
def test_wrong_bearer_is_401(client, settings):
    r = client.get("/api/sessions", headers={"Authorization": "Bearer nope"})
    assert r.status_code == 401


@respx.mock
def test_health_proxy(client, settings):
    respx.get("http://webui.test/health").mock(
        return_value=respx.MockResponse(
            status_code=200,
            json={"status": "ok", "active_streams": 0, "active_runs": 0, "uptime_seconds": 1.0},
        )
    )
    r = client.get("/health", headers={"Authorization": "Bearer phone-token-hex"})
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


@respx.mock
def test_webui_401_reauthenticates_once(client, settings):
    login = respx.post("http://webui.test/api/auth/login").mock(
        side_effect=[
            respx.MockResponse(
                status_code=200,
                json={"ok": True},
                cookies={"hermes_session": "old-token.old-signature"},
            ),
            respx.MockResponse(
                status_code=200,
                json={"ok": True},
                cookies={"hermes_session": "new-token.new-signature"},
            ),
        ]
    )
    sessions = respx.get("http://webui.test/api/sessions").mock(
        side_effect=[
            respx.MockResponse(status_code=401, json={"error": "expired"}),
            respx.MockResponse(status_code=200, json={"sessions": []}),
        ]
    )

    r = client.get("/api/sessions", headers={"Authorization": "Bearer phone-token-hex"})

    assert r.status_code == 200
    assert len(login.calls) == 2
    assert len(sessions.calls) == 2
    assert sessions.calls[0].request.headers.get("x-hermes-csrf-token") == "old-token"
    assert sessions.calls[1].request.headers.get("x-hermes-csrf-token") == "new-token"


@respx.mock
def test_chat_stream_forwards_resume_and_records_run_state(client, settings):
    respx.post("http://webui.test/api/auth/login").mock(
        return_value=respx.MockResponse(
            status_code=200,
            json={"ok": True},
            cookies={"hermes_session": "stream-token.stream-signature"},
        )
    )
    upstream = respx.get("http://webui.test/api/chat/stream").mock(
        return_value=respx.MockResponse(
            status_code=200,
            content=(
                b'id: stream-1:5\nevent: delta\ndata: {"text":"Hello"}\n\n'
                b'id: stream-1:6\nevent: done\ndata: {"status":"done"}\n\n'
            ),
            content_type="text/event-stream",
        )
    )

    from jarvis_bridge import runs as runs_mod

    assert runs_mod._registry is not None
    runs_mod._registry.record_start("stream-1", "session-1")
    r = client.get(
        "/api/chat/stream",
        params={"stream_id": "stream-1", "after_event_id": "stream-1:4"},
        headers={"Authorization": "Bearer phone-token-hex"},
    )

    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/event-stream")
    assert "id: stream-1:5" in r.text
    assert 'data: {"text":"Hello"}' in r.text
    assert "event: done" in r.text
    assert upstream.calls[0].request.url.params["after_event_id"] == "stream-1:4"
    summary = runs_mod._registry.terminal_summary("stream-1")
    assert summary is not None
    assert summary["last_event_id"] == "stream-1:6"
    assert summary["terminal_state"] == "done"


def test_bridge_liveness(client):
    r = client.get("/__bridge/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_bridge_version_is_jarvis(client):
    r = client.get("/__bridge/version")
    assert r.status_code == 200
    assert r.json() == {"name": "jarvis-mobile-bridge", "version": "0.1.0"}


@respx.mock
def test_session_creation_defaults_to_jarvis_profile(client, settings):
    respx.post("http://webui.test/api/auth/login").mock(
        return_value=respx.MockResponse(status_code=200, json={"ok": True})
    )
    upstream = respx.post("http://webui.test/api/session/new").mock(
        return_value=respx.MockResponse(status_code=200, json={"session": {"session_id": "s1"}})
    )
    personality = respx.post("http://webui.test/api/personality/set").mock(
        return_value=respx.MockResponse(status_code=200, json={"ok": True, "personality": "jarvis"})
    )

    r = client.post(
        "/api/session/new",
        headers={"Authorization": "Bearer phone-token-hex"},
        json={"workspace": "default"},
    )

    assert r.status_code == 200
    payload = json.loads(upstream.calls[0].request.content)
    assert payload["profile"] == "jarvis"
    assert payload["personality"] == "jarvis"
    assert json.loads(personality.calls[0].request.content) == {
        "session_id": "s1",
        "name": "jarvis",
    }


@respx.mock
def test_explicit_profile_is_preserved(client, settings):
    respx.post("http://webui.test/api/auth/login").mock(
        return_value=respx.MockResponse(status_code=200, json={"ok": True})
    )
    upstream = respx.post("http://webui.test/api/session/new").mock(
        return_value=respx.MockResponse(status_code=200, json={"session": {"session_id": "s1"}})
    )
    personality = respx.post("http://webui.test/api/personality/set").mock(
        return_value=respx.MockResponse(status_code=200, json={"ok": True, "personality": "jarvis"})
    )

    r = client.post(
        "/api/session/new",
        headers={"Authorization": "Bearer phone-token-hex"},
        json={"profile": "engineering"},
    )

    assert r.status_code == 200
    payload = json.loads(upstream.calls[0].request.content)
    assert payload["profile"] == "engineering"
    assert payload["personality"] == "jarvis"
    assert json.loads(personality.calls[0].request.content)["name"] == "jarvis"


@respx.mock
def test_explicit_personality_is_preserved(client, settings):
    respx.post("http://webui.test/api/auth/login").mock(
        return_value=respx.MockResponse(status_code=200, json={"ok": True})
    )
    upstream = respx.post("http://webui.test/api/session/new").mock(
        return_value=respx.MockResponse(status_code=200, json={"session": {"session_id": "s1"}})
    )
    personality = respx.post("http://webui.test/api/personality/set").mock(
        return_value=respx.MockResponse(
            status_code=200, json={"ok": True, "personality": "concise"}
        )
    )

    r = client.post(
        "/api/session/new",
        headers={"Authorization": "Bearer phone-token-hex"},
        json={"personality": "concise"},
    )

    assert r.status_code == 200
    assert json.loads(upstream.calls[0].request.content)["personality"] == "concise"
    assert json.loads(personality.calls[0].request.content)["name"] == "concise"


@respx.mock
def test_chat_start_defaults_to_jarvis_profile(client, settings):
    respx.post("http://webui.test/api/auth/login").mock(
        return_value=respx.MockResponse(status_code=200, json={"ok": True})
    )
    upstream = respx.post("http://webui.test/api/chat/start").mock(
        return_value=respx.MockResponse(
            status_code=200,
            json={"stream_id": "stream-1", "session_id": "session-1"},
        )
    )
    personality = respx.post("http://webui.test/api/personality/set").mock(
        return_value=respx.MockResponse(status_code=200, json={"ok": True, "personality": "jarvis"})
    )

    r = client.post(
        "/api/chat/start",
        headers={"Authorization": "Bearer phone-token-hex"},
        json={"session_id": "session-1", "message": "Check my schedule"},
    )

    assert r.status_code == 200
    payload = json.loads(upstream.calls[0].request.content)
    assert payload["profile"] == "jarvis"
    assert payload["personality"] == "jarvis"
    assert payload["message"] == "Check my schedule"
    assert json.loads(personality.calls[0].request.content) == {
        "session_id": "session-1",
        "name": "jarvis",
    }


@respx.mock
def test_approval_event_is_registered_and_one_action_decision_forwards(client, settings):
    respx.post("http://webui.test/api/auth/login").mock(
        return_value=respx.MockResponse(
            status_code=200,
            json={"ok": True},
            cookies={"hermes_session": "approval-token.approval-signature"},
        )
    )
    respx.get("http://webui.test/api/chat/stream").mock(
        return_value=respx.MockResponse(
            status_code=200,
            content=(
                b"id: stream-approval:1\nevent: approval\n"
                b'data: {"approval_id":"a1","tool_name":"gmail_send",'
                b'"command":"send email","description":"Send the draft",'
                b'"choices":["once","deny"]}\n\n'
                b'id: stream-approval:2\nevent: done\ndata: {"status":"done"}\n\n'
            ),
            content_type="text/event-stream",
        )
    )
    upstream_decision = respx.post("http://webui.test/api/approval/respond").mock(
        return_value=respx.MockResponse(status_code=200, json={"ok": True})
    )

    from jarvis_bridge import runs as runs_mod

    assert runs_mod._registry is not None
    runs_mod._registry.record_start("stream-approval", "session-approval")
    stream = client.get(
        "/api/chat/stream",
        params={"stream_id": "stream-approval"},
        headers={"Authorization": "Bearer phone-token-hex"},
    )
    assert stream.status_code == 200

    approvals = client.get(
        "/mobile/approvals",
        headers={"Authorization": "Bearer phone-token-hex"},
    )
    assert approvals.status_code == 200
    record = approvals.json()["approvals"][0]
    assert record["approval_id"] == "a1"
    assert record["action_class"] == "send_email"
    assert record["status"] == "pending"

    decision = client.post(
        "/mobile/approvals/a1/decision",
        headers={"Authorization": "Bearer phone-token-hex"},
        json={"decision": "approve"},
    )
    assert decision.status_code == 200
    assert decision.json()["status"] == "consumed"
    assert json.loads(upstream_decision.calls[0].request.content) == {
        "approval_id": "a1",
        "choice": "once",
        "run_id": "stream-approval",
    }

    replay = client.post(
        "/mobile/approvals/a1/decision",
        headers={"Authorization": "Bearer phone-token-hex"},
        json={"decision": "approve"},
    )
    assert replay.status_code == 409
