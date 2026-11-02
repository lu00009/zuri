import hashlib
import json
from sqlalchemy.orm import Session
from app.ai.embedding_provider import compute_cosine_similarity, get_embedding_provider
from app.ai.llm_provider import get_llm_provider
from app.models.embedding import NoteEmbedding
from app.models.note import Note
from app.schemas.ai import AiAskResponse, CitationItem, SemanticSearchResultItem


class RetrievalService:
    def __init__(self):
        self.embedding_provider = get_embedding_provider()
        self.llm_provider = get_llm_provider()

    @staticmethod
    def _compute_hash(title: str, content: str) -> str:
        data = f"{title}:{content}".encode("utf-8")
        return hashlib.sha256(data).hexdigest()

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
            sim = compute_cosine_similarity(query_vec, note_vec)
            tags = [t.tag for t in note.tags] if note.tags else []

            scored_notes.append({
                "note_id": note.id,
                "title": note.title,
                "content": note.content,
                "project_id": note.project_id,
                "tags": tags,
                "similarity": sim,
            })

        scored_notes.sort(key=lambda x: x["similarity"], reverse=True)
        return scored_notes[:top_k]

    def ask(
        self,
        db: Session,
        user_id: str,
        query: str,
        top_k: int = 3,
        similarity_threshold: float = 0.25,
    ) -> AiAskResponse:
        """
        Executes grounded retrieval and synthesizes an answer with source citations.
        """
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


retrieval_service = RetrievalService()
