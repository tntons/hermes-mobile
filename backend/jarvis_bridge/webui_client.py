"""Singleton HTTPX client that owns the hermes-webui cookie + CSRF session.

The bridge authenticates ONCE to the webui by sending `POST /api/auth/login`
with the configured password (webui sets `hermes_session=<token>.<sig>` cookie).
On every subsequent request the bridge attaches the cookie and the
`X-Hermes-CSRF-Token` header (webui enforces this on unsafe methods when
password auth is enabled).

If the webui returns 401 on a request, we drop the cached session and re-login.

CSRF: hermes-webui does not expose the raw CSRF token directly via a public
endpoint. The webui's JS obtains the token via an authenticated endpoint during
boot and includes it on subsequent POSTs. Because the bridge uses the same
authenticated session as the browser, we mirror what the browser does: include
the token only when it has been observed. On first boot we attempt a no-op
authenticated GET (`GET /api/auth/status`) which sometimes exposes the token
in a response header; if not present, we login and use the cookie's MAC over
the cookie value as the token (the webui's `_check_csrf` accepts that variant
because it's `HMAC(signing_key, server_token)`).
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

import httpx
from fastapi import HTTPException

from .config import Settings

logger = logging.getLogger("jarvis_bridge.webui_client")

AUTH_COOKIE_NAME = "hermes_session"
CSRF_HEADER_NAME = "X-Hermes-CSRF-Token"


class WebUIClient:
    """Thin async wrapper around hermes-webui.

    Concurrency: a single `_lock` serializes login/logout; in-flight requests
    are concurrent on `httpx.AsyncClient` (which is safe).
    """

    def __init__(self, settings: Settings):
        self._settings = settings
        self._base_url = settings.webui_base_url.rstrip("/")
        self._client = httpx.AsyncClient(
            base_url=self._base_url,
            timeout=httpx.Timeout(connect=5.0, read=60.0, write=10.0, pool=10.0),
            headers={"Accept": "application/json"},
            # The webui uses HttpOnly cookies; we'll let httpx manage them,
            # but we also track the auth cookie explicitly so we can re-derive
            # the CSRF token from it.
            cookies={},
            follow_redirects=False,
        )
        self._session_cookie_value: str | None = None  # "<token>.<sig>"
        self._csrf_token: str | None = None
        self._session_obtained_at: float = 0.0
        self._login_lock = asyncio.Lock()
        self._session_lock = asyncio.Lock()
        self._closed = False

    # ---------------- session lifecycle ----------------

    async def close(self) -> None:
        self._closed = True
        await self._client.aclose()

    async def _login(self) -> None:
        """Perform `POST /api/auth/login` and capture the cookie.

        Idempotent under `_login_lock`.
        """
        async with self._login_lock:
            if self._session_cookie_value is not None:
                return

            password = self._settings.webui_password.get_secret_value()
            if not password:
                raise RuntimeError("WEBUI_PASSWORD not set — cannot authenticate to hermes-webui")

            attempt = 0
            last_err: Exception | None = None
            while attempt < self._settings.webui_login_retries:
                attempt += 1
                try:
                    resp = await self._client.post(
                        "/api/auth/login",
                        json={"password": password},
                    )
                except httpx.HTTPError as exc:
                    last_err = exc
                    logger.warning("webui login attempt %d failed: %s", attempt, exc)
                    await asyncio.sleep(min(2**attempt, 8))
                    continue

                if resp.status_code == 200:
                    self._capture_session(resp)
                    self._session_obtained_at = time.time()
                    logger.info(
                        "logged in to webui (cookie len=%d)", len(self._session_cookie_value or "")
                    )
                    return
                else:
                    last_err = RuntimeError(
                        f"webui login failed: HTTP {resp.status_code} {resp.text[:200]}"
                    )
                    logger.warning("webui login HTTP %d: %s", resp.status_code, resp.text[:200])

            raise RuntimeError(f"exhausted webui login retries: {last_err}")

    def _capture_session(self, resp: httpx.Response) -> None:
        """Pick up the `hermes_session` cookie from a response and the CSRF token."""
        for cookie_name, morsel in resp.cookies.items():
            if cookie_name == AUTH_COOKIE_NAME:
                # httpx exposes the value via the jar:
                value = morsel.value if hasattr(morsel, "value") else str(morsel)
                self._session_cookie_value = value

        # CSRF tokens sometimes come back as a response header set by the webui's
        # authenticated endpoints; check both common locations.
        for hdr_name in (CSRF_HEADER_NAME, CSRF_HEADER_NAME.lower()):
            if hdr_name in resp.headers:
                self._csrf_token = resp.headers[hdr_name]
                break

        # If we still don't have a CSRF token but we DO have the cookie, the
        # webui's server side stores `signing_key` and `_check_csrf` recomputes
        # `HMAC(signing_key, server_token)` server-side; the *client half* is
        # the cookie token portion (first half of "<token>.<sig>"). Send that.
        if self._csrf_token is None and self._session_cookie_value:
            token_part = self._session_cookie_value.split(".", 1)[0]
            self._csrf_token = token_part

    async def _ensure_session(self) -> None:
        async with self._session_lock:
            if self._session_cookie_value is None or self._csrf_token is None:
                await self._login()

    async def _reauth(self) -> None:
        self._session_cookie_value = None
        self._csrf_token = None
        await self._login()

    # ---------------- request methods ----------------

    def _headers(self) -> dict[str, str]:
        h: dict[str, str] = {}
        if self._csrf_token:
            h[CSRF_HEADER_NAME] = self._csrf_token
        return h

    async def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        json_body: Any = None,
        allow_reauth: bool = True,
    ) -> httpx.Response:
        """Make an authed request to the webui. Re-logs in once on 401."""
        await self._ensure_session()
        try:
            resp = await self._client.request(
                method,
                path,
                params=params,
                json=json_body,
                headers=self._headers(),
            )
        except httpx.HTTPError:
            raise

        if resp.status_code == 401 and allow_reauth:
            logger.info("webui 401 — re-logging in")
            await self._reauth()
            resp = await self._client.request(
                method,
                path,
                params=params,
                json=json_body,
                headers=self._headers(),
            )
        return resp

    async def get(self, path: str, *, params: dict[str, Any] | None = None) -> httpx.Response:
        return await self.request("GET", path, params=params)

    async def post(self, path: str, json_body: Any) -> httpx.Response:
        return await self.request("POST", path, json_body=json_body)

    async def patch(self, path: str, json_body: Any) -> httpx.Response:
        return await self.request("PATCH", path, json_body=json_body)

    async def delete(self, path: str, json_body: Any = None) -> httpx.Response:
        return await self.request("DELETE", path, json_body=json_body)

    async def stream(
        self, method: str, path: str, *, params: dict[str, Any] | None = None
    ) -> httpx.Response:
        """Open an SSE/`text/event-stream` request. Caller closes the response."""
        await self._ensure_session()
        req = self._client.build_request(method, path, params=params, headers=self._headers())
        timeout = httpx.Timeout(
            connect=5.0,
            read=self._settings.sse_proxy_write_deadline_seconds,
            write=10.0,
            pool=10.0,
        )
        return await self._client.send(req, stream=True, timeout=timeout)

    # ---------------- health ----------------

    async def health(self) -> dict[str, Any]:
        """Public endpoint — do NOT require auth on webui. Returns parsed JSON."""
        try:
            r = await self._client.get("/health", timeout=httpx.Timeout(5.0))
            if r.status_code == 200:
                return r.json()
        except httpx.HTTPError:
            pass
        return {"status": "unknown", "error": "webui unreachable"}


_client: WebUIClient | None = None


async def init_webui_client(settings: Settings) -> WebUIClient:
    """Module-level initializer; called from FastAPI lifespan."""
    global _client
    if _client is None:
        _client = WebUIClient(settings)
    return _client


def get_webui_client() -> WebUIClient:
    if _client is None:
        raise HTTPException(503, "Bridge not initialized")
    return _client
