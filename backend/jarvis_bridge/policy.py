"""JARVIS-owned secretary action policy.

The upstream persona explains this policy to the model, but this module is the
authoritative boundary for JARVIS-owned workflow actions.  Upstream Hermes
approval events are classified for display and remain subject to Hermes'
approval loop.
"""

from __future__ import annotations

from enum import StrEnum


class ActionClass(StrEnum):
    READ_EMAIL = "read_email"
    SUMMARIZE_EMAIL = "summarize_email"
    DRAFT_EMAIL = "draft_email"
    SEND_EMAIL = "send_email"
    MUTATE_EMAIL = "mutate_email"
    READ_CALENDAR = "read_calendar"
    MUTATE_CALENDAR = "mutate_calendar"
    CREATE_TASK = "create_task"
    MUTATE_TASK = "mutate_task"
    DANGEROUS_TERMINAL = "dangerous_terminal"
    WORKSPACE_READ = "workspace_read"
    UNKNOWN = "unknown"


# This is intentionally strict.  It is mirrored in the tracked JARVIS persona
# but is not controlled by model output or an ordinary chat message.
_APPROVAL_REQUIRED = frozenset(
    {
        ActionClass.SEND_EMAIL,
        ActionClass.MUTATE_EMAIL,
        ActionClass.MUTATE_CALENDAR,
        ActionClass.MUTATE_TASK,
        ActionClass.DANGEROUS_TERMINAL,
        ActionClass.UNKNOWN,
    }
)


def requires_approval(action: ActionClass) -> bool:
    """Return whether one explicit approval is required for this action."""
    return action in _APPROVAL_REQUIRED


def classify_action(tool_name: str | None, command: str | None = None) -> ActionClass:
    """Map a tool/command label to the closest JARVIS action class.

    Connector integrations should pass an explicit action class once they are
    added.  This conservative fallback is used for current upstream approval
    events and fails closed for unknown side effects.
    """
    value = " ".join(part for part in (tool_name, command) if part).lower()
    if any(token in value for token in ("send_email", "send email", "gmail_send")):
        return ActionClass.SEND_EMAIL
    if any(
        token in value
        for token in (
            "delete_email",
            "archive_email",
            "move_email",
            "delete email",
            "archive email",
            "move email",
        )
    ):
        return ActionClass.MUTATE_EMAIL
    if any(token in value for token in ("calendar.create", "calendar.update", "calendar.cancel")):
        return ActionClass.MUTATE_CALENDAR
    if any(
        token in value for token in ("task.complete", "task.delete", "complete task", "delete task")
    ):
        return ActionClass.MUTATE_TASK
    if any(token in value for token in ("shell", "terminal", "sudo", "rm -", "chmod")):
        return ActionClass.DANGEROUS_TERMINAL
    if any(token in value for token in ("read_email", "list_email", "gmail_read")):
        return ActionClass.READ_EMAIL
    if any(token in value for token in ("summarize_email", "email_summary")):
        return ActionClass.SUMMARIZE_EMAIL
    if any(token in value for token in ("draft_email", "email_draft")):
        return ActionClass.DRAFT_EMAIL
    if any(token in value for token in ("calendar.list", "calendar.read")):
        return ActionClass.READ_CALENDAR
    if any(token in value for token in ("task.create", "create task")):
        return ActionClass.CREATE_TASK
    if any(token in value for token in ("workspace", "read_file", "list_files")):
        return ActionClass.WORKSPACE_READ
    return ActionClass.UNKNOWN
