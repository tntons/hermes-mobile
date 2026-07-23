"""Bearer-token auth dependency for the bridge.

The iOS app sends `Authorization: Bearer <MOBILE_TOKEN>` on every request.
We don't have (and don't want) the bridge ever to talk to the webui without its
cookie+CSRF — that's `WebUIClient`'s job. This module only gates the phone → bridge.
"""

from __future__ import annotations

import secrets

from fastapi import Depends, Header, HTTPException, status

from .config import Settings, get_settings


def require_bearer(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),  # noqa: B008
) -> None:
    """FastAPI dependency. Constant-time compares the bearer token."""
    expected = settings.mobile_token.get_secret_value()
    if not expected:
        # Misconfigured server: refuse all requests rather than fail open.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Bridge not configured: MOBILE_TOKEN is empty.",
        )

    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": 'Bearer realm="jarvis-mobile"'},
        )

    presented = authorization[7:].strip()
    if not secrets.compare_digest(presented, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bearer token",
            headers={"WWW-Authenticate": 'Bearer realm="jarvis-mobile"'},
        )
