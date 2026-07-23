"""Generic JSON pass-through proxy from the bridge to hermes-webui.

The bridge is a 1:1 reverse proxy for `/api/*` (and `/health`). The phone
talks to the bridge over bearer; the bridge talks to the webui over
cookie+CSRF, transparently. SSE lives in `sse_proxy.py`.

Concurrency hardening (Layer 2 of the desktop-vs-mobile plan):
    webui's `_clear_stale_stream_state` (routes.py:2866) fires on every
    GET /api/session when the session has `active_stream_id` set but
    neither STREAMS nor ACTIVE_RUNS contains it. The Hermes Desktop
    and webui are SEPARATE processes with isolated stream registries
    but shared on-disk state — so the desktop's active stream is
    invisible to webui, and any iOS app read of a session the desktop
    is working on clears the desktop's `active_stream_id` after 30s,
    which the desktop renderer then sees as "stream ended" → "result
    fades." We mitigate on two axes:

      1. Strip `active_stream_id` from JSON responses so the iOS app
         never accidentally acts on a stream id it doesn't own.
      2. Refuse mutating POSTs (chat/start, session/delete, session/
         clear, session/update, session/branch, session/retry) on
         sessions that webui reports as actively streaming, since we
         can't distinguish desktop vs bridge streams and acting on
         the wrong one would corrupt the desktop's turn.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from fastapi import APIRouter, Depends, Request, Response

from .auth import require_bearer
from .config import get_settings
from .webui_client import WebUIClient, get_webui_client

logger = logging.getLogger("jarvis_bridge.proxy")

router = APIRouter()


async def _set_upstream_personality(
    webui: WebUIClient,
    session_id: str,
    personality: str,
) -> None:
    """Persist the selected upstream personality for a newly created session.

    Hermes Agent exposes personality selection as a session mutation rather
    than a field consumed by ``/api/session/new``. Keep that upstream detail
    inside the bridge so the iOS client only needs the JARVIS API contract.
    """
    try:
        response = await webui.post(
            "/api/personality/set",
            json_body={"session_id": session_id, "name": personality},
        )
    except Exception:
        logger.exception("failed to set personality for session %s", session_id)
        return
    if response.status_code >= 400:
        logger.warning(
            "upstream personality selection failed for session %s: HTTP %s %s",
            session_id,
            response.status_code,
            response.text[:200],
        )


# Endpoints that mutate session state. If a session is actively streaming
# (per webui's response), we reject the iOS-side POST so we don't step on
# the desktop's turn. Reads (GET) and the chat/stream SSE itself are
# unaffected.
_MUTATING_SESSION_PATHS = frozenset(
    {
        "/api/chat/start",
        "/api/session/delete",
        "/api/session/clear",
        "/api/session/update",
        "/api/session/branch",
        "/api/session/retry",
        "/api/session/rename",
        "/api/session/pin",
        "/api/session/archive",
    }
)


def _strip_stream_fields(body: bytes) -> bytes:
    """Remove `active_stream_id`, `pending_*`, and other stream-internals
    from a JSON response before forwarding it to the iOS app. The phone
    should never act on stream identifiers it doesn't own."""
    if not body:
        return body
    try:
        payload = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return body

    def _scrub(obj: Any) -> Any:
        if isinstance(obj, dict):
            for k in (
                "active_stream_id",
                "pending_started_at",
                "pending_user_message",
                "pending_workspace",
            ):
                obj.pop(k, None)
            for v in obj.values():
                _scrub(v)
        elif isinstance(obj, list):
            for item in obj:
                _scrub(item)
        return obj

    _scrub(payload)
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def _session_active_stream_id_from_json(payload: Any) -> str | None:
    """Pull the session-active stream id from a parsed /api/sessions or
    /api/session response body. Returns None if absent."""
    if isinstance(payload, dict):
        # /api/session shape: {"session": {...}, "messages": [...]}
        sess = payload.get("session")
        if isinstance(sess, dict):
            v = sess.get("active_stream_id")
            if isinstance(v, str) and v:
                return v
        # /api/sessions shape: {"sessions": [...]}
        for s in payload.get("sessions", []) or []:
            if isinstance(s, dict):
                v = s.get("active_stream_id")
                if isinstance(v, str) and v:
                    return v
    return None


async def _passthrough(
    request: Request,
    webui: WebUIClient,
) -> Response:
    """Forward the inbound request to the webui, copy back the response."""
    method = request.method
    # `rest` is the substring after `/api/` — re-prepend `/api/` to forward
    # the full upstream path verbatim.
    rest = request.path_params.get("rest", "")
    path = "/api/" + rest if rest else "/api/"
    params = dict(request.query_params)

    body: Any = None
    content_type = request.headers.get("content-type", "")
    if method in ("POST", "PUT", "PATCH", "DELETE"):
        if "application/json" in content_type:
            try:
                body = await request.json()
            except Exception:
                body = None
        else:
            # For multipart or binary uploads, hand raw bytes through.
            body = await request.body()

    # Select the upstream-supported JARVIS profile/personality without
    # rewriting the user's message. Explicit values remain untouched.
    if path == "/api/session/new" and isinstance(body, dict):
        body.setdefault("profile", get_settings().jarvis_profile)
        body.setdefault("personality", get_settings().jarvis_personality)

    # Concurrency guard: if the iOS app tries to mutate a session that
    # webui reports as actively streaming, reject the call. The active
    # stream could be the desktop's and we can't prove otherwise from
    # inside the bridge. See module docstring for the full rationale.
    if method in ("POST", "PUT", "PATCH", "DELETE") and path in _MUTATING_SESSION_PATHS:
        session_id = _extract_session_id(path, body, params)
        if session_id:
            try:
                list_resp = await webui.request("GET", "/api/sessions")
            except Exception:
                list_resp = None
            if list_resp is not None and list_resp.status_code == 200:
                try:
                    payload = json.loads(list_resp.content)
                except (ValueError, UnicodeDecodeError):
                    payload = None
                active = _session_active_stream_id_from_json(payload) if payload else None
                if active:
                    logger.warning(
                        "rejecting mutating %s %s — session %s has active_stream_id=%s",
                        method,
                        path,
                        session_id,
                        active,
                    )
                    return Response(
                        content=(
                            b'{"error":"session_in_use",'
                            b'"detail":"this session is actively streaming on another client; '
                            b'wait for the current turn to finish before sending another."}'
                        ),
                        media_type="application/json",
                        status_code=409,
                    )

    try:
        resp = await webui.request(
            method, path, params=params, json_body=body if body is not None else None
        )
    except Exception as exc:
        logger.exception("passthrough failed for %s %s", method, path)
        return Response(
            content=f'{{"error":"upstream_unreachable","detail":"{exc}"}}',
            media_type="application/json",
            status_code=502,
        )

    # Select a media type that the iOS app can decode.
    out_ct = resp.headers.get("content-type", "application/json")

    # Drop cookie/hop-by-hop headers we don't want to expose to the phone.
    # `content-length` is excluded because httpx auto-decompresses the body,
    # so the decoded length doesn't match the upstream Content-Length.
    excluded = {
        "content-encoding",
        "transfer-encoding",
        "set-cookie",
        "connection",
        "content-length",
    }
    headers = {k: v for k, v in resp.headers.items() if k.lower() not in excluded}

    # Strip stream-internals from JSON responses. Only do this for JSON;
    # leave SSE / binary responses untouched.
    body_bytes = resp.content
    is_json = "json" in out_ct.lower()
    if is_json and method == "GET" and resp.status_code == 200:
        body_bytes = _strip_stream_fields(body_bytes)

    # ``/api/session/new`` does not consume ``personality`` itself in the
    # upstream API. Apply it after creation, then return the original session
    # response to preserve the upstream wire contract.
    if path == "/api/session/new" and resp.status_code < 400 and isinstance(body, dict):
        try:
            created = json.loads(resp.content)
            session = created.get("session", {}) if isinstance(created, dict) else {}
            session_id = session.get("session_id") if isinstance(session, dict) else None
            personality = body.get("personality")
            if (
                isinstance(session_id, str)
                and session_id
                and isinstance(personality, str)
                and personality
            ):
                await _set_upstream_personality(webui, session_id, personality)
        except (ValueError, TypeError, AttributeError):
            logger.warning("could not inspect new session response for personality selection")

    return Response(
        content=body_bytes,
        media_type=out_ct.split(";")[0].strip(),
        status_code=resp.status_code,
        headers=headers,
    )


def _extract_session_id(path: str, body: Any, params: dict[str, str]) -> str | None:
    """Find the session_id for a mutating endpoint. Looks at query params
    first (most chat/start calls pass `session_id=X`), then at JSON body."""
    sid = params.get("session_id")
    if isinstance(sid, str) and sid:
        return sid
    if isinstance(body, dict):
        sid = body.get("session_id")
        if isinstance(sid, str) and sid:
            return sid
    return None


@router.api_route(
    "/api/{rest:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    dependencies=[Depends(require_bearer)],
)
async def api_proxy(
    rest: str,
    request: Request,
    webui: WebUIClient = Depends(get_webui_client),  # noqa: B008
) -> Response:
    """All `/api/*` JSON routes, pass-through with re-auth on 401."""
    # FastAPI has already consumed `rest` into path_params; rebuild from request.url
    return await _passthrough(request, webui)


@router.get("/health", dependencies=[Depends(require_bearer)])
async def health(webui: WebUIClient = Depends(get_webui_client)) -> dict[str, Any]:  # noqa: B008
    """Public-ish: we still require bearer (the iOS app uses this to ping).

    Returns the webui's `/health` body if reachable, else a stub.
    """
    return await webui.health()


@router.get("/")
async def root() -> dict[str, Any]:
    return {"name": "jarvis-mobile-bridge", "version": "0.1.0"}
