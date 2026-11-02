from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


class NoteBase(BaseModel):
    title: str = Field(default="", max_length=500)
    content: str = Field(default="")
    project_id: str | None = Field(default=None, max_length=255)
    tags: list[str] = Field(default_factory=list)
    is_pinned: bool = False
    is_archived: bool = False


class NoteCreate(NoteBase):
    id: str | None = Field(
        default=None,
        description="Optional client-generated UUID for offline creation",
    )
    client_updated_at: datetime | None = None


class NoteUpdate(BaseModel):
    title: str | None = Field(default=None, max_length=500)
    content: str | None = None
    project_id: str | None = None
    tags: list[str] | None = None
    is_pinned: bool | None = None
    is_archived: bool | None = None
    is_deleted: bool | None = None


class NoteResponse(BaseModel):
    id: str
    user_id: str
    title: str
    content: str
    project_id: str | None
    tags: list[str] = Field(default_factory=list)
    is_pinned: bool
    is_archived: bool
    is_deleted: bool
    version: int
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class NotesListResponse(BaseModel):
    items: list[NoteResponse]
    total: int
