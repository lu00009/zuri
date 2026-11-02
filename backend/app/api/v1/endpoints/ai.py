from typing import Annotated, Any
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session
from app.ai.retrieval_service import retrieval_service
from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.ai import (
    AiAskRequest,
    AiAskResponse,
    SemanticSearchResponse,
    SemanticSearchResultItem,
)

router = APIRouter()


@router.post("/ask", response_model=AiAskResponse)
def ask_personal_memory(
    request: AiAskRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> AiAskResponse:
    """
    Ask a question grounded strictly in the authenticated user's private notes.
    Returns source citations with exact excerpts and similarity scores.
    Indicates insufficient evidence if no relevant notes are found.
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
