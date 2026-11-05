from datetime import datetime
from pydantic import BaseModel, Field


class CitationItem(BaseModel):
    note_id: str
    note_title: str
    excerpt: str
    similarity: float


class AiAskRequest(BaseModel):
    query: str = Field(..., min_length=2, description="Question or memory query")
    top_k: int = Field(default=5, ge=1, le=10)
    similarity_threshold: float = Field(default=0.20, ge=0.0, le=1.0)


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


# --- 1. Conversational Memory Schemas ---

class ConversationCreateRequest(BaseModel):
    title: str | None = Field(default=None, max_length=255)


class ConversationUpdateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)


class ConversationMessageResponse(BaseModel):
    id: str
    conversation_id: str
    role: str
    content: str
    citations: list[CitationItem] = Field(default_factory=list)
    has_sufficient_evidence: bool = True
    created_at: datetime


class ConversationSummaryResponse(BaseModel):
    id: str
    user_id: str
    title: str
    message_count: int = 0
    last_message_preview: str | None = None
    created_at: datetime
    updated_at: datetime


class ConversationDetailResponse(BaseModel):
    id: str
    user_id: str
    title: str
    created_at: datetime
    updated_at: datetime
    messages: list[ConversationMessageResponse] = Field(default_factory=list)


class ConversationMessageCreateRequest(BaseModel):
    query: str = Field(..., min_length=1, description="User follow-up or query")
    top_k: int = Field(default=5, ge=1, le=10)
    similarity_threshold: float = Field(default=0.20, ge=0.0, le=1.0)


class ConversationMessageCreateResponse(BaseModel):
    user_message: ConversationMessageResponse
    assistant_message: ConversationMessageResponse


# --- 2. Related Memories Schemas ---

class RelatedMemoryItem(BaseModel):
    note_id: str
    title: str
    excerpt: str
    similarity: float
    project_id: str | None = None
    tags: list[str] = Field(default_factory=list)
    shared_tags: list[str] = Field(default_factory=list)
    explanation: str


class RelatedMemoriesResponse(BaseModel):
    note_id: str
    note_title: str
    related: list[RelatedMemoryItem] = Field(default_factory=list)


# --- 3. Memory Recap Schemas ---

class MemoryRecapRequest(BaseModel):
    period: str = Field(default="weekly", description="'today', 'weekly', 'monthly', or 'custom'")
    start_date: datetime | None = None
    end_date: datetime | None = None


class RecapCategoryHighlight(BaseModel):
    note_id: str
    note_title: str
    summary: str
    tags: list[str] = Field(default_factory=list)
    updated_at: datetime


class RecapCategorySection(BaseModel):
    category: str
    description: str
    highlights: list[RecapCategoryHighlight] = Field(default_factory=list)


class MemoryRecapResponse(BaseModel):
    period: str
    start_date: datetime
    end_date: datetime
    total_notes: int
    overview: str
    categories: list[RecapCategorySection] = Field(default_factory=list)
    important_decisions: list[str] = Field(default_factory=list)
    recurring_topics: list[str] = Field(default_factory=list)
    unfinished_ideas: list[str] = Field(default_factory=list)
