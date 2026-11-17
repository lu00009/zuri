from __future__ import annotations

import hashlib
import json
import re
import uuid
from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session
from app.ai.embedding_provider import compute_cosine_similarity, get_embedding_provider
from app.ai.llm_provider import get_llm_provider
from app.models.conversation import Conversation, ConversationMessage
from app.models.embedding import NoteEmbedding
from app.models.note import Note
from app.schemas.ai import (
    AiAskResponse,
    CitationItem,
    ConversationMessageCreateResponse,
    ConversationMessageResponse,
    MemoryRecapResponse,
    RecapCategoryHighlight,
    RecapCategorySection,
    RelatedMemoriesResponse,
    RelatedMemoryItem,
    SemanticSearchResultItem,
)


class RetrievalService:
    def __init__(self):
        self.embedding_provider = get_embedding_provider()
        self.llm_provider = get_llm_provider()

    @staticmethod
    def _compute_hash(title: str, content: str) -> str:
        data = f"{title}:{content}".encode("utf-8")
        return hashlib.sha256(data).hexdigest()

    @staticmethod
    def _compute_keyword_overlap(query: str, title: str, content: str, tags: list[str]) -> float:
        stopwords = {
            "what", "is", "the", "for", "with", "was", "a", "an", "in", "to", "of",
            "and", "or", "on", "at", "by", "it", "this", "that", "which", "are", "be",
            "did", "do", "does", "how", "when", "where", "who", "why", "i", "my", "me",
            "we", "our", "you", "your", "can", "could", "would", "should", "have", "had",
            "has", "been", "about"
        }
        q_words = [w for w in re.findall(r"\b\w+\b", query.lower()) if w not in stopwords]
        if not q_words:
            return 0.0

        title_lower = title.lower()
        content_lower = content.lower()
        tag_set = set(t.lower() for t in tags)

        score = 0.0
        for w in q_words:
            if w in tag_set:
                score += 2.0
            if re.search(r"\b" + re.escape(w) + r"\b", title_lower):
                score += 2.5
            elif re.search(r"\b" + re.escape(w) + r"\b", content_lower):
                score += 1.0

        max_possible = len(q_words) * 2.5
        return min(1.0, score / max_possible) if max_possible > 0 else 0.0

    def sync_user_embeddings(self, db: Session, user_id: str) -> int:
        """
        Synchronizes embeddings for all active notes belonging to user_id.
        Detects stale embeddings via content hash and updates only what changed.
        """
        active_notes = (
            db.query(Note)
            .filter(Note.user_id == user_id, Note.is_deleted.is_(False))
            .all()
        )

        existing_embeddings = {
            emb.note_id: emb
            for emb in db.query(NoteEmbedding).filter(NoteEmbedding.user_id == user_id).all()
        }

        updated_count = 0
        active_ids = set()

        for note in active_notes:
            active_ids.add(note.id)
            current_hash = self._compute_hash(note.title, note.content)
            existing = existing_embeddings.get(note.id)

            # Check if embedding missing or stale
            if not existing or existing.content_hash != current_hash:
                text_to_embed = f"{note.title}\n{note.content}"
                vector = self.embedding_provider.embed_query(text_to_embed)
                vec_json = json.dumps(vector)

                if existing:
                    existing.embedding_json = vec_json
                    existing.content_hash = current_hash
                else:
                    new_emb = NoteEmbedding(
                        note_id=note.id,
                        user_id=user_id,
                        embedding_json=vec_json,
                        content_hash=current_hash,
                    )
                    db.add(new_emb)
                updated_count += 1

        # Clean up embeddings for deleted notes
        for note_id, emb in existing_embeddings.items():
            if note_id not in active_ids:
                db.delete(emb)

        if updated_count > 0:
            db.commit()

        return updated_count

    def search_similar(
        self,
        db: Session,
        user_id: str,
        query: str,
        top_k: int = 5,
    ) -> list[dict]:
        """
        Retrieves top_k notes strictly belonging to user_id ranked by semantic cosine similarity.
        """
        # Ensure user's embeddings are up-to-date
        self.sync_user_embeddings(db, user_id)

        query_vec = self.embedding_provider.embed_query(query)

        embeddings = (
            db.query(NoteEmbedding, Note)
            .join(Note, Note.id == NoteEmbedding.note_id)
            .filter(
                NoteEmbedding.user_id == user_id,
                Note.user_id == user_id,
                Note.is_deleted.is_(False),
            )
            .all()
        )

        scored_notes = []
        for emb, note in embeddings:
            note_vec = json.loads(emb.embedding_json)
            sem_sim = compute_cosine_similarity(query_vec, note_vec)
            tags = [t.tag for t in note.tags] if note.tags else []
            kw_sim = self._compute_keyword_overlap(query, note.title, note.content, tags)
            hybrid_sim = round(0.60 * sem_sim + 0.40 * kw_sim, 3)

            scored_notes.append({
                "note_id": note.id,
                "title": note.title,
                "content": note.content,
                "project_id": note.project_id,
                "tags": tags,
                "similarity": hybrid_sim,
                "updated_at": note.updated_at,
            })

        scored_notes.sort(key=lambda x: x["similarity"], reverse=True)
        return scored_notes[:top_k]

    def ask(
        self,
        db: Session,
        user_id: str,
        query: str,
        top_k: int = 5,
        similarity_threshold: float = 0.20,
    ) -> AiAskResponse:
        """
        Executes grounded retrieval and synthesizes an answer with source citations.
        Supports cross-memory querying, comparison, and change detection.
        Separates conversational intent (greetings/chit-chat) so they never trigger note search.
        """
        # Conversational & Agent check: Greetings, writing, scheduling, and generative agent tasks
        conversational_reply = self.llm_provider._detect_conversational_intent(query)
        agent_reply = conversational_reply or self.llm_provider._detect_agent_intent(query)
        if agent_reply:
            return AiAskResponse(
                answer=agent_reply,
                has_sufficient_evidence=True,
                citations=[],
                latency_ms=1.0,
                model_name="zuri-agent-v1",
                tokens_used=len(agent_reply.split()),
            )

        retrieved = self.search_similar(db, user_id, query, top_k=top_k)
        result = self.llm_provider.generate_grounded_answer(
            query=query,
            retrieved_notes=retrieved,
            similarity_threshold=similarity_threshold,
        )

        return AiAskResponse(
            answer=result.answer,
            has_sufficient_evidence=result.has_sufficient_evidence,
            citations=[
                CitationItem(
                    note_id=c.note_id,
                    note_title=c.note_title,
                    excerpt=c.excerpt,
                    similarity=c.similarity,
                )
                for c in result.citations
            ],
            latency_ms=result.latency_ms,
            model_name=result.model_name,
            tokens_used=result.tokens_used,
        )

    def get_related_memories(
        self,
        db: Session,
        user_id: str,
        note_id: str,
        limit: int = 5,
        min_similarity: float = 0.15,
    ) -> RelatedMemoriesResponse:
        """
        Discovers semantically related notes for a given note_id belonging to user_id.
        Computes relevance explanation, shared tags, and similarity scores.
        """
        # Ensure user ownership and note existence
        target_note = (
            db.query(Note)
            .filter(Note.id == note_id, Note.user_id == user_id, Note.is_deleted.is_(False))
            .first()
        )
        if not target_note:
            return RelatedMemoriesResponse(note_id=note_id, note_title="Unknown", related=[])

        self.sync_user_embeddings(db, user_id)

        target_emb_record = db.query(NoteEmbedding).filter(NoteEmbedding.note_id == note_id).first()
        if not target_emb_record:
            return RelatedMemoriesResponse(note_id=note_id, note_title=target_note.title, related=[])

        target_vec = json.loads(target_emb_record.embedding_json)
        target_tags = set(t.tag for t in target_note.tags) if target_note.tags else set()
        target_dict = {
            "title": target_note.title,
            "content": target_note.content,
            "project_id": target_note.project_id,
        }

        candidate_embeddings = (
            db.query(NoteEmbedding, Note)
            .join(Note, Note.id == NoteEmbedding.note_id)
            .filter(
                NoteEmbedding.user_id == user_id,
                Note.user_id == user_id,
                Note.id != note_id,
                Note.is_deleted.is_(False),
            )
            .all()
        )

        scored: list[RelatedMemoryItem] = []
        for emb, note in candidate_embeddings:
            candidate_vec = json.loads(emb.embedding_json)
            sim = compute_cosine_similarity(target_vec, candidate_vec)

            cand_tags = [t.tag for t in note.tags] if note.tags else []
            shared = list(target_tags.intersection(set(cand_tags)))

            # If shared project, slight boost
            if target_note.project_id and target_note.project_id == note.project_id:
                sim = min(1.0, sim + 0.05)

            if sim >= min_similarity:
                cand_dict = {
                    "title": note.title,
                    "content": note.content,
                    "project_id": note.project_id,
                }
                explanation = self.llm_provider.generate_related_explanation(
                    target_note=target_dict,
                    candidate_note=cand_dict,
                    similarity=sim,
                    shared_tags=shared,
                )

                excerpt = note.content[:140] + ("..." if len(note.content) > 140 else "")
                scored.append(
                    RelatedMemoryItem(
                        note_id=note.id,
                        title=note.title,
                        excerpt=excerpt,
                        similarity=round(sim, 3),
                        project_id=note.project_id,
                        tags=cand_tags,
                        shared_tags=shared,
                        explanation=explanation,
                    )
                )

        scored.sort(key=lambda x: x.similarity, reverse=True)
        return RelatedMemoriesResponse(
            note_id=target_note.id,
            note_title=target_note.title,
            related=scored[:limit],
        )

    def generate_memory_recap(
        self,
        db: Session,
        user_id: str,
        period: str = "weekly",
        start_date: datetime | None = None,
        end_date: datetime | None = None,
    ) -> MemoryRecapResponse:
        """
        Summarizes memories created or modified during the selected timeframe.
        Categorizes into Projects, Learning, Decisions, Ideas, Personal Notes.
        """
        now = datetime.now(timezone.utc)
        normalized_period = period.lower().strip()

        if normalized_period == "today":
            start = now - timedelta(days=1)
            end = now
        elif normalized_period == "monthly":
            start = now - timedelta(days=30)
            end = now
        elif normalized_period == "custom" and start_date and end_date:
            start = start_date
            end = end_date
        else:
            # Default weekly
            normalized_period = "weekly"
            start = now - timedelta(days=7)
            end = now

        # Query user notes in range
        notes = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.is_deleted.is_(False),
                (Note.updated_at >= start) | (Note.created_at >= start),
            )
            .order_by(Note.updated_at.desc())
            .all()
        )

        notes_data = [
            {
                "id": n.id,
                "title": n.title,
                "content": n.content,
                "project_id": n.project_id,
                "tags": [t.tag for t in n.tags] if n.tags else [],
                "updated_at": n.updated_at,
            }
            for n in notes
        ]

        if not notes_data:
            return MemoryRecapResponse(
                period=normalized_period,
                start_date=start,
                end_date=end,
                total_notes=0,
                overview=f"No notes were recorded or updated during this {normalized_period} period.",
                categories=[],
                important_decisions=[],
                recurring_topics=[],
                unfinished_ideas=[],
            )

        raw_recap = self.llm_provider.generate_recap(
            notes=notes_data,
            period=normalized_period,
            start_date=start,
            end_date=end,
        )

        categories_models = [
            RecapCategorySection(
                category=cat["category"],
                description=cat["description"],
                highlights=[
                    RecapCategoryHighlight(
                        note_id=h["note_id"],
                        note_title=h["note_title"],
                        summary=h["summary"],
                        tags=h["tags"],
                        updated_at=h["updated_at"],
                    )
                    for h in cat["highlights"]
                ],
            )
            for cat in raw_recap["categories"]
        ]

        return MemoryRecapResponse(
            period=normalized_period,
            start_date=start,
            end_date=end,
            total_notes=raw_recap["total_notes"],
            overview=raw_recap["overview"],
            categories=categories_models,
            important_decisions=raw_recap["important_decisions"],
            recurring_topics=raw_recap["recurring_topics"],
            unfinished_ideas=raw_recap["unfinished_ideas"],
        )

    @staticmethod
    def _is_approval_intent(query: str) -> bool:
        q_clean = re.sub(r"[^\w\s]", " ", query.lower())
        q_clean = re.sub(r"\s+", " ", q_clean).strip()
        approval_words = {
            "approve", "approved", "approve it", "yes", "yes please",
            "save", "save it", "save this", "save note", "save to notes",
            "write it to my notes", "add to notes", "add it to notes",
            "yes save it", "yes please save it", "yes save this",
            "confirm", "confirmed", "please save", "please save it",
            "okay save it", "ok save it"
        }
        if q_clean in approval_words:
            return True
        if re.search(r"\b(approve|save\s+(this|it|to\s+notes?)|add\s+to\s+notes?)\b", q_clean):
            if not re.search(r"\b(did\s+i|what\s+did|search|find|check)\b", q_clean):
                return True
        return False

    @staticmethod
    def _extract_note_draft(assistant_text: str) -> tuple[str, str]:
        title = "Personal Note"
        # Look for headers like 📅 **9:00 PM Schedule** or **Marketing Launch** or # Title
        title_match = re.search(r"(?:📅\s*|\#+\s*)?\*\*([^\*\n]+(?:Schedule|Routine|Agenda|Note|Plan|List|[A-Za-z0-9\s]+))\*\*", assistant_text)
        if title_match:
            cand = title_match.group(1).strip()
            if 3 < len(cand) < 60:
                title = cand
        elif re.search(r"^\#+\s+(.+)$", assistant_text, re.MULTILINE):
            title = re.search(r"^\#+\s+(.+)$", assistant_text, re.MULTILINE).group(1).strip()

        title = re.sub(r"^[📅📋📝\s]+", "", title).strip()
        if not title:
            title = "Personal Note"

        # Content cleaning: strip intro line and trailing approval question
        content = re.sub(r"^Here is (?:your|a) [^\n]+:\s*", "", assistant_text.strip(), flags=re.IGNORECASE)
        content = re.sub(
            r"\n*Would you like me to save this [^\n]*\?.*$",
            "",
            content,
            flags=re.IGNORECASE | re.DOTALL,
        ).strip()

        if not content:
            content = assistant_text.strip()

        return title, content

    def ask_in_conversation(
        self,
        db: Session,
        user_id: str,
        conversation_id: str,
        query: str,
        top_k: int = 5,
        similarity_threshold: float = 0.25,
    ) -> ConversationMessageCreateResponse:
        """
        Executes a conversational turn with reference resolution and persistent history.
        """
        conversation = (
            db.query(Conversation)
            .filter(Conversation.id == conversation_id, Conversation.user_id == user_id)
            .first()
        )
        if not conversation:
            raise ValueError("Conversation not found or access denied")

        # Get existing messages
        history_msgs = (
            db.query(ConversationMessage)
            .filter(ConversationMessage.conversation_id == conversation_id)
            .order_by(ConversationMessage.created_at.asc())
            .all()
        )
        history_list = [
            {"role": m.role, "content": m.content}
            for m in history_msgs
        ]

        # 0. Approval Flow: If user replies "approve", "yes", "save it", create and save Note in DB
        if self._is_approval_intent(query):
            last_assistant_msg = next((m["content"] for m in reversed(history_list) if m["role"] == "assistant"), None)
            if last_assistant_msg and ("approve" in last_assistant_msg.lower() or "save this" in last_assistant_msg.lower() or "schedule" in last_assistant_msg.lower() or "draft" in last_assistant_msg.lower()):
                title, content = self._extract_note_draft(last_assistant_msg)
                new_note = Note(
                    id=str(uuid.uuid4()),
                    user_id=user_id,
                    title=title,
                    content=content,
                    is_deleted=False,
                    created_at=datetime.now(timezone.utc),
                    updated_at=datetime.now(timezone.utc),
                )
                db.add(new_note)
                db.flush()
                self.sync_user_embeddings(db, user_id)

                reply_text = (
                    f"Approved! ✅ I have saved this to your notes under '**{title}**'. "
                    "You can view and edit it in your notes anytime."
                )
            else:
                reply_text = "I'm ready to save when you have a note or schedule drafted! Tell me what you'd like to write or schedule first."

            user_msg = ConversationMessage(
                conversation_id=conversation_id,
                user_id=user_id,
                role="user",
                content=query,
                citations_json=None,
                has_sufficient_evidence=True,
            )
            db.add(user_msg)
            db.flush()

            assistant_msg = ConversationMessage(
                conversation_id=conversation_id,
                user_id=user_id,
                role="assistant",
                content=reply_text,
                citations_json=None,
                has_sufficient_evidence=True,
            )
            db.add(assistant_msg)
            conversation.updated_at = datetime.utcnow()
            db.commit()
            db.refresh(user_msg)
            db.refresh(assistant_msg)

            return ConversationMessageCreateResponse(
                user_message=ConversationMessageResponse(
                    id=user_msg.id,
                    conversation_id=user_msg.conversation_id,
                    role=user_msg.role,
                    content=user_msg.content,
                    citations=[],
                    has_sufficient_evidence=True,
                    created_at=user_msg.created_at,
                ),
                assistant_message=ConversationMessageResponse(
                    id=assistant_msg.id,
                    conversation_id=assistant_msg.conversation_id,
                    role=assistant_msg.role,
                    content=assistant_msg.content,
                    citations=[],
                    has_sufficient_evidence=True,
                    created_at=assistant_msg.created_at,
                ),
            )

        # 1. Conversational & Agent intent check: Greetings, chit-chat, writing, scheduling, and generative agent tasks
        conversational_reply = self.llm_provider._detect_conversational_intent(query)
        agent_reply = conversational_reply or self.llm_provider._detect_agent_intent(query, history_list)
        if agent_reply:
            user_msg = ConversationMessage(
                conversation_id=conversation_id,
                user_id=user_id,
                role="user",
                content=query,
                citations_json=None,
                has_sufficient_evidence=True,
            )
            db.add(user_msg)
            db.flush()

            assistant_msg = ConversationMessage(
                conversation_id=conversation_id,
                user_id=user_id,
                role="assistant",
                content=agent_reply,
                citations_json=None,
                has_sufficient_evidence=True,
            )
            db.add(assistant_msg)
            conversation.updated_at = datetime.utcnow()
            db.commit()
            db.refresh(user_msg)
            db.refresh(assistant_msg)

            return ConversationMessageCreateResponse(
                user_message=ConversationMessageResponse(
                    id=user_msg.id,
                    conversation_id=user_msg.conversation_id,
                    role=user_msg.role,
                    content=user_msg.content,
                    citations=[],
                    has_sufficient_evidence=True,
                    created_at=user_msg.created_at,
                ),
                assistant_message=ConversationMessageResponse(
                    id=assistant_msg.id,
                    conversation_id=assistant_msg.conversation_id,
                    role=assistant_msg.role,
                    content=assistant_msg.content,
                    citations=[],
                    has_sufficient_evidence=True,
                    created_at=assistant_msg.created_at,
                ),
            )

        # 2. Resolve conversational references / pronouns
        resolved_query = self.llm_provider.resolve_query_context(query, history_list)

        # 2. Retrieve relevant notes using both resolved query and base query
        scored_resolved = self.search_similar(db, user_id, resolved_query, top_k=top_k)
        scored_base = self.search_similar(db, user_id, query, top_k=top_k) if resolved_query != query else []

        # Merge results without duplicates
        merged_notes_map = {}
        for n in scored_resolved + scored_base:
            if n["note_id"] not in merged_notes_map or n["similarity"] > merged_notes_map[n["note_id"]]["similarity"]:
                merged_notes_map[n["note_id"]] = n

        merged_notes = sorted(merged_notes_map.values(), key=lambda x: x["similarity"], reverse=True)[:top_k]

        # 3. Generate grounded answer
        answer_result = self.llm_provider.generate_grounded_answer(
            query=query,
            retrieved_notes=merged_notes,
            similarity_threshold=similarity_threshold,
            conversation_history=history_list,
        )

        citations_list = [
            CitationItem(
                note_id=c.note_id,
                note_title=c.note_title,
                excerpt=c.excerpt,
                similarity=c.similarity,
            )
            for c in answer_result.citations
        ]
        citations_json_str = json.dumps([c.model_dump() for c in citations_list]) if citations_list else None

        # 4. Save User Message
        user_msg = ConversationMessage(
            conversation_id=conversation_id,
            user_id=user_id,
            role="user",
            content=query,
            citations_json=None,
            has_sufficient_evidence=True,
        )
        db.add(user_msg)
        db.flush()

        # 5. Save Assistant Message
        assistant_msg = ConversationMessage(
            conversation_id=conversation_id,
            user_id=user_id,
            role="assistant",
            content=answer_result.answer,
            citations_json=citations_json_str,
            has_sufficient_evidence=answer_result.has_sufficient_evidence,
        )
        db.add(assistant_msg)

        # 6. Update conversation title if first message
        if conversation.title == "New Conversation" or not conversation.title:
            clean_title = query.strip()
            if len(clean_title) > 40:
                clean_title = clean_title[:37] + "..."
            conversation.title = clean_title

        conversation.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(user_msg)
        db.refresh(assistant_msg)

        return ConversationMessageCreateResponse(
            user_message=ConversationMessageResponse(
                id=user_msg.id,
                conversation_id=user_msg.conversation_id,
                role=user_msg.role,
                content=user_msg.content,
                citations=[],
                has_sufficient_evidence=True,
                created_at=user_msg.created_at,
            ),
            assistant_message=ConversationMessageResponse(
                id=assistant_msg.id,
                conversation_id=assistant_msg.conversation_id,
                role=assistant_msg.role,
                content=assistant_msg.content,
                citations=citations_list,
                has_sufficient_evidence=assistant_msg.has_sufficient_evidence,
                created_at=assistant_msg.created_at,
            ),
        )


retrieval_service = RetrievalService()
