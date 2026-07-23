"""Durable, one-action approval records and the mobile approval API."""

from __future__ import annotations

import json
import logging
import sqlite3
import threading
import time
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from .auth import require_bearer
from .policy import ActionClass, classify_action
from .webui_client import WebUIClient, get_webui_client

logger = logging.getLogger("jarvis_bridge.approvals")

APPROVAL_TTL_SECONDS = 15 * 60


class ApprovalDecisionBody(BaseModel):
    decision: Literal["approve", "deny"]


class ApprovalRecord(BaseModel):
    approval_id: str
    session_id: str
    stream_id: str | None = None
    action_class: ActionClass
    tool_name: str
    command: str
    description: str
    choices: list[str] = Field(default_factory=lambda: ["approve", "deny"])
    source: Literal["upstream", "jarvis"]
    upstream_approval_id: str | None = None
    status: Literal["pending", "approved", "denied", "expired", "consumed"]
    created_at: float
    expires_at: float
    decided_at: float | None = None


class ApprovalRegistry:
    """SQLite-backed approval state shared by bridge requests and reconnects."""

    SCHEMA = """
    CREATE TABLE IF NOT EXISTS approval_requests (
        approval_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        stream_id TEXT,
        action_class TEXT NOT NULL,
        tool_name TEXT NOT NULL,
        command TEXT NOT NULL,
        description TEXT NOT NULL,
        choices_json TEXT NOT NULL,
        source TEXT NOT NULL,
        upstream_approval_id TEXT,
        status TEXT NOT NULL,
        created_at REAL NOT NULL,
        expires_at REAL NOT NULL,
        decided_at REAL
    );
    CREATE INDEX IF NOT EXISTS approval_status_idx ON approval_requests(status, expires_at);
    """

    def __init__(self, path: str, ttl_seconds: float = APPROVAL_TTL_SECONDS):
        self._path = path
        self._ttl_seconds = ttl_seconds
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        with self._connect() as conn:
            conn.executescript(self.SCHEMA)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self._path, check_same_thread=False, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        return conn

    def register(
        self,
        *,
        approval_id: str,
        session_id: str,
        stream_id: str | None,
        tool_name: str,
        command: str,
        description: str,
        choices: list[str] | None = None,
        source: Literal["upstream", "jarvis"] = "upstream",
        upstream_approval_id: str | None = None,
    ) -> ApprovalRecord:
        now = time.time()
        expires = now + self._ttl_seconds
        action = classify_action(tool_name, command)
        choices_json = json.dumps(choices or ["approve", "deny"])
        with self._lock, self._connect() as conn:
            conn.execute(
                """INSERT OR IGNORE INTO approval_requests(
                    approval_id, session_id, stream_id, action_class, tool_name,
                    command, description, choices_json, source, upstream_approval_id,
                    status, created_at, expires_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)""",
                (
                    approval_id,
                    session_id,
                    stream_id,
                    action.value,
                    tool_name,
                    command,
                    description,
                    choices_json,
                    source,
                    upstream_approval_id,
                    now,
                    expires,
                ),
            )
            row = conn.execute(
                "SELECT * FROM approval_requests WHERE approval_id=?", (approval_id,)
            ).fetchone()
        assert row is not None
        return self._row(row)

    def _expire_locked(self, conn: sqlite3.Connection) -> None:
        conn.execute(
            """UPDATE approval_requests SET status='expired', decided_at=?
               WHERE status='pending' AND expires_at <= ?""",
            (time.time(), time.time()),
        )

    def list(self, status: str | None = "pending") -> list[ApprovalRecord]:
        with self._lock, self._connect() as conn:
            self._expire_locked(conn)
            if status:
                rows = conn.execute(
                    "SELECT * FROM approval_requests WHERE status=? ORDER BY created_at DESC",
                    (status,),
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM approval_requests ORDER BY created_at DESC"
                ).fetchall()
        return [self._row(row) for row in rows]

    def get(self, approval_id: str) -> ApprovalRecord | None:
        with self._lock, self._connect() as conn:
            self._expire_locked(conn)
            row = conn.execute(
                "SELECT * FROM approval_requests WHERE approval_id=?", (approval_id,)
            ).fetchone()
        return self._row(row) if row else None

    def decide(self, approval_id: str, decision: Literal["approve", "deny"]) -> ApprovalRecord:
        with self._lock, self._connect() as conn:
            self._expire_locked(conn)
            row = conn.execute(
                "SELECT * FROM approval_requests WHERE approval_id=?", (approval_id,)
            ).fetchone()
            if row is None:
                raise KeyError(approval_id)
            if row["status"] != "pending":
                return self._row(row)
            status = "approved" if decision == "approve" else "denied"
            decided_at = time.time()
            conn.execute(
                "UPDATE approval_requests SET status=?, decided_at=? WHERE approval_id=? AND status='pending'",
                (status, decided_at, approval_id),
            )
            row = conn.execute(
                "SELECT * FROM approval_requests WHERE approval_id=?", (approval_id,)
            ).fetchone()
        assert row is not None
        return self._row(row)

    def mark_consumed(self, approval_id: str) -> ApprovalRecord | None:
        with self._lock, self._connect() as conn:
            conn.execute(
                "UPDATE approval_requests SET status='consumed' WHERE approval_id=? AND status='approved'",
                (approval_id,),
            )
            row = conn.execute(
                "SELECT * FROM approval_requests WHERE approval_id=?", (approval_id,)
            ).fetchone()
        return self._row(row) if row else None

    @staticmethod
    def _row(row: sqlite3.Row) -> ApprovalRecord:
        return ApprovalRecord(
            approval_id=row["approval_id"],
            session_id=row["session_id"],
            stream_id=row["stream_id"],
            action_class=ActionClass(row["action_class"]),
            tool_name=row["tool_name"],
            command=row["command"],
            description=row["description"],
            choices=json.loads(row["choices_json"]),
            source=row["source"],
            upstream_approval_id=row["upstream_approval_id"],
            status=row["status"],
            created_at=row["created_at"],
            expires_at=row["expires_at"],
            decided_at=row["decided_at"],
        )


_registry: ApprovalRegistry | None = None


def init_approval_registry(
    path: str, ttl_seconds: float = APPROVAL_TTL_SECONDS
) -> ApprovalRegistry:
    global _registry
    if _registry is None:
        _registry = ApprovalRegistry(path, ttl_seconds)
    return _registry


def get_approval_registry() -> ApprovalRegistry:
    if _registry is None:
        raise RuntimeError("ApprovalRegistry not initialized")
    return _registry


router = APIRouter()


@router.get("/mobile/approvals", dependencies=[Depends(require_bearer)])
async def list_approvals(
    status: str | None = "pending",
    registry: ApprovalRegistry = Depends(get_approval_registry),  # noqa: B008
) -> dict[str, list[ApprovalRecord]]:
    if status not in {None, "pending", "approved", "denied", "expired", "consumed"}:
        raise HTTPException(status_code=400, detail="invalid approval status")
    return {"approvals": registry.list(status)}


@router.get("/mobile/approvals/{approval_id}", dependencies=[Depends(require_bearer)])
async def get_approval(
    approval_id: str,
    registry: ApprovalRegistry = Depends(get_approval_registry),  # noqa: B008
) -> ApprovalRecord:
    record = registry.get(approval_id)
    if record is None:
        raise HTTPException(status_code=404, detail="approval not found")
    return record


async def _forward_upstream_decision(
    record: ApprovalRecord,
    webui: WebUIClient,
    decision: Literal["approve", "deny"],
) -> None:
    """Forward only the supported one-action choice to Hermes."""
    if record.source != "upstream":
        return
    payload: dict[str, str] = {
        "approval_id": record.approval_id,
        "choice": "once" if decision == "approve" else "deny",
    }
    if record.upstream_approval_id:
        payload["approval_id"] = record.upstream_approval_id
    if record.stream_id:
        payload["run_id"] = record.stream_id
    response = await webui.post("/api/approval/respond", json_body=payload)
    if response.status_code >= 400:
        raise HTTPException(
            status_code=502,
            detail=f"upstream approval response failed: HTTP {response.status_code}",
        )


@router.post(
    "/mobile/approvals/{approval_id}/decision",
    dependencies=[Depends(require_bearer)],
)
async def decide_approval(
    approval_id: str,
    body: ApprovalDecisionBody,
    registry: ApprovalRegistry = Depends(get_approval_registry),  # noqa: B008
    webui: WebUIClient = Depends(get_webui_client),  # noqa: B008
) -> ApprovalRecord:
    try:
        record = registry.decide(approval_id, body.decision)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="approval not found") from exc
    if record.status in {"expired", "consumed"}:
        raise HTTPException(status_code=409, detail=f"approval is {record.status}")
    if record.status == "approved" and body.decision == "approve":
        await _forward_upstream_decision(record, webui, body.decision)
        return registry.mark_consumed(approval_id) or record
    if record.status == "denied" and body.decision == "deny":
        await _forward_upstream_decision(record, webui, body.decision)
        return record
    raise HTTPException(status_code=409, detail="approval was already decided")
