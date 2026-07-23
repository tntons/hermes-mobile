"""JARVIS Mobile Bridge — FastAPI app entry point."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from .apns import init_apns
from .config import get_settings
from .proxy import router as proxy_router
from .runs import init_registry
from .sse_proxy import router as sse_router
from .webui_client import init_webui_client

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
)
logger = logging.getLogger("jarvis_bridge")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    settings = get_settings()
    if not settings.mobile_token.get_secret_value():
        logger.warning("MOBILE_TOKEN is empty — all phone requests will get 503")
    if not settings.webui_password.get_secret_value():
        logger.warning("WEBUI_PASSWORD is empty — webui login will fail")

    init_registry(settings.runs_db_path)
    apns = init_apns(settings)
    webui = await init_webui_client(settings)
    logger.info(
        "Bridge ready (webui=%s, apns=%s, runs_db=%s)",
        settings.webui_base_url,
        apns.enabled,
        settings.runs_db_path,
    )
    try:
        yield
    finally:
        await webui.close()
        logger.info("Bridge shutting down")


app = FastAPI(
    title="JARVIS Mobile Bridge",
    description="Bearer-auth adapter between the JARVIS iPhone app and hermes-webui.",
    version="0.1.0",
    lifespan=lifespan,
)

# Order matters: SSE router first so its path matches `/api/chat/stream`
# before the generic `/api/{rest}` catch-all in the JSON proxy.
app.include_router(sse_router)
app.include_router(proxy_router)


@app.get("/__bridge/health")
async def bridge_health() -> dict[str, str]:
    """Ungated liveness for Docker/orchestrator probes."""
    return {"status": "ok"}


@app.get("/__bridge/version")
async def bridge_version() -> dict[str, str]:
    return {"name": "jarvis-mobile-bridge", "version": "0.1.0"}
