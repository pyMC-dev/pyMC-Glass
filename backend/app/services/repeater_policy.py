from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import RepeaterPolicySyncStatus

SUPPORTED_ACTIONS = {"allow", "drop", "log_only"}
SUPPORTED_LOGICAL_KEYS = {"all", "any"}


def normalize_policy_document(policy: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(policy, dict):
        raise ValueError("policy must be an object")

    normalized = dict(policy)
    normalized["enabled"] = bool(normalized.get("enabled", True))
    default_action = str(normalized.get("default_action", "allow")).strip()
    if default_action not in SUPPORTED_ACTIONS:
        raise ValueError("default_action must be one of allow, drop, log_only")
    normalized["default_action"] = default_action

    rules = normalized.get("rules", [])
    if rules is None:
        rules = []
    if not isinstance(rules, list):
        raise ValueError("rules must be a list")
    normalized_rules: list[dict[str, Any]] = []
    for index, rule in enumerate(rules):
        normalized_rules.append(_normalize_rule(rule, index=index))
    normalized["rules"] = normalized_rules

    objects = normalized.get("objects", {})
    if objects is None:
        objects = {}
    if not isinstance(objects, dict):
        raise ValueError("objects must be an object")
    normalized["objects"] = objects
    return normalized


def policy_payload_hash(policy: dict[str, Any]) -> str:
    encoded = json.dumps(policy, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _utc_now() -> datetime:
    return datetime.now(UTC)


def mark_repeater_policy_sync_dispatched(
    db: Session,
    *,
    repeater_id: str,
    command_id: str,
) -> None:
    row = db.scalar(
        select(RepeaterPolicySyncStatus).where(RepeaterPolicySyncStatus.repeater_id == repeater_id)
    )
    if row is None:
        row = RepeaterPolicySyncStatus(repeater_id=repeater_id)
        db.add(row)
    now = _utc_now()
    row.command_id = command_id
    row.status = "dispatched"
    row.dispatched_at = now
    row.updated_at = now


def mark_repeater_policy_sync_result(
    db: Session,
    *,
    repeater_id: str,
    command_id: str,
    status: str,
    message: str | None,
    completed_at: datetime | None,
) -> None:
    row = db.scalar(
        select(RepeaterPolicySyncStatus).where(RepeaterPolicySyncStatus.repeater_id == repeater_id)
    )
    if row is None:
        row = RepeaterPolicySyncStatus(repeater_id=repeater_id)
        db.add(row)
    normalized_status = status.lower().strip()
    if normalized_status not in {"success", "failed", "partial"}:
        normalized_status = "failed"
    now = _utc_now()
    row.command_id = command_id
    row.status = normalized_status
    row.error_message = message if normalized_status in {"failed", "partial"} else None
    row.completed_at = completed_at or now
    row.updated_at = now


def validate_policy_document(policy: dict[str, Any]) -> list[str]:
    try:
        normalize_policy_document(policy)
    except ValueError as exc:
        return [str(exc)]
    return []


def _normalize_rule(rule: Any, *, index: int) -> dict[str, Any]:
    if not isinstance(rule, dict):
        raise ValueError(f"rules[{index}] must be an object")
    normalized = dict(rule)
    name = str(normalized.get("name") or f"rule-{index + 1}").strip()
    if not name:
        raise ValueError(f"rules[{index}].name cannot be empty")
    normalized["name"] = name
    normalized["enabled"] = bool(normalized.get("enabled", True))

    condition = normalized.get("if", {})
    if not isinstance(condition, dict):
        raise ValueError(f"rules[{index}].if must be an object")
    if condition:
        logical_keys = [key for key in condition if key in SUPPORTED_LOGICAL_KEYS]
        if len(logical_keys) != 1:
            raise ValueError(f"rules[{index}].if must contain exactly one of all or any")
        entries = condition[logical_keys[0]]
        if not isinstance(entries, list) or not entries:
            raise ValueError(f"rules[{index}].if.{logical_keys[0]} must be a non-empty list")
        for entry_index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                raise ValueError(
                    f"rules[{index}].if.{logical_keys[0]}[{entry_index}] must be an object"
                )
            if "field" not in entry or not str(entry.get("field") or "").strip():
                raise ValueError(
                    f"rules[{index}].if.{logical_keys[0]}[{entry_index}].field is required"
                )
            if "op" not in entry and "operator" not in entry:
                raise ValueError(
                    f"rules[{index}].if.{logical_keys[0]}[{entry_index}].op is required"
                )
    normalized["if"] = condition

    then = normalized.get("then")
    if not isinstance(then, dict):
        raise ValueError(f"rules[{index}].then must be an object")
    action = str(then.get("action", "")).strip()
    if action not in SUPPORTED_ACTIONS:
        raise ValueError(f"rules[{index}].then.action must be one of allow, drop, log_only")
    normalized["then"] = dict(then, action=action)
    return normalized
