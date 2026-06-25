import json
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.models import (
    CommandQueueItem,
    Repeater,
    RepeaterPolicySyncStatus,
    RepeaterPolicyTemplate,
    User,
)
from app.db.session import get_db_session
from app.schemas.repeater_policy import (
    RepeaterPolicySyncRequest,
    RepeaterPolicySyncResponse,
    RepeaterPolicySyncStatusResponse,
    RepeaterPolicyTemplateCreateRequest,
    RepeaterPolicyTemplateResponse,
    RepeaterPolicyTemplateUpdateRequest,
    RepeaterPolicyValidateRequest,
    RepeaterPolicyValidateResponse,
)
from app.security.deps import require_roles
from app.services.audit import write_audit_log
from app.services.repeater_policy import (
    normalize_policy_document,
    policy_payload_hash,
    validate_policy_document,
)

router = APIRouter(prefix="/api/repeater-policies")


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _load_policy_json(template: RepeaterPolicyTemplate) -> dict[str, Any]:
    try:
        loaded = json.loads(template.policy_json)
    except json.JSONDecodeError:
        return {}
    return loaded if isinstance(loaded, dict) else {}


def _to_template_response(template: RepeaterPolicyTemplate) -> RepeaterPolicyTemplateResponse:
    return RepeaterPolicyTemplateResponse(
        id=template.id,
        name=template.name,
        description=template.description,
        enabled=template.enabled == 1,
        policy=_load_policy_json(template),
        created_at=template.created_at,
        updated_at=template.updated_at,
    )


def _to_sync_status_response(
    sync_status: RepeaterPolicySyncStatus,
    repeater: Repeater,
) -> RepeaterPolicySyncStatusResponse:
    return RepeaterPolicySyncStatusResponse(
        repeater_id=repeater.id,
        node_name=repeater.node_name,
        template_id=sync_status.template_id,
        command_id=sync_status.command_id,
        payload_hash=sync_status.payload_hash,
        status=sync_status.status,
        error_message=sync_status.error_message,
        queued_at=sync_status.queued_at,
        dispatched_at=sync_status.dispatched_at,
        completed_at=sync_status.completed_at,
        updated_at=sync_status.updated_at,
    )


@router.get("/templates", response_model=list[RepeaterPolicyTemplateResponse])
def list_templates(
    db: Session = Depends(get_db_session),
    _: User = Depends(require_roles("admin", "operator", "viewer")),
) -> list[RepeaterPolicyTemplateResponse]:
    templates = db.scalars(
        select(RepeaterPolicyTemplate).order_by(RepeaterPolicyTemplate.name.asc())
    ).all()
    return [_to_template_response(template) for template in templates]


@router.post(
    "/templates",
    response_model=RepeaterPolicyTemplateResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_template(
    payload: RepeaterPolicyTemplateCreateRequest,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(require_roles("admin", "operator")),
) -> RepeaterPolicyTemplateResponse:
    try:
        normalized_policy = normalize_policy_document(payload.policy)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        ) from exc

    template = RepeaterPolicyTemplate(
        name=payload.name.strip(),
        description=payload.description,
        enabled=1 if payload.enabled else 0,
        policy_json=json.dumps(normalized_policy, sort_keys=True),
    )
    db.add(template)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Repeater policy template already exists",
        ) from exc
    write_audit_log(
        db,
        action="repeater_policy_template_created",
        target_type="repeater_policy_template",
        target_id=template.id,
        user_id=current_user.id,
        details={"name": template.name},
    )
    db.commit()
    db.refresh(template)
    return _to_template_response(template)


@router.patch("/templates/{template_id}", response_model=RepeaterPolicyTemplateResponse)
def update_template(
    template_id: str,
    payload: RepeaterPolicyTemplateUpdateRequest,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(require_roles("admin", "operator")),
) -> RepeaterPolicyTemplateResponse:
    template = db.scalar(
        select(RepeaterPolicyTemplate).where(RepeaterPolicyTemplate.id == template_id)
    )
    if template is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Repeater policy template not found"
        )

    changes = payload.model_dump(exclude_unset=True)
    if "policy" in changes and changes["policy"] is not None:
        try:
            changes["policy"] = normalize_policy_document(changes["policy"])
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
            ) from exc

    if "name" in changes and changes["name"] is not None:
        template.name = str(changes["name"]).strip()
    if "description" in changes:
        template.description = changes["description"]
    if "enabled" in changes and changes["enabled"] is not None:
        template.enabled = 1 if changes["enabled"] else 0
    if "policy" in changes and changes["policy"] is not None:
        template.policy_json = json.dumps(changes["policy"], sort_keys=True)

    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Repeater policy template already exists",
        ) from exc
    write_audit_log(
        db,
        action="repeater_policy_template_updated",
        target_type="repeater_policy_template",
        target_id=template.id,
        user_id=current_user.id,
        details={"changes": {key: value for key, value in changes.items() if key != "policy"}},
    )
    db.commit()
    db.refresh(template)
    return _to_template_response(template)


@router.delete("/templates/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_template(
    template_id: str,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(require_roles("admin", "operator")),
) -> None:
    template = db.scalar(
        select(RepeaterPolicyTemplate).where(RepeaterPolicyTemplate.id == template_id)
    )
    if template is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Repeater policy template not found"
        )
    template_name = template.name
    db.delete(template)
    write_audit_log(
        db,
        action="repeater_policy_template_deleted",
        target_type="repeater_policy_template",
        target_id=template_id,
        user_id=current_user.id,
        details={"name": template_name},
    )
    db.commit()


@router.post("/validate", response_model=RepeaterPolicyValidateResponse)
def validate_policy(
    payload: RepeaterPolicyValidateRequest,
    _: User = Depends(require_roles("admin", "operator", "viewer")),
) -> RepeaterPolicyValidateResponse:
    errors = validate_policy_document(payload.policy)
    if errors:
        return RepeaterPolicyValidateResponse(valid=False, errors=errors)
    return RepeaterPolicyValidateResponse(
        valid=True,
        errors=[],
        normalized_policy=normalize_policy_document(payload.policy),
    )


@router.get("/sync-status", response_model=list[RepeaterPolicySyncStatusResponse])
def list_sync_status(
    db: Session = Depends(get_db_session),
    _: User = Depends(require_roles("admin", "operator", "viewer")),
) -> list[RepeaterPolicySyncStatusResponse]:
    rows = db.execute(
        select(RepeaterPolicySyncStatus, Repeater)
        .join(Repeater, Repeater.id == RepeaterPolicySyncStatus.repeater_id)
        .order_by(Repeater.node_name.asc())
    ).all()
    return [_to_sync_status_response(sync_status, repeater) for sync_status, repeater in rows]


@router.post("/sync", response_model=RepeaterPolicySyncResponse)
def sync_policy(
    payload: RepeaterPolicySyncRequest,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(require_roles("admin", "operator")),
) -> RepeaterPolicySyncResponse:
    template_id: str | None = None
    if payload.template_id:
        template = db.scalar(
            select(RepeaterPolicyTemplate).where(RepeaterPolicyTemplate.id == payload.template_id)
        )
        if template is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Repeater policy template not found"
            )
        if template.enabled != 1:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail="Repeater policy template is disabled"
            )
        policy = _load_policy_json(template)
        template_id = template.id
    else:
        policy = payload.policy or {}

    try:
        normalized_policy = normalize_policy_document(policy)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        ) from exc

    repeaters_query = select(Repeater).where(~Repeater.status.in_(["pending_adoption", "rejected"]))
    if not payload.all_repeaters:
        repeaters_query = repeaters_query.where(Repeater.id.in_(payload.repeater_ids))
    repeaters = db.scalars(repeaters_query.order_by(Repeater.node_name.asc())).all()
    if not repeaters:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No eligible repeaters found"
        )

    now = _utc_now()
    payload_hash = policy_payload_hash(normalized_policy)
    command_ids: list[str] = []
    responses: list[RepeaterPolicySyncStatusResponse] = []
    for repeater in repeaters:
        command_payload = {
            "policy": normalized_policy,
            "mode": payload.mode,
            "validate_only": payload.validate_only,
            "source": "openHop Glass",
        }
        if template_id:
            command_payload["template_id"] = template_id
        command = CommandQueueItem(
            repeater_id=repeater.id,
            command="policy_sync",
            params_json=json.dumps(command_payload, sort_keys=True),
            status="queued",
            requested_by=current_user.email,
        )
        db.add(command)
        db.flush()
        command_ids.append(command.id)

        sync_status = db.scalar(
            select(RepeaterPolicySyncStatus).where(
                RepeaterPolicySyncStatus.repeater_id == repeater.id
            )
        )
        if sync_status is None:
            sync_status = RepeaterPolicySyncStatus(repeater_id=repeater.id)
            db.add(sync_status)
        sync_status.template_id = template_id
        sync_status.command_id = command.id
        sync_status.payload_hash = payload_hash
        sync_status.status = "queued"
        sync_status.error_message = None
        sync_status.queued_at = now
        sync_status.dispatched_at = None
        sync_status.completed_at = None
        sync_status.updated_at = now
        responses.append(_to_sync_status_response(sync_status, repeater))

    write_audit_log(
        db,
        action="repeater_policy_sync_queued",
        target_type="repeater_policy_template" if template_id else "repeater_policy",
        target_id=template_id,
        user_id=current_user.id,
        details={
            "queued_commands": len(command_ids),
            "mode": payload.mode,
            "validate_only": payload.validate_only,
            "reason": payload.reason,
            "all_repeaters": payload.all_repeaters,
        },
    )
    db.commit()
    return RepeaterPolicySyncResponse(
        queued_commands=len(command_ids),
        command_ids=command_ids,
        statuses=responses,
    )
