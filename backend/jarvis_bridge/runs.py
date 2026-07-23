"""SQLite-backed runs registry.

We track:
  - Every chat turn by `stream_id` (= `run_id`) returned from
    `POST /api/chat/start`.
  - Its session, when it started, its current `last_event_id` (as observed by
    the phone), and any registered APNs device token.
  - Terminal status when a turn completes (`done`/`cancel`/`apperror`).

This is what makes backgrounded-turn survival "stable + seamless" even before
APNs ships — when the phone reconnects, it queries `StreamCursor` and asks the
webui for a journal replay via `after_event_id`.

JSON-file fallback is NOT used because we want full SQL semantics (last write
wins across processes, simple atomic transactions).
"""

from __future__ import annotations

import logging
import sqlite3
import threading
import time
from collections.abc import Iterable
from pathlib import Path
from typing import Any

logger = logging.getLogger("jarvis_bridge.runs")


class RunsRegistry:
    """Threadsafe SQLite registry. One per process is fine."""

    SCHEMA = """
    CREATE TABLE IF NOT EXISTS runs (
        stream_id        TEXT PRIMARY KEY,
        session_id       TEXT NOT NULL,
        device_token     TEXT,
        started_at       REAL NOT NULL,
        last_event_id    TEXT,
        terminal_state   TEXT,
        terminal_at      REAL
    );
    CREATE INDEX IF NOT EXISTS runs_session_idx ON runs(session_id);
    CREATE INDEX IF NOT EXISTS runs_open_idx    ON runs(terminal_state) WHERE terminal_state IS NULL;
    """

    def __init__(self, path: str):
        self._path = path
        # ensure parent dir
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        with self._connect() as conn:
            conn.executescript(self.SCHEMA)
            conn.commit()

    # ---------------- internals ----------------

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self._path, check_same_thread=False, isolation_level=None)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.row_factory = sqlite3.Row
        return conn

    # ---------------- API ----------------

    def record_start(self, stream_id: str, session_id: str) -> None:
        with self._lock, self._connect() as conn:
            conn.execute(
                """INSERT INTO runs(stream_id, session_id, started_at)
                   VALUES (?, ?, ?)
                   ON CONFLICT(stream_id) DO UPDATE SET session_id=excluded.session_id""",
                (stream_id, session_id, time.time()),
            )

    def record_event_id(self, stream_id: str, last_event_id: str) -> None:
        if not last_event_id:
            return
        with self._lock, self._connect() as conn:
            conn.execute(
                "UPDATE runs SET last_event_id=? WHERE stream_id=?",
                (last_event_id, stream_id),
            )

    def record_terminal(
        self,
        stream_id: str,
        state: str,  # "done" | "cancel" | "apperror"
        payload: dict[str, Any] | None = None,
    ) -> None:
        with self._lock, self._connect() as conn:
            conn.execute(
                "UPDATE runs SET terminal_state=?, terminal_at=? WHERE stream_id=?",
                (state, time.time(), stream_id),
            )

    def attach_device_token(self, stream_id: str, device_token: str) -> None:
        with self._lock, self._connect() as conn:
            conn.execute(
                "UPDATE runs SET device_token=? WHERE stream_id=?",
                (device_token, stream_id),
            )

    def set_device_token(self, device_token: str) -> None:
        """Mark any in-flight runs as targeted at this device."""
        with self._lock, self._connect() as conn:
            conn.execute(
                "UPDATE runs SET device_token=? WHERE terminal_state IS NULL",
                (device_token,),
            )

    def device_token_for(self, stream_id: str) -> str | None:
        with self._lock, self._connect() as conn:
            row = conn.execute(
                "SELECT device_token FROM runs WHERE stream_id=?", (stream_id,)
            ).fetchone()
            return row["device_token"] if row else None

    def open_runs_for_device(self, device_token: str) -> list[dict[str, Any]]:
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM runs WHERE device_token=? AND terminal_state IS NULL",
                (device_token,),
            ).fetchall()
            return [dict(r) for r in rows]

    def terminal_summary(self, stream_id: str) -> dict[str, Any] | None:
        with self._lock, self._connect() as conn:
            row = conn.execute("SELECT * FROM runs WHERE stream_id=?", (stream_id,)).fetchone()
            return dict(row) if row else None

    def all_open(self) -> Iterable[dict[str, Any]]:
        with self._lock, self._connect() as conn:
            rows = conn.execute("SELECT * FROM runs WHERE terminal_state IS NULL").fetchall()
            return [dict(r) for r in rows]


_registry: RunsRegistry | None = None


def init_registry(path: str) -> RunsRegistry:
    global _registry
    if _registry is None:
        _registry = RunsRegistry(path)
    return _registry


def get_registry() -> RunsRegistry:
    if _registry is None:
        raise RuntimeError("RunsRegistry not initialized")
    return _registry
