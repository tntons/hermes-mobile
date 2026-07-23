"""Deterministic Phase 2 secretary policy and task-contract tests."""

from datetime import UTC, datetime

import pytest

from jarvis_bridge.approvals import ApprovalRegistry
from jarvis_bridge.policy import ActionClass, classify_action, requires_approval
from jarvis_bridge.tasks import InMemoryTaskStore


@pytest.mark.parametrize(
    ("action", "required"),
    [
        (ActionClass.READ_EMAIL, False),
        (ActionClass.SUMMARIZE_EMAIL, False),
        (ActionClass.DRAFT_EMAIL, False),
        (ActionClass.SEND_EMAIL, True),
        (ActionClass.MUTATE_EMAIL, True),
        (ActionClass.READ_CALENDAR, False),
        (ActionClass.MUTATE_CALENDAR, True),
        (ActionClass.CREATE_TASK, False),
        (ActionClass.MUTATE_TASK, True),
        (ActionClass.DANGEROUS_TERMINAL, True),
        (ActionClass.UNKNOWN, True),
    ],
)
def test_default_policy_matrix(action, required):
    assert requires_approval(action) is required


@pytest.mark.parametrize(
    ("tool", "command", "expected"),
    [
        ("gmail_send", "", ActionClass.SEND_EMAIL),
        ("", "delete email from inbox", ActionClass.MUTATE_EMAIL),
        ("calendar.update", "", ActionClass.MUTATE_CALENDAR),
        ("task.create", "", ActionClass.CREATE_TASK),
        ("shell", "rm -rf /tmp/demo", ActionClass.DANGEROUS_TERMINAL),
        ("unknown_connector", "", ActionClass.UNKNOWN),
    ],
)
def test_action_classification_is_conservative(tool, command, expected):
    assert classify_action(tool, command) is expected


def test_fake_task_store_allows_creation_without_production_persistence():
    store = InMemoryTaskStore()
    task = store.create(
        "Call the dentist",
        notes="Ask for an afternoon appointment",
        due_at=datetime(2026, 8, 1, 9, tzinfo=UTC),
        timezone="Asia/Bangkok",
    )
    assert task.completed is False
    assert store.list() == [task]


def test_approval_registry_is_one_action_and_expires(tmp_path):
    registry = ApprovalRegistry(str(tmp_path / "approvals.sqlite"), ttl_seconds=0)
    record = registry.register(
        approval_id="expire-me",
        session_id="session-1",
        stream_id="stream-1",
        tool_name="gmail_send",
        command="send email",
        description="Send the draft",
    )
    assert record.status == "pending"
    assert registry.get("expire-me").status == "expired"
    with pytest.raises(KeyError):
        registry.decide("missing", "approve")
