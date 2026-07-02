"""Test that the generic JSON pass-through attaches the webui cookie and CSRF."""

from __future__ import annotations

import pytest
import respx
from fastapi.testclient import TestClient

from hermes_bridge.config import Settings
from hermes_bridge.main import app
from hermes_bridge.webui_client import init_webui_client


@pytest.fixture()
def settings(monkeypatch: pytest.MonkeyPatch) -> Settings:
    monkeypatch.setenv("WEBUI_BASE_URL", "http://webui.test")
    monkeypatch.setenv("WEBUI_PASSWORD", "secret")
    monkeypatch.setenv("MOBILE_TOKEN", "phone-token-hex")
    # Re-import settings each test (pydantic-settings caches).
    from hermes_bridge import config as cfg
    cfg._settings = None  # type: ignore[attr-defined]
    return cfg.get_settings()


@pytest.fixture()
def client(settings: Settings):
    # Reset the module-level singletons so each test gets a fresh client.
    from hermes_bridge import webui_client as wc
    from hermes_bridge import runs as runs_mod
    from hermes_bridge import apns as apns_mod
    wc._client = None
    runs_mod._registry = None
    apns_mod._apns = None
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

    r = client.get(
        "/api/sessions", headers={"Authorization": "Bearer phone-token-hex"}
    )
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


def test_bridge_liveness(client):
    r = client.get("/__bridge/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
