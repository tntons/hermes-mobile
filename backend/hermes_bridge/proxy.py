"""Generic JSON pass-through proxy from the bridge to hermes-webui.

The bridge is a 1:1 reverse proxy for `/api/*` (and `/health`). The phone
talks to the bridge over bearer; the bridge talks to the webui over
cookie+CSRF, transparently. SSE lives in `sse_proxy.py`.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, Depends, Request, Response

from .auth import require_bearer
from .webui_client import WebUIClient, get_webui_client

logger = logging.getLogger("hermes_bridge.proxy")

router = APIRouter()


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

    try:
        resp = await webui.request(method, path, params=params, json_body=body if body is not None else None)
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
    excluded = {"content-encoding", "transfer-encoding", "set-cookie", "connection"}
    headers = {k: v for k, v in resp.headers.items() if k.lower() not in excluded}

    return Response(
        content=resp.content,
        media_type=out_ct.split(";")[0].strip(),
        status_code=resp.status_code,
        headers=headers,
    )


@router.api_route(
    "/api/{rest:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    dependencies=[Depends(require_bearer)],
)
async def api_proxy(
    rest: str,
    request: Request,
    webui: WebUIClient = Depends(get_webui_client),
) -> Response:
    """All `/api/*` JSON routes, pass-through with re-auth on 401."""
    # FastAPI has already consumed `rest` into path_params; rebuild from request.url
    return await _passthrough(request, webui)


@router.get("/health", dependencies=[Depends(require_bearer)])
async def health(webui: WebUIClient = Depends(get_webui_client)) -> dict[str, Any]:
    """Public-ish: we still require bearer (the iOS app uses this to ping).

    Returns the webui's `/health` body if reachable, else a stub.
    """
    return await webui.health()


@router.get("/")
async def root() -> dict[str, Any]:
    return {"name": "hermes-mobile-bridge", "version": "0.1.0"}
