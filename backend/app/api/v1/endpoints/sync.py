from typing import Annotated
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session
from app.api.deps import get_current_user, get_db
from app.api.v1.endpoints.notes import _format_note_response
from app.models.note import Note, NoteTag
from app.models.sync import AppliedOperation
from app.models.user import User
from app.schemas.sync import (
    SyncOperationResult,
    SyncPullResponse,
    SyncPushRequest,
    SyncPushResponse,
)

router = APIRouter()


@router.post("/push", response_model=SyncPushResponse)
def push_sync_operations(
    request: SyncPushRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> SyncPushResponse:
    """Batch apply client mutations idempotently with conflict detection."""
    results: list[SyncOperationResult] = []

    for op in request.operations:
        # 1. Idempotency check: has this op_id already been applied?
        already_applied = (
            db.query(AppliedOperation)
            .filter(
                AppliedOperation.op_id == op.op_id,
                AppliedOperation.user_id == current_user.id,
            )
            .first()
        )
        if already_applied:
            results.append(
                SyncOperationResult(
                    op_id=op.op_id,
                    entity_id=op.entity_id,
                    status="IGNORED",
                    message="Operation already applied previously",
                )
            )
            continue

        op_type = op.op_type.upper()
        payload = op.payload

        if op_type == "CREATE":
            # Check if note exists
            existing = db.query(Note).filter(Note.id == op.entity_id).first()
            if existing:
                if existing.user_id != current_user.id:
                    results.append(
                        SyncOperationResult(
                            op_id=op.op_id,
                            entity_id=op.entity_id,
                            status="ERROR",
                            message="Note identifier conflicts with another user",
                        )
                    )
                    continue
                # Same user, note already exists: treat as idempotent success
                db.add(AppliedOperation(op_id=op.op_id, user_id=current_user.id))
                db.commit()
                results.append(
                    SyncOperationResult(
                        op_id=op.op_id,
                        entity_id=op.entity_id,
                        status="IGNORED",
                        server_version=existing.version,
                        message="Note already exists",
                    )
                )
                continue

            # Create note
            note = Note(
                id=op.entity_id,
                user_id=current_user.id,
                title=payload.get("title", ""),
                content=payload.get("content", ""),
                project_id=payload.get("project_id"),
                is_pinned=payload.get("is_pinned", False),
                is_archived=payload.get("is_archived", False),
                client_updated_at=op.client_updated_at,
                version=1,
            )
            db.add(note)
            db.flush()

            tags = payload.get("tags", [])
            for raw_tag in tags:
                clean = raw_tag.strip().lower()
                if clean:
                    db.add(NoteTag(note_id=note.id, tag=clean))

            db.add(AppliedOperation(op_id=op.op_id, user_id=current_user.id))
            db.commit()
            db.refresh(note)

            results.append(
                SyncOperationResult(
                    op_id=op.op_id,
                    entity_id=op.entity_id,
                    status="APPLIED",
                    server_version=note.version,
                )
            )

        elif op_type == "UPDATE":
            note = (
                db.query(Note)
                .filter(Note.id == op.entity_id, Note.user_id == current_user.id)
                .first()
            )
            if not note:
                results.append(
                    SyncOperationResult(
                        op_id=op.op_id,
                        entity_id=op.entity_id,
                        status="ERROR",
                        message="Target note not found for update",
                    )
                )
                continue

            # Conflict Detection: has the server version diverged from the client's base version?
            if note.version > op.client_version:
                # Conflict detected! Do NOT overwrite server content.
                results.append(
                    SyncOperationResult(
                        op_id=op.op_id,
                        entity_id=op.entity_id,
                        status="CONFLICT",
                        server_version=note.version,
                        conflict_note=_format_note_response(note),
                        message=f"Conflict detected: server version is {note.version}, client based on {op.client_version}",
                    )
                )
                continue

            # Safe update
            if "title" in payload:
                note.title = payload["title"]
            if "content" in payload:
                note.content = payload["content"]
            if "project_id" in payload:
                note.project_id = payload["project_id"]
            if "is_pinned" in payload:
                note.is_pinned = payload["is_pinned"]
            if "is_archived" in payload:
                note.is_archived = payload["is_archived"]
            if "is_deleted" in payload:
                note.is_deleted = payload["is_deleted"]
            if op.client_updated_at:
                note.client_updated_at = op.client_updated_at

            if "tags" in payload:
                db.query(NoteTag).filter(NoteTag.note_id == note.id).delete()
                for raw_tag in payload["tags"]:
                    clean = raw_tag.strip().lower()
                    if clean:
                        db.add(NoteTag(note_id=note.id, tag=clean))

            note.version += 1
            db.add(AppliedOperation(op_id=op.op_id, user_id=current_user.id))
            db.commit()
            db.refresh(note)

            results.append(
                SyncOperationResult(
                    op_id=op.op_id,
                    entity_id=op.entity_id,
                    status="APPLIED",
                    server_version=note.version,
                )
            )

        elif op_type == "DELETE":
            note = (
                db.query(Note)
                .filter(Note.id == op.entity_id, Note.user_id == current_user.id)
                .first()
            )
            if note:
                note.is_deleted = True
                note.version += 1
                db.add(AppliedOperation(op_id=op.op_id, user_id=current_user.id))
                db.commit()
                db.refresh(note)
                results.append(
                    SyncOperationResult(
                        op_id=op.op_id,
                        entity_id=op.entity_id,
                        status="APPLIED",
                        server_version=note.version,
                    )
                )
            else:
                db.add(AppliedOperation(op_id=op.op_id, user_id=current_user.id))
                db.commit()
                results.append(
                    SyncOperationResult(
                        op_id=op.op_id,
                        entity_id=op.entity_id,
                        status="IGNORED",
                        message="Note already deleted or not found",
                    )
                )

    return SyncPushResponse(results=results)


@router.get("/pull", response_model=SyncPullResponse)
def pull_sync_updates(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    since_version: int = Query(default=0, ge=0, description="Highest server version already known to client"),
    limit: int = Query(default=100, le=500),
) -> SyncPullResponse:
    """Retrieve all updates (including soft-deletions) since since_version for current user."""
    notes = (
        db.query(Note)
        .filter(
            Note.user_id == current_user.id,
            Note.version > since_version,
        )
        .order_by(Note.version.asc())
        .limit(limit)
        .all()
    )

    max_version = since_version
    for n in notes:
        if n.version > max_version:
            max_version = n.version

    # Check if more remain
    remaining = (
        db.query(Note)
        .filter(
            Note.user_id == current_user.id,
            Note.version > max_version,
        )
        .count()
    )

    return SyncPullResponse(
        notes=[_format_note_response(n) for n in notes],
        server_version_watermark=max_version,
        has_more=remaining > 0,
    )
