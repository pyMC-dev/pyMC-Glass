from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator


class RepeaterPolicyTemplateCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    description: str | None = Field(default=None, max_length=2048)
    enabled: bool = True
    policy: dict[str, Any]


class RepeaterPolicyTemplateUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=128)
    description: str | None = Field(default=None, max_length=2048)
    enabled: bool | None = None
    policy: dict[str, Any] | None = None


class RepeaterPolicyTemplateResponse(BaseModel):
    id: str
    name: str
    description: str | None = None
    enabled: bool
    policy: dict[str, Any]
    created_at: datetime
    updated_at: datetime


class RepeaterPolicyValidateRequest(BaseModel):
    policy: dict[str, Any]


class RepeaterPolicyValidateResponse(BaseModel):
    valid: bool
    errors: list[str] = Field(default_factory=list)
    normalized_policy: dict[str, Any] | None = None


class RepeaterPolicySyncRequest(BaseModel):
    template_id: str | None = None
    policy: dict[str, Any] | None = None
    repeater_ids: list[str] = Field(default_factory=list)
    all_repeaters: bool = False
    mode: Literal["replace", "patch"] = "replace"
    validate_only: bool = False
    reason: str | None = Field(default=None, max_length=256)

    @model_validator(mode="after")
    def validate_payload(self) -> "RepeaterPolicySyncRequest":
        if not self.template_id and self.policy is None:
            raise ValueError("template_id or policy is required")
        if self.template_id and self.policy is not None:
            raise ValueError("template_id and policy are mutually exclusive")
        if not self.all_repeaters and not self.repeater_ids:
            raise ValueError("all_repeaters or repeater_ids is required")
        return self


class RepeaterPolicySyncStatusResponse(BaseModel):
    repeater_id: str
    node_name: str
    template_id: str | None = None
    command_id: str | None = None
    payload_hash: str | None = None
    status: str
    error_message: str | None = None
    queued_at: datetime | None = None
    dispatched_at: datetime | None = None
    completed_at: datetime | None = None
    updated_at: datetime | None = None


class RepeaterPolicySyncResponse(BaseModel):
    queued_commands: int
    command_ids: list[str]
    statuses: list[RepeaterPolicySyncStatusResponse]
