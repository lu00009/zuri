import uuid
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import distinct, or_, select
from sqlalchemy.orm import Session
from app.api.deps import get_current_user, get_db
from app.models.note import Note, NoteTag
from app.models.user import User
from app.schemas.note import NoteCreate, NoteResponse, NotesListResponse, NoteUpdate

router = APIRouter()


def _format_note_response(note: Note) -> NoteResponse:
    tags = [t.tag for t in note.tags] if note.tags else []
    return NoteResponse(
        id=note.id,
        user_id=note.user_id,
        title=note.title,
        content=note.content,
        project_id=note.project_id,
        tags=tags,
        is_pinned=note.is_pinned,
        is_archived=note.is_archived,
        is_deleted=note.is_deleted,
        version=note.version,
        created_at=note.created_at,
        updated_at=note.updated_at,
    )


@router.get("", response_model=NotesListResponse)
def list_notes(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    is_archived: bool = False,
    search: str | None = Query(default=None, description="Search term for title or content"),
    tag: str | None = Query(default=None, description="Filter by tag"),
    project_id: str | None = Query(default=None, description="Filter by project ID"),
    skip: int = 0,
    limit: int = 50,
) -> NotesListResponse:
    """Retrieve all notes belonging to the authenticated user."""
    query = db.query(Note).filter(
        Note.user_id == current_user.id,
        Note.is_deleted.is_(False),
        Note.is_archived == is_archived,
    )

    if project_id:
        query = query.filter(Note.project_id == project_id)

    if search and search.strip():
        term = f"%{search.strip()}%"
        query = query.filter(or_(Note.title.ilike(term), Note.content.ilike(term)))

    if tag and tag.strip():
        clean_tag = tag.strip().lower()
        query = query.join(Note.tags).filter(NoteTag.tag == clean_tag)

    total = query.count()
    notes = (
        query.order_by(Note.is_pinned.desc(), Note.updated_at.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )

    return NotesListResponse(
        items=[_format_note_response(n) for n in notes],
        total=total,
    )


@router.post("", response_model=NoteResponse, status_code=status.HTTP_201_CREATED)
def create_note(
    note_in: NoteCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> NoteResponse:
    """Create a new note belonging to the authenticated user."""
    note_id = note_in.id or str(uuid.uuid4())

    # Check if a note with this ID already exists for the user
    existing = db.query(Note).filter(Note.id == note_id, Note.user_id == current_user.id).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A note with this ID already exists.",
        )

    from sqlalchemy import func
    max_ver = (
        db.query(func.max(Note.version))
        .filter(Note.user_id == current_user.id)
        .scalar()
    ) or 0

    note = Note(
        id=note_id,
        user_id=current_user.id,
        title=note_in.title,
        content=note_in.content,
        project_id=note_in.project_id,
        is_pinned=note_in.is_pinned,
        is_archived=note_in.is_archived,
        client_updated_at=note_in.client_updated_at,
        version=max_ver + 1,
    )
    db.add(note)
    db.flush()

    for raw_tag in note_in.tags:
        clean = raw_tag.strip().lower()
        if clean:
            db.add(NoteTag(note_id=note.id, tag=clean))

    db.commit()
    db.refresh(note)
    return _format_note_response(note)


@router.get("/tags/all", response_model=list[str])
def list_user_tags(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> list[str]:
    """Retrieve all unique tags associated with the authenticated user's active notes."""
    tags = (
        db.query(NoteTag.tag)
        .distinct()
        .join(Note, Note.id == NoteTag.note_id)
        .filter(Note.user_id == current_user.id, Note.is_deleted.is_(False))
        .order_by(NoteTag.tag.asc())
        .all()
    )
    return [t[0] for t in tags]


@router.get("/projects/all", response_model=list[str])
def list_user_projects(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> list[str]:
    """Retrieve all unique project IDs associated with the authenticated user's active notes."""
    projects = (
        db.query(Note.project_id)
        .distinct()
        .filter(
            Note.user_id == current_user.id,
            Note.is_deleted.is_(False),
            Note.project_id.isnot(None),
            Note.project_id != "",
        )
        .order_by(Note.project_id.asc())
        .all()
    )
    return [p[0] for p in projects if p[0]]


@router.get("/{note_id}", response_model=NoteResponse)
def get_note(
    note_id: str,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> NoteResponse:
    """Get a specific note by ID, enforcing user ownership."""
    note = db.query(Note).filter(Note.id == note_id, Note.user_id == current_user.id).first()
    if not note or note.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")
    return _format_note_response(note)


@router.put("/{note_id}", response_model=NoteResponse)
def update_note(
    note_id: str,
    note_in: NoteUpdate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> NoteResponse:
    """Update a specific note by ID, enforcing user ownership."""
    note = db.query(Note).filter(Note.id == note_id, Note.user_id == current_user.id).first()
    if not note or note.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")

    if note_in.title is not None:
        note.title = note_in.title
    if note_in.content is not None:
        note.content = note_in.content
    if note_in.project_id is not None:
        note.project_id = note_in.project_id
    if note_in.is_pinned is not None:
        note.is_pinned = note_in.is_pinned
    if note_in.is_archived is not None:
        note.is_archived = note_in.is_archived
    if note_in.is_deleted is not None:
        note.is_deleted = note_in.is_deleted

    if note_in.tags is not None:
        # Replace tags
        db.query(NoteTag).filter(NoteTag.note_id == note.id).delete()
        for raw_tag in note_in.tags:
            clean = raw_tag.strip().lower()
            if clean:
                db.add(NoteTag(note_id=note.id, tag=clean))

    note.version += 1
    db.commit()
    db.refresh(note)
    return _format_note_response(note)


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(
    note_id: str,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> None:
    """Soft-delete a note, enforcing user ownership."""
    note = db.query(Note).filter(Note.id == note_id, Note.user_id == current_user.id).first()
    if not note:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")

    note.is_deleted = True
    note.version += 1
    db.commit()
