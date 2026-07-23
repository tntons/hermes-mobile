"""Task/reminder contract used by Phase 2 tests and future connectors."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Protocol
from uuid import uuid4


@dataclass(slots=True, frozen=True)
class JarvisTask:
    task_id: str
    title: str
    notes: str | None = None
    due_at: datetime | None = None
    timezone: str | None = None
    completed: bool = False
    created_at: datetime = field(default_factory=lambda: datetime.now(UTC))


class TaskStore(Protocol):
    def create(
        self,
        title: str,
        *,
        notes: str | None = None,
        due_at: datetime | None = None,
        timezone: str | None = None,
    ) -> JarvisTask: ...

    def list(self) -> list[JarvisTask]: ...


class InMemoryTaskStore:
    """Deterministic fake adapter; production persistence is deferred."""

    def __init__(self) -> None:
        self._tasks: dict[str, JarvisTask] = {}

    def create(
        self,
        title: str,
        *,
        notes: str | None = None,
        due_at: datetime | None = None,
        timezone: str | None = None,
    ) -> JarvisTask:
        task = JarvisTask(
            task_id=str(uuid4()),
            title=title,
            notes=notes,
            due_at=due_at,
            timezone=timezone,
        )
        self._tasks[task.task_id] = task
        return task

    def list(self) -> list[JarvisTask]:
        return list(self._tasks.values())
