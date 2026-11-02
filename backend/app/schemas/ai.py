from pydantic import BaseModel, Field


class CitationItem(BaseModel):
    note_id: str
    note_title: str
    excerpt: str
    similarity: float


class AiAskRequest(BaseModel):
    query: str = Field(..., min_length=2, description="Question or memory query")
    top_k: int = Field(default=3, ge=1, le=10)
    similarity_threshold: float = Field(default=0.25, ge=0.0, le=1.0)


class AiAskResponse(BaseModel):
    answer: str
    has_sufficient_evidence: bool
    citations: list[CitationItem] = Field(default_factory=list)
    latency_ms: float
    model_name: str
    tokens_used: int


class SemanticSearchResultItem(BaseModel):
    note_id: str
    title: str
    content: str
    project_id: str | None = None
    tags: list[str] = Field(default_factory=list)
    similarity: float


class SemanticSearchResponse(BaseModel):
    results: list[SemanticSearchResultItem]
