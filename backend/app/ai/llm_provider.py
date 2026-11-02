import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any


@dataclass
class Citation:
    note_id: str
    note_title: str
    excerpt: str
    similarity: float


@dataclass
class GroundedAnswerResult:
    answer: str
    has_sufficient_evidence: bool
    citations: list[Citation] = field(default_factory=list)
    latency_ms: float = 0.0
    model_name: str = "pocketbrain-grounded-v1"
    tokens_used: int = 0


class LLMProvider(ABC):
    @abstractmethod
    def generate_grounded_answer(
        self,
        query: str,
        retrieved_notes: list[dict[str, Any]],
        similarity_threshold: float = 0.35,
    ) -> GroundedAnswerResult:
        pass


class GroundedLocalLLMProvider(LLMProvider):
    """
    Deterministic, source-grounded personal memory synthesizer.
    Guarantees:
    1. Returns 'insufficient evidence' if no retrieved notes exceed similarity_threshold.
    2. Answers are strictly grounded in retrieved note text.
    3. Never hallucinates ungrounded facts or personal memories.
    4. Cites original note titles and excerpts with relevance scores.
    5. Treats retrieved notes as untrusted data.
    """

    def generate_grounded_answer(
        self,
        query: str,
        retrieved_notes: list[dict[str, Any]],
        similarity_threshold: float = 0.25,
    ) -> GroundedAnswerResult:
        start_time = time.perf_counter()

        # Filter notes that pass the relevance bar
        qualified_notes = [
            n for n in retrieved_notes if n.get("similarity", 0.0) >= similarity_threshold
        ]

        # Case 1: Insufficient Evidence
        if not qualified_notes:
            elapsed = (time.perf_counter() - start_time) * 1000
            return GroundedAnswerResult(
                answer="Insufficient information in your saved notes to answer this question. Please ensure your notes contain relevant details or try a different question.",
                has_sufficient_evidence=False,
                citations=[],
                latency_ms=round(elapsed, 2),
                model_name="pocketbrain-grounded-v1",
                tokens_used=len(query.split()),
            )

        # Case 2: Sufficient Evidence - Synthesize source-grounded response
        citations: list[Citation] = []
        answer_parts: list[str] = []

        query_tokens = set(query.lower().split())

        for note in qualified_notes:
            note_id = note["note_id"]
            title = note["title"]
            content = note["content"]
            sim = note["similarity"]

            # Extract most relevant sentence/excerpt for citation
            sentences = [s.strip() for s in content.replace("\n", ". ").split(".") if s.strip()]
            best_sentence = ""
            best_overlap = -1

            for s in sentences:
                s_tokens = set(s.lower().split())
                overlap = len(query_tokens.intersection(s_tokens))
                if overlap > best_overlap:
                    best_overlap = overlap
                    best_sentence = s

            excerpt = best_sentence if best_sentence else (content[:150] + ("..." if len(content) > 150 else ""))

            citations.append(
                Citation(
                    note_id=note_id,
                    note_title=title,
                    excerpt=excerpt,
                    similarity=round(sim, 3),
                )
            )

            answer_parts.append(f"According to your note '{title}': {excerpt}")

        synthesized_answer = "\n\n".join(answer_parts)
        elapsed = (time.perf_counter() - start_time) * 1000
        approx_tokens = len(query.split()) + sum(len(n['content'].split()) for n in qualified_notes)

        return GroundedAnswerResult(
            answer=synthesized_answer,
            has_sufficient_evidence=True,
            citations=citations,
            latency_ms=round(elapsed, 2),
            model_name="pocketbrain-grounded-v1",
            tokens_used=approx_tokens,
        )


def get_llm_provider() -> LLMProvider:
    return GroundedLocalLLMProvider()
