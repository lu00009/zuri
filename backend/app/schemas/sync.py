from datetime import datetime
from pydantic import BaseModel, Field
from app.schemas.note import NoteResponse


class SyncOperationIn(BaseModel):
    op_id: str = Field(..., description="Stable client operation UUID for idempotency")
    entity_type: str = Field(default="note")
    entity_id: str = Field(..., description="Target note UUID")
    op_type: str = Field(..., description="CREATE, UPDATE, or DELETE")
    client_version: int = Field(default=0, description="Server version the client based this edit on")
    client_updated_at: datetime | None = None
    payload: dict = Field(default_factory=dict, description="Entity fields to apply")


class SyncPushRequest(BaseModel):
    operations: list[SyncOperationIn] = Field(default_factory=list)


class SyncOperationResult(BaseModel):
    op_id: str
    entity_id: str
    status: str = Field(..., description="APPLIED, CONFLICT, IGNORED, or ERROR")
    server_version: int | None = None
    conflict_note: NoteResponse | None = None
    message: str | None = None


class SyncPushResponse(BaseModel):
    results: list[SyncOperationResult]


class SyncPullResponse(BaseModel):
    notes: list[NoteResponse]
    server_version_watermark: int
    has_more: bool = False
