from __future__ import annotations

import json
from datetime import datetime
from typing import Annotated, Any
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from app.ai.retrieval_service import retrieval_service
from app.api.deps import get_current_user, get_db
from app.models.conversation import Conversation, ConversationMessage
from app.models.note import Note
from app.models.user import User
from app.schemas.ai import (
    AiAskRequest,
    AiAskResponse,
    CitationItem,
    ConversationCreateRequest,
    ConversationDetailResponse,
    ConversationMessageCreateRequest,
    ConversationMessageCreateResponse,
    ConversationMessageResponse,
    ConversationSummaryResponse,
    ConversationUpdateRequest,
    MemoryRecapRequest,
    MemoryRecapResponse,
    RelatedMemoriesResponse,
    SemanticSearchResponse,
    SemanticSearchResultItem,
)

router = APIRouter()


# ---------------------------------------------------------------------------
# 1. Ask Across Memories (Standard & Multi-Note RAG)
# ---------------------------------------------------------------------------

@router.post("/ask", response_model=AiAskResponse)
def ask_personal_memory(
    request: AiAskRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> AiAskResponse:
    """
    Ask questions across your private knowledge repository.
    Supports multi-note synthesis, comparisons, and contradiction detection.
    """
    return retrieval_service.ask(
        db=db,
        user_id=current_user.id,
        query=request.query,
        top_k=request.top_k,
        similarity_threshold=request.similarity_threshold,
    )


@router.get("/semantic-search", response_model=SemanticSearchResponse)
def semantic_search(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    query: str = Query(..., min_length=2, description="Semantic search query"),
    top_k: int = Query(default=5, ge=1, le=20),
) -> SemanticSearchResponse:
    """
    Retrieve user notes ranked by semantic vector similarity.
    """
    scored = retrieval_service.search_similar(
        db=db,
        user_id=current_user.id,
        query=query,
        top_k=top_k,
    )

    items = [
        SemanticSearchResultItem(
            note_id=n["note_id"],
            title=n["title"],
            content=n["content"],
            project_id=n["project_id"],
            tags=n["tags"],
            similarity=round(n["similarity"], 3),
        )
        for n in scored
    ]

    return SemanticSearchResponse(results=items)


@router.post("/reindex", status_code=status.HTTP_200_OK)
def trigger_reindex(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> dict[str, Any]:
    """
    Force reindexing of missing or stale embeddings for current user.
    """
    count = retrieval_service.sync_user_embeddings(db, current_user.id)
    return {"status": "ok", "indexed_or_updated": count}


# ---------------------------------------------------------------------------
# 2. Conversational Memory (Persistent Sessions, Follow-ups, Context Resolution)
# ---------------------------------------------------------------------------

@router.post(
    "/conversations",
    response_model=ConversationDetailResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_conversation(
    request: ConversationCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ConversationDetailResponse:
    """
    Create a new persistent conversation session for the authenticated user.
    """
    title = (request.title or "New Conversation").strip()
    conv = Conversation(
        user_id=current_user.id,
        title=title,
    )
    db.add(conv)
    db.commit()
    db.refresh(conv)

    return ConversationDetailResponse(
        id=conv.id,
        user_id=conv.user_id,
        title=conv.title,
        created_at=conv.created_at,
        updated_at=conv.updated_at,
        messages=[],
    )


@router.get("/conversations", response_model=list[ConversationSummaryResponse])
def list_conversations(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    limit: int = Query(default=30, ge=1, le=100),
) -> list[ConversationSummaryResponse]:
    """
    List all conversations belonging to the authenticated user ordered by recent activity.
    """
    convs = (
        db.query(Conversation)
        .filter(Conversation.user_id == current_user.id)
        .order_by(Conversation.updated_at.desc())
        .limit(limit)
        .all()
    )

    results = []
    for c in convs:
        last_msg = (
            db.query(ConversationMessage)
            .filter(ConversationMessage.conversation_id == c.id)
            .order_by(ConversationMessage.created_at.desc())
            .first()
        )
        msg_count = (
            db.query(ConversationMessage)
            .filter(ConversationMessage.conversation_id == c.id)
            .count()
        )

        preview = None
        if last_msg:
            preview = last_msg.content[:80] + ("..." if len(last_msg.content) > 80 else "")

        results.append(
            ConversationSummaryResponse(
                id=c.id,
                user_id=c.user_id,
                title=c.title,
                message_count=msg_count,
                last_message_preview=preview,
                created_at=c.created_at,
                updated_at=c.updated_at,
            )
        )

    return results


@router.get("/conversations/{conversation_id}", response_model=ConversationDetailResponse)
def get_conversation(
    conversation_id: str,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ConversationDetailResponse:
    """
    Get full conversation history by ID. Enforces strict multi-tenant ownership.
    """
    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id, Conversation.user_id == current_user.id)
        .first()
    )
    if not conv:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    messages = (
        db.query(ConversationMessage)
        .filter(ConversationMessage.conversation_id == conv.id)
        .order_by(ConversationMessage.created_at.asc())
        .all()
    )

    msg_responses = []
    for m in messages:
        citations = []
        if m.citations_json:
            try:
                raw_citations = json.loads(m.citations_json)
                citations = [CitationItem(**c) for c in raw_citations]
            except Exception:
                citations = []

        msg_responses.append(
            ConversationMessageResponse(
                id=m.id,
                conversation_id=m.conversation_id,
                role=m.role,
                content=m.content,
                citations=citations,
                has_sufficient_evidence=m.has_sufficient_evidence,
                created_at=m.created_at,
            )
        )

    return ConversationDetailResponse(
        id=conv.id,
        user_id=conv.user_id,
        title=conv.title,
        created_at=conv.created_at,
        updated_at=conv.updated_at,
        messages=msg_responses,
    )


@router.patch("/conversations/{conversation_id}", response_model=ConversationSummaryResponse)
def rename_conversation(
    conversation_id: str,
    request: ConversationUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ConversationSummaryResponse:
    """
    Rename an existing conversation title.
    """
    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id, Conversation.user_id == current_user.id)
        .first()
    )
    if not conv:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    conv.title = request.title.strip()
    db.commit()
    db.refresh(conv)

    msg_count = (
        db.query(ConversationMessage)
        .filter(ConversationMessage.conversation_id == conv.id)
        .count()
    )

    return ConversationSummaryResponse(
        id=conv.id,
        user_id=conv.user_id,
        title=conv.title,
        message_count=msg_count,
        created_at=conv.created_at,
        updated_at=conv.updated_at,
    )


@router.delete("/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_conversation(
    conversation_id: str,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """
    Delete a conversation and all its messages.
    """
    conv = (
        db.query(Conversation)
        .filter(Conversation.id == conversation_id, Conversation.user_id == current_user.id)
        .first()
    )
    if not conv:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    db.delete(conv)
    db.commit()
    return None


@router.post(
    "/conversations/{conversation_id}/messages",
    response_model=ConversationMessageCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
def send_conversation_message(
    conversation_id: str,
    request: ConversationMessageCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ConversationMessageCreateResponse:
    """
    Send a message within an ongoing conversation.
    Resolves pronouns and follow-up context against conversation history.
    Stores and returns both the user message and grounded assistant reply.
    """
    try:
        return retrieval_service.ask_in_conversation(
            db=db,
            user_id=current_user.id,
            conversation_id=conversation_id,
            query=request.query,
            top_k=request.top_k,
            similarity_threshold=request.similarity_threshold,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e),
        )


# ---------------------------------------------------------------------------
# 3. Related Memories
# ---------------------------------------------------------------------------

@router.get("/notes/{note_id}/related", response_model=RelatedMemoriesResponse)
def get_related_notes(
    note_id: str,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    limit: int = Query(default=5, ge=1, le=10),
    min_similarity: float = Query(default=0.15, ge=0.0, le=1.0),
) -> RelatedMemoriesResponse:
    """
    Discover semantically related notes with explanations and shared tags.
    """
    note = (
        db.query(Note)
        .filter(Note.id == note_id, Note.user_id == current_user.id, Note.is_deleted.is_(False))
        .first()
    )
    if not note:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Note not found",
        )

    return retrieval_service.get_related_memories(
        db=db,
        user_id=current_user.id,
        note_id=note_id,
        limit=limit,
        min_similarity=min_similarity,
    )


# ---------------------------------------------------------------------------
# 4. Memory Recap
# ---------------------------------------------------------------------------

@router.get("/recap", response_model=MemoryRecapResponse)
def get_memory_recap(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    period: str = Query(default="weekly", description="'today', 'weekly', 'monthly', or 'custom'"),
    start_date: str | None = Query(default=None),
    end_date: str | None = Query(default=None),
) -> MemoryRecapResponse:
    """
    Generate an AI memory recap categorized into Projects, Learning, Decisions, Ideas, and Personal Notes.
    """
    parsed_start = None
    parsed_end = None
    if start_date:
        try:
            parsed_start = datetime.fromisoformat(start_date.replace(" ", "+"))
        except Exception:
            pass
    if end_date:
        try:
            parsed_end = datetime.fromisoformat(end_date.replace(" ", "+"))
        except Exception:
            pass

    return retrieval_service.generate_memory_recap(
        db=db,
        user_id=current_user.id,
        period=period,
        start_date=parsed_start,
        end_date=parsed_end,
    )


@router.post("/recap", response_model=MemoryRecapResponse)
def post_memory_recap(
    request: MemoryRecapRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> MemoryRecapResponse:
    """
    POST variant for custom date-range memory recaps.
    """
    return retrieval_service.generate_memory_recap(
        db=db,
        user_id=current_user.id,
        period=request.period,
        start_date=request.start_date,
        end_date=request.end_date,
    )
