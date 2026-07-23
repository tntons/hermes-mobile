"""Optional APNs client (v1.1). Wired but inert when not configured."""

from __future__ import annotations

import logging
from typing import Any

from .config import Settings

logger = logging.getLogger("jarvis_bridge.apns")


class APNsClient:
    """Lazy APNs HTTP/2 client using `apns2`.

    Sends a background push with a `thread-id` per session so multiple turns
    from the same session thread.
    """

    def __init__(self, settings: Settings):
        self._settings = settings
        self._client: Any | None = None

    @property
    def enabled(self) -> bool:
        return self._settings.apns_configured

    def _ensure(self) -> None:
        if self._client is not None or not self.enabled:
            return
        try:
            from apns2.client import APNsClient as _Client  # type: ignore
            from apns2.credentials import TokenCredentials  # type: ignore

            creds = TokenCredentials(
                auth_key_path=self._settings.apns_key_path,
                auth_key_id=self._settings.apns_key_id,
                team_id=self._settings.apns_team_id,
            )
            self._client = _Client(creds, use_sandbox=self._settings.apns_use_sandbox)
            logger.info("APNs client initialized (sandbox=%s)", self._settings.apns_use_sandbox)
        except Exception as exc:  # pragma: no cover
            logger.warning("APNs init failed: %s — push disabled", exc)
            self._enabled_safe = False

    async def send(
        self,
        device_token: str,
        session_id: str,
        title: str,
        body: str,
    ) -> bool:
        if not self.enabled:
            return False
        self._ensure()
        if self._client is None:
            return False
        try:
            from apns2.payload import Payload as _Payload  # type: ignore

            payload = _Payload(
                alert={"title": title, "body": body},
                sound="default",
                thread_id=session_id,
                # `content-available: 1` would deliver a silent push; we use a
                # visible push so the user actually sees completion.
            )
            # apns2 is sync — push to a thread to keep this non-blocking.
            import anyio

            def _send() -> None:
                try:
                    self._client.send_notification(
                        device_token,
                        payload,
                        topic=self._settings.apns_topic,
                    )
                except Exception as exc:
                    logger.warning("APNs send failed: %s", exc)

            await anyio.to_thread.run_sync(_send)
            return True
        except Exception as exc:
            logger.warning("APNs send exception: %s", exc)
            return False


_apns: APNsClient | None = None


def init_apns(settings: Settings) -> APNsClient:
    global _apns
    if _apns is None:
        _apns = APNsClient(settings)
    return _apns


def get_apns() -> APNsClient | None:
    return _apns
