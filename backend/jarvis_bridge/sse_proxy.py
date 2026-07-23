"""SSE pass-through with a long write deadline and APNs-on-terminal hook.

`GET /api/chat/stream?stream_id=…` is the long-lived endpoint that streams
the agent's per-turn events. The webui's worker survives disconnects; we just
need to forward each `event:` + `data:` + `id:` frame to the phone, recording
the `id:` so the phone can resume via `after_event_id`.

When a terminal event (`done` / `cancel` / `apperror`) passes through and we
have a registered `device_token` for that run, we also fire an APNs push
(best-effort, in a background task) so the phone gets notified even when
the app is suspended.

We also publish `X-Accel-Buffering: no` and `Cache-Control: no-cache` so any
reverse proxy (nginx, cloudflared) doesn't buffer chunks.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
from collections.abc import AsyncIterator

import httpx
from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import StreamingResponse
from sse_starlette.sse import EventSourceResponse

from .apns import APNsClient, get_apns
from .auth import require_bearer
from .config import Settings, get_settings
from .runs import RunsRegistry, get_registry
from .webui_client import WebUIClient, get_webui_client

logger = logging.getLogger("jarvis_bridge.sse")

router = APIRouter()

# A terminal `event:` name means the run is done (for APNs purposes).
_TERMINAL_EVENTS = {"done", "cancel", "apperror"}

# Per-frame parser. The webui emits SSE in the shape:
#   id: stream_id:seq
#   event: name
#   data: json
#
#   <blank>
#
# We forward verbatim. We do NOT inject frames, edit data, or rewrite anything.

# Detect a terminal event inside a forwarded byte chunk to fire APNs at most once.
_TERMINAL_LINE_RE = re.compile(rb"^event:\s*(done|cancel|apperror)\s*$", re.MULTILINE)


async def _stream_from_webui(
    webui: WebUIClient,
    path: str,
    params: dict[str, str],
    settings: Settings,
    runs: RunsRegistry,
    apns: APNsClient | None,
) -> AsyncIterator[dict]:
    """Open an SSE request to the webui and yield each event as a dict."""
    try:
        resp = await webui.stream("GET", path, params=params)
    except httpx.HTTPError as exc:
        logger.warning("stream open failed: %s", exc)
        # Surface as a single error event so the phone can clean up.
        yield {
            "event": "apperror",
            "data": json.dumps({"type": "upstream_open_failed", "message": str(exc)}),
        }
        return

    if resp.status_code != 200:
        body = await resp.aread()
        yield {
            "event": "apperror",
            "data": json.dumps(
                {"type": "upstream_non_200", "message": body[:400].decode("utf-8", "replace")}
            ),
        }
        await resp.aclose()
        return

    stream_id = params.get("stream_id", "")
    fired_terminal = False

    async def gen() -> AsyncIterator[dict]:
        nonlocal fired_terminal
        try:
            async for raw in resp.aiter_lines():
                if not raw:
                    continue
                # We expect three lines per event; webui emits them in order.
                # LDSwiftEventSource on the phone expects the exact same wire
                # form — copy bytes verbatim.
                # We still need to recover the `id:` and `event:` to:
                #   1. persist `last_event_id` for resume
                #   2. trigger APNs on terminal
                #
                # To do this we buffer lines between blank-line terminators.
                # The simplest correct approach is to forward verbatim via raw
                # events below.
                pass
        finally:
            await resp.aclose()

    # Forward bytes verbatim. To keep it simple, we yield each SSE event as a
    # single `data:` of raw text — but the phone-side LDSwiftEventSource
    # expects the standard wire framing. So we read raw lines and group them
    # into one event per blank-line terminator.
    #
    # To avoid decoding pressure we just forward the byte chunks that have a
    # complete event; the FastAPI layer turns them into actual SSE data: lines.
    #
    # ssse-starlette's `EventSourceResponse` expects `dict` with `data` (and
    # optionally `event`, `id`, `retry`). We mirror that exactly.

    buffer = b""
    current_id: str | None = None
    current_event: str | None = None
    current_data_parts: list[bytes] = []

    async def flush() -> AsyncIterator[dict]:
        nonlocal current_id, current_event, current_data_parts, fired_terminal
        if not current_data_parts and not current_event:
            return
        data = b"\n".join(current_data_parts).decode("utf-8", "replace")
        evt: dict = {"data": data}
        if current_event:
            evt["event"] = current_event
        if current_id:
            evt["id"] = current_id
        # Side effects: persist last_event_id, trigger APNs on terminal
        if current_id and stream_id:
            try:
                runs.record_event_id(stream_id, current_id)
            except Exception:
                logger.exception("record_event_id failed")
        if current_event in _TERMINAL_EVENTS and not fired_terminal:
            fired_terminal = True
            try:
                if apns and apns.enabled:
                    payload: dict = {}
                    try:
                        payload = json.loads(data) if data else {}
                    except Exception:
                        payload = {}
                    title = payload.get("type") or payload.get("status") or "Turn complete"
                    body = payload.get("message") or payload.get("label") or "JARVIS turn finished"
                    dt = runs.device_token_for(stream_id)
                    if dt:
                        asyncio.create_task(apns.send(dt, stream_id, str(title), str(body)))
            except Exception:
                logger.exception("APNs trigger failed")
            try:
                runs.record_terminal(stream_id, current_event)
            except Exception:
                logger.exception("record_terminal failed")
        # Reset
        current_id = None
        current_event = None
        current_data_parts = []
        yield evt

    try:
        async for chunk in resp.aiter_bytes():
            buffer += chunk
            while b"\n\n" in buffer:
                raw_event, buffer = buffer.split(b"\n\n", 1)
                # parse one SSE frame
                current_id = None
                current_event = None
                current_data_parts = []
                for ln in raw_event.split(b"\n"):
                    if not ln:
                        continue
                    if ln.startswith(b":"):
                        continue
                    if b":" in ln:
                        field, _, value = ln.partition(b":")
                        # strip optional leading space per SSE spec
                        if value.startswith(b" "):
                            value = value[1:]
                        if field == b"id":
                            current_id = value.decode("utf-8", "replace")
                        elif field == b"event":
                            current_event = value.decode("utf-8", "replace")
                        elif field == b"data":
                            current_data_parts.append(value)
                # yield
                if current_data_parts or current_event:
                    data = b"\n".join(current_data_parts).decode("utf-8", "replace")
                    evt: dict = {"data": data}
                    if current_event:
                        evt["event"] = current_event
                    if current_id:
                        evt["id"] = current_id
                    if current_id and stream_id:
                        try:
                            runs.record_event_id(stream_id, current_id)
                        except Exception:
                            logger.exception("record_event_id failed")
                    if current_event in _TERMINAL_EVENTS and not fired_terminal:
                        fired_terminal = True
                        try:
                            payload = {}
                            if data:
                                try:
                                    payload = json.loads(data)
                                except Exception:
                                    payload = {}
                            if apns and apns.enabled:
                                dt = runs.device_token_for(stream_id)
                                if dt:
                                    title = payload.get("type") or "Turn complete"
                                    body = payload.get("message") or "JARVIS turn finished"
                                    asyncio.create_task(
                                        apns.send(dt, stream_id, str(title), str(body))
                                    )
                        except Exception:
                            logger.exception("APNs trigger failed")
                        try:
                            runs.record_terminal(stream_id, current_event)
                        except Exception:
                            logger.exception("record_terminal failed")
                    current_id = None
                    current_event = None
                    current_data_parts = []
                    yield evt
    finally:
        await resp.aclose()


@router.get("/api/chat/stream", dependencies=[Depends(require_bearer)])
async def chat_stream(
    request: Request,
    stream_id: str = Query(...),
    after_event_id: str | None = Query(default=None),
    webui: WebUIClient = Depends(get_webui_client),  # noqa: B008
    settings: Settings = Depends(get_settings),  # noqa: B008
    runs: RunsRegistry = Depends(get_registry),  # noqa: B008
) -> StreamingResponse:
    """Phone-facing SSE proxy.

    Forwards `GET /api/chat/stream` from the webui verbatim, optionally
    rewriting `after_event_id` query param (the webui also accepts the
    standard `Last-Event-ID` header, but the query param is robust across
    HTTP/2 → CDN intermediaries).
    """
    params: dict[str, str] = {"stream_id": stream_id}
    if after_event_id:
        params["after_event_id"] = after_event_id

    apns = get_apns()
    gen = _stream_from_webui(webui, "/api/chat/stream", params, settings, runs, apns)
    return EventSourceResponse(gen, ping=5)


@router.get("/api/chat/stream/status", dependencies=[Depends(require_bearer)])
async def chat_stream_status(
    stream_id: str = Query(...),
    webui: WebUIClient = Depends(get_webui_client),  # noqa: B008
) -> dict:
    """Pass-through to webui's reconnect probe."""
    resp = await webui.get("/api/chat/stream/status", params={"stream_id": stream_id})
    try:
        return resp.json()
    except Exception:
        return {"stream_id": stream_id, "active": False, "raw": resp.text[:200]}


@router.get("/api/chat/cancel", dependencies=[Depends(require_bearer)])
async def chat_cancel(
    stream_id: str = Query(...),
    webui: WebUIClient = Depends(get_webui_client),  # noqa: B008
) -> dict:
    """Note: webui accepts GET (we forward GET)."""
    resp = await webui.get("/api/chat/cancel", params={"stream_id": stream_id})
    try:
        return resp.json()
    except Exception:
        return {"ok": False, "stream_id": stream_id, "raw": resp.text[:200]}


@router.post("/api/chat/start", dependencies=[Depends(require_bearer)])
async def chat_start(
    request: Request,
    webui: WebUIClient = Depends(get_webui_client),  # noqa: B008
    runs: RunsRegistry = Depends(get_registry),  # noqa: B008
) -> dict:
    """Start a turn AND record it in the runs registry."""
    body = await request.json()
    body.setdefault("profile", get_settings().jarvis_profile)
    body.setdefault("personality", get_settings().jarvis_personality)
    personality = body.get("personality")
    if isinstance(personality, str) and personality:
        try:
            personality_resp = await webui.post(
                "/api/personality/set",
                json_body={"session_id": body.get("session_id"), "name": personality},
            )
            if personality_resp.status_code >= 400:
                logger.warning(
                    "upstream personality selection failed before chat start: HTTP %s %s",
                    personality_resp.status_code,
                    personality_resp.text[:200],
                )
        except Exception:
            logger.exception("failed to set personality before chat start")
    resp = await webui.post("/api/chat/start", json_body=body)
    try:
        data = resp.json()
    except Exception:
        data = {"raw": resp.text[:400]}
    if "stream_id" in data and "session_id" in data and resp.status_code < 400:
        try:
            runs.record_start(data["stream_id"], data["session_id"])
        except Exception:
            logger.exception("runs.record_start failed")
    return data


@router.post("/mobile/device", dependencies=[Depends(require_bearer)])
async def register_device(
    request: Request,
    runs: RunsRegistry = Depends(get_registry),  # noqa: B008
) -> dict:
    """Register / update the APNs device token.

    Body: {"device_token": "<hex>", "stream_ids": ["..."] (optional)}
    """
    body = await request.json()
    token = body.get("device_token")
    if not token:
        return {"ok": False, "error": "missing device_token"}
    runs.set_device_token(token)
    for sid in body.get("stream_ids", []) or []:
        runs.attach_device_token(sid, token)
    return {"ok": True}
