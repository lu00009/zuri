from __future__ import annotations

import re
import time
from abc import ABC, abstractmethod
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
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
        similarity_threshold: float = 0.25,
        conversation_history: list[dict[str, str]] | None = None,
    ) -> GroundedAnswerResult:
        pass

    @abstractmethod
    def resolve_query_context(
        self,
        query: str,
        conversation_history: list[dict[str, str]],
    ) -> str:
        pass

    @abstractmethod
    def generate_related_explanation(
        self,
        target_note: dict[str, Any],
        candidate_note: dict[str, Any],
        similarity: float,
        shared_tags: list[str],
    ) -> str:
        pass

    @abstractmethod
    def generate_recap(
        self,
        notes: list[dict[str, Any]],
        period: str,
        start_date: datetime,
        end_date: datetime,
    ) -> dict[str, Any]:
        pass


class GroundedLocalLLMProvider(LLMProvider):
    """
    Deterministic, source-grounded personal memory synthesizer.
    Guarantees:
    1. Returns 'insufficient evidence' if no retrieved notes exceed similarity_threshold.
    2. Answers are strictly grounded in retrieved note text.
    3. Never hallucinates ungrounded facts or personal memories.
    4. Cites original note titles and excerpts with relevance scores.
    5. Detects contradiction, timeline changes, and comparisons across multiple notes.
    6. Resolves conversational pronouns and references using recent chat context.
    """

    STOP_ENTITIES = {
        "here", "according", "your", "note", "notes", "based", "additionally",
        "in", "i", "we", "the", "a", "an", "this", "that", "these", "those",
        "what", "why", "how", "when", "which", "is", "was", "are", "were"
    }

    def resolve_query_context(
        self,
        query: str,
        conversation_history: list[dict[str, str]],
    ) -> str:
        """
        Resolves pronouns ('it', 'that', 'the alternative', 'which database did we choose', 'why did I choose it')
        against previous conversational turns to build an effective retrieval query.
        """
        if not conversation_history:
            return query

        q_tokens = set(re.findall(r"\b\w+\b", query.lower()))
        referential_indicators = {
            "it", "that", "this", "them", "its", "they", "why", "which", "what",
            "alternative", "option", "previous", "former", "latter", "compare", "explain"
        }

        # Check if query contains any pronoun or referential marker
        if not q_tokens.intersection(referential_indicators) and len(q_tokens) >= 5:
            # Query is already detailed and standalone
            return query

        # Search recent history (up to last 6 messages) for quoted titles, technical nouns, and entities
        extracted_entities: list[str] = []
        for msg in reversed(conversation_history[-6:]):
            content = msg.get("content", "")
            # 1. Quoted note titles '...' or "..."
            quoted = re.findall(r"['\"]([^'\"]+)['\"]", content)
            for q in quoted:
                if len(q.split()) <= 6:
                    extracted_entities.append(q)

            # 2. Capitalized technical terms and acronyms (e.g. PostgreSQL, SQLite, Riverpod, AWS, GCP, FastAPI)
            tech_matches = re.findall(r"\b[A-Z][a-zA-Z0-9_\-\.]{2,}\b", content)
            for tm in tech_matches:
                if tm.lower() not in self.STOP_ENTITIES and tm not in extracted_entities:
                    extracted_entities.append(tm)

        if not extracted_entities:
            return query

        # Deduplicate while preserving order of recency
        unique_entities: list[str] = []
        seen = set()
        for e in extracted_entities:
            low = e.lower()
            if low not in seen:
                seen.add(low)
                unique_entities.append(e)

        context_boost = " ".join(unique_entities[:3])
        return f"{query} {context_boost}".strip()

    @staticmethod
    def _detect_conversational_intent(query: str) -> str | None:
        """
        Recognizes greetings, identity/capabilities inquiries, gratitude, and farewells.
        Returns a friendly natural response if matched, or None to fall back to note retrieval.
        Separates pure conversational intent from personal memory-search queries.
        """
        q = query.strip().lower()
        # Remove emojis and punctuation for clean token matching
        q_clean = re.sub(r"[^\w\s]", " ", q)
        q_clean = re.sub(r"\s+", " ", q_clean).strip()

        # If the user explicitly asks about saved notes, personal information, or specific knowledge,
        # it is NOT conversational chit-chat; it must be routed to memory retrieval.
        memory_seeking_pattern = (
            r"\b(save|saved|my\s+notes?|notes?\s+about|notes?\s+on|did\s+i|what\s+did\s+i|"
            r"what\s+do\s+i\s+have|my\s+projects?|my\s+ideas?|my\s+learnings?|my\s+meetings?|"
            r"remind\s+me|search\s+for|find\s+notes?|look\s+up|what\s+were\s+my|check\s+my)\b"
        )
        if re.search(memory_seeking_pattern, q_clean) and not re.search(r"\b(who\s+are\s+you|what\s+can\s+you\s+do)\b", q_clean):
            return None

        # 0. Emotional feedback, corrections, and criticisms
        if re.search(r"\b(liar|lying|you\s+lie|you\s+are\s+a\s+liar|youre\s+a\s+liar|fake)\b", q_clean):
            return "I'm sorry if I gave you an inaccurate or confusing response! I only aim to help you recall what you've saved. What can I look up or clarify for you?"
        if re.search(r"\b(wrong|incorrect|not\s+true|thats\s+wrong|you\s+are\s+wrong|youre\s+wrong)\b", q_clean):
            return "My apologies for the confusion! Let me know what information was incorrect or what you'd like me to look up in your notes."

        # 1. Farewells
        if re.search(
            r"\b(goodbye|bye|bye\s*bye|see\s*(you|ya|u)|farewell|talk\s*to\s*you\s*later|good\s*night|cya)\b",
            q_clean,
        ) and not re.search(r"\b(what|why|which|how|where|when)\b", q_clean):
            if "night" in q_clean:
                return "Good night! Rest well, and I'll be right here whenever you're ready to pick up your notes again."
            return "Goodbye! Have a great day ahead. Whenever you have a new thought or question, I'll be right here."

        # 2. Thank you / Gratitude
        if re.search(
            r"\b(thank\s*you|thanks|thank\s+you\s+so\s+much|thanks\s+a\s+lot|appreciate\s+it|thx)\b",
            q_clean,
        ) and not re.search(r"\b(what|why|which|how|where|when)\b", q_clean):
            return "You're very welcome! If there's anything else you'd like to check or remember, just let me know."

        # 3. How are you / Well-being
        if re.search(r"\b(how\s+are\s+you|how\s+are\s+you\s+doing|hows\s+it\s+going|how\s+do\s+you\s+do|hows\s+everything|how\s+is\s+it\s+going)\b", q_clean):
            return (
                "I'm doing great, thank you for asking! I'm ready to help you explore your notes and organize your thoughts. "
                "What would you like to work on today?"
            )

        # 4. Identity / Name
        if re.search(r"\b(who\s+are\s+you|what\s+is\s+your\s+name|what\s+are\s+you|tell\s+me\s+about\s+yourself|introduce\s+yourself|are\s+you\s+(an\s+)?ai)\b", q_clean):
            return (
                "I'm Zuri, your personal AI assistant and memory companion. "
                "I help you remember important ideas, organize your thoughts, find connections across your notes, "
                "and answer questions based on what you've saved. You can chat with me naturally anytime!"
            )

        # 5. Capabilities / What can you do / Help
        if re.search(r"\b(what\s+can\s+you\s+do|how\s+can\s+you\s+help|what\s+do\s+you\s+do|what\s+are\s+your\s+features|help\s+me|help)\b", q_clean):
            return (
                "Here is what I can do for you:\n"
                "• Answer questions based on your saved notes and memories\n"
                "• Remember conversation context across follow-up questions\n"
                "• Discover related memories and connect similar ideas\n"
                "• Summarize your weekly, monthly, or daily learnings and decisions\n"
                "• Chat with you naturally whenever you need assistance\n\n"
                "Feel free to ask me anything about your notes, or just chat!"
            )

        # 6. Greetings (e.g. "Say hello to Zuri", "hello", "hi", "hey", "good morning", "yo")
        greeting_match = re.search(
            r"\b(hello|hi|hey|howdy|greetings|good\s*(morning|afternoon|evening|day)|yo|sup|whats\s*up|wassup|greet|say\s+hello|say\s+hi)\b",
            q_clean,
        )
        if greeting_match:
            words = q_clean.split()
            has_question = bool(re.search(r"\b(what|which|where|when|why|who\s+did|how\s+to|how\s+do|how\s+did)\b", q_clean))
            # If it's a greeting phrase without an interrogative question, or a short greeting <= 8 words
            if not has_question or len(words) <= 8:
                if "morning" in q_clean:
                    return "Good morning! I'm Zuri, your personal AI assistant. How can I help you today?"
                elif "afternoon" in q_clean:
                    return "Good afternoon! I'm Zuri. How is your day going? Let me know if you need to recall or save anything."
                elif "evening" in q_clean:
                    return "Good evening! I'm Zuri. What would you like to review or brainstorm tonight?"
                return "Hello! I'm Zuri, your personal AI assistant. How can I help you today? You can ask me anything about your notes, or share what's on your mind."

        # 7. Casual acknowledgments
        if q_clean in {"ok", "okay", "cool", "great", "awesome", "nice", "got it", "sounds good", "understood"}:
            return "Sounds good! I'm here whenever you're ready to search your notes or save a new thought."

        return None

    def generate_grounded_answer(
        self,
        query: str,
        retrieved_notes: list[dict[str, Any]],
        similarity_threshold: float = 0.20,
        conversation_history: list[dict[str, str]] | None = None,
    ) -> GroundedAnswerResult:
        start_time = time.perf_counter()

        # Check for direct conversational intent first (greetings, identity, gratitude, farewells)
        conversational_reply = self._detect_conversational_intent(query)
        if conversational_reply:
            elapsed = (time.perf_counter() - start_time) * 1000
            return GroundedAnswerResult(
                answer=conversational_reply,
                has_sufficient_evidence=True,
                citations=[],
                latency_ms=round(elapsed, 2),
                model_name="zuri-conversational-v1",
                tokens_used=len(conversational_reply.split()),
            )

        # Filter notes that pass the relevance bar
        qualified_notes = [
            n for n in retrieved_notes if n.get("similarity", 0.0) >= similarity_threshold
        ]

        # Case 1: Insufficient Evidence
        if not qualified_notes:
            elapsed = (time.perf_counter() - start_time) * 1000
            return GroundedAnswerResult(
                answer=(
                    "There is insufficient information in your saved notes to answer this question. "
                    "Try saving a note with more details or ask about another topic!"
                ),
                has_sufficient_evidence=False,
                citations=[],
                latency_ms=round(elapsed, 2),
                model_name="pocketbrain-grounded-v1",
                tokens_used=len(query.split()),
            )

        # Case 2: Sufficient Evidence - Synthesize source-grounded response
        citations: list[Citation] = []
        answer_items: list[dict[str, Any]] = []

        query_tokens = set(re.findall(r"\b\w+\b", query.lower()))
        is_comparison = bool(re.search(r"\b(compare|versus|vs|difference|between|alternative)\b", query.lower()))
        is_change_query = bool(re.search(r"\b(change|changed|latest|rescheduled|updated|timeline|switch|evolve)\b", query.lower()))

        for note in qualified_notes:
            note_id = note["note_id"]
            title = note["title"]
            content = note["content"]
            sim = note["similarity"]
            updated_at = note.get("updated_at")

            # Extract most relevant sentence/excerpt for citation
            sentences = [
                s.strip()
                for s in re.split(r'(?<=[.!?])\s+', content.replace("\n", " "))
                if s.strip()
            ]
            best_sentence = ""
            best_overlap = -1

            for s in sentences:
                s_tokens = set(re.findall(r"\b\w+\b", s.lower()))
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

            answer_items.append({
                "note_id": note_id,
                "title": title,
                "content": content,
                "excerpt": excerpt,
                "similarity": sim,
                "updated_at": updated_at,
            })

        # Synthesize flowing answer paragraph
        # Check for contradiction / schedule change / revision across notes
        has_contradiction = False
        contradiction_pair = None

        if len(answer_items) >= 2:
            change_keywords = {"rescheduled", "revised", "instead of", "changed", "switched", "updated", "deprecated", "replaced"}
            for i in range(len(answer_items) - 1):
                item_a = answer_items[i]
                item_b = answer_items[i + 1]
                comb_text = f"{item_a['title']} {item_a['content']} {item_b['title']} {item_b['content']}".lower()
                if any(ck in comb_text for ck in change_keywords) or is_change_query:
                    has_contradiction = True
                    contradiction_pair = (item_a, item_b)
                    break

        if has_contradiction and contradiction_pair:
            first, second = contradiction_pair
            e1 = first["excerpt"].strip().rstrip(".")
            e2 = second["excerpt"].strip().rstrip(".")
            synthesized_answer = (
                f"Based on your notes, there was a change recorded over time: "
                f"In '{first['title']}', you recorded: \"{e1}\". "
                f"However, in '{second['title']}', you noted a revision: \"{e2}\"."
            )
        elif is_comparison and len(answer_items) >= 2:
            first = answer_items[0]
            second = answer_items[1]
            e1 = first["excerpt"].strip().rstrip(".")
            e2 = second["excerpt"].strip().rstrip(".")
            synthesized_answer = (
                f"Comparing your saved notes: In '{first['title']}', you noted that \"{e1}\". "
                f"In contrast, in '{second['title']}', you recorded: \"{e2}\"."
            )
        elif len(answer_items) == 1:
            item = answer_items[0]
            e = item["excerpt"].strip().rstrip(".")
            synthesized_answer = f"In your note on '{item['title']}', you recorded: \"{e}\"."
        elif len(answer_items) == 2:
            item1, item2 = answer_items[0], answer_items[1]
            e1 = item1["excerpt"].strip().rstrip(".")
            e2 = item2["excerpt"].strip().rstrip(".")
            synthesized_answer = (
                f"Based on your saved notes, in '{item1['title']}' you recorded: \"{e1}\". "
                f"Additionally, in '{item2['title']}', you noted: \"{e2}\"."
            )
        else:
            parts = []
            for i, item in enumerate(answer_items[:4]):
                clean = item["excerpt"].strip().rstrip(".")
                if i == 0:
                    parts.append(f"Based on your notes, in '{item['title']}' you recorded: \"{clean}\".")
                elif i == len(answer_items[:4]) - 1:
                    parts.append(f"Lastly, in '{item['title']}', you noted: \"{clean}\".")
                else:
                    parts.append(f"Additionally, in '{item['title']}', you wrote: \"{clean}\".")
            synthesized_answer = " ".join(parts)

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

    def generate_related_explanation(
        self,
        target_note: dict[str, Any],
        candidate_note: dict[str, Any],
        similarity: float,
        shared_tags: list[str],
    ) -> str:
        """
        Generates a concise 1-2 sentence explanation of why two notes are related.
        """
        if shared_tags:
            tag_str = ", ".join(f"#{t}" for t in shared_tags[:3])
            return f"Shares topic tags {tag_str} with {round(similarity * 100)}% semantic context match."

        target_proj = target_note.get("project_id")
        candidate_proj = candidate_note.get("project_id")
        if target_proj and target_proj == candidate_proj:
            return f"Part of the same project '{target_proj}' with {round(similarity * 100)}% concept overlap."

        # Compute overlapping words between title and content
        t_words = set(re.findall(r"\b\w{4,}\b", target_note.get("content", "").lower()))
        c_words = set(re.findall(r"\b\w{4,}\b", candidate_note.get("content", "").lower()))
        overlap = list(t_words.intersection(c_words) - self.STOP_ENTITIES)

        if overlap:
            top_terms = ", ".join(overlap[:3])
            return f"Discusses related concepts concerning {top_terms} ({round(similarity * 100)}% match)."

        return f"Semantically connected with {round(similarity * 100)}% knowledge base relevance."

    def generate_recap(
        self,
        notes: list[dict[str, Any]],
        period: str,
        start_date: datetime,
        end_date: datetime,
    ) -> dict[str, Any]:
        """
        Organizes notes into Projects, Learning, Decisions, Ideas, and Personal Notes.
        Extracts key decisions, recurring topics, and unfinished ideas.
        """
        categories = {
            "Projects": {
                "description": "Project architecture, features, and technical implementations",
                "highlights": [],
            },
            "Learning": {
                "description": "Technical research, documentation, and conceptual studies",
                "highlights": [],
            },
            "Important Decisions": {
                "description": "Architecture, database, and infrastructure choices",
                "highlights": [],
            },
            "Ideas": {
                "description": "Proposed concepts, future explorations, and backlogs",
                "highlights": [],
            },
            "Personal Notes": {
                "description": "Schedules, appointments, reflections, and personal entries",
                "highlights": [],
            },
        }

        important_decisions: list[str] = []
        unfinished_ideas: list[str] = []
        all_tags: list[str] = []

        decision_regex = re.compile(r"\b(selected|chose|decided|decision|choice|architecture decision|rfc)\b", re.IGNORECASE)
        learning_regex = re.compile(r"\b(learned|studied|research|reading|concept|tutorial|documentation)\b", re.IGNORECASE)
        idea_regex = re.compile(r"\b(idea|explore|consider|future|todo|investigate|proposal|backlog)\b", re.IGNORECASE)

        for n in notes:
            title = n.get("title", "")
            content = n.get("content", "")
            tags = n.get("tags", [])
            all_tags.extend(tags)
            updated_at = n.get("updated_at") or datetime.now(timezone.utc)

            # Summarize note for highlight
            sentences = [s.strip() for s in re.split(r'(?<=[.!?])\s+', content.replace("\n", " ")) if s.strip()]
            first_sentence = sentences[0] if sentences else content[:100]

            highlight = {
                "note_id": n["id"],
                "note_title": title,
                "summary": first_sentence,
                "tags": tags,
                "updated_at": updated_at,
            }

            assigned = False

            # Check Decisions
            if decision_regex.search(content) or decision_regex.search(title) or "decision" in tags:
                categories["Important Decisions"]["highlights"].append(highlight)
                important_decisions.append(f"{title}: {first_sentence}")
                assigned = True

            # Check Learning
            if learning_regex.search(content) or learning_regex.search(title) or "learning" in tags:
                categories["Learning"]["highlights"].append(highlight)
                assigned = True

            # Check Ideas
            if idea_regex.search(content) or idea_regex.search(title) or "idea" in tags:
                categories["Ideas"]["highlights"].append(highlight)
                unfinished_ideas.append(f"{title}: {first_sentence}")
                assigned = True

            # Check Projects
            if n.get("project_id") or any(t in {"architecture", "flutter", "fastapi", "backend", "mobile", "project"} for t in tags):
                categories["Projects"]["highlights"].append(highlight)
                assigned = True

            # Default to Personal Notes
            if not assigned:
                categories["Personal Notes"]["highlights"].append(highlight)

        # Recurring topics
        tag_counts = Counter(all_tags)
        recurring_topics = [f"#{tag} ({count})" for tag, count in tag_counts.most_common(5)]

        # Filter empty categories
        non_empty_categories = [
            {
                "category": name,
                "description": data["description"],
                "highlights": data["highlights"],
            }
            for name, data in categories.items()
            if data["highlights"]
        ]

        overview = (
            f"During {period}, you recorded or modified {len(notes)} note(s) across "
            f"{len(non_empty_categories)} knowledge categories."
        )

        return {
            "period": period,
            "start_date": start_date,
            "end_date": end_date,
            "total_notes": len(notes),
            "overview": overview,
            "categories": non_empty_categories,
            "important_decisions": important_decisions[:5],
            "recurring_topics": recurring_topics,
            "unfinished_ideas": unfinished_ideas[:5],
        }


def get_llm_provider() -> LLMProvider:
    return GroundedLocalLLMProvider()
