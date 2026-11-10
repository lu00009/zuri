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
            "it", "that", "this", "them", "its", "they", "why", "which",
            "alternative", "option", "previous", "former", "latter", "compare"
        }

        # Context resolution should ONLY trigger if the query actually contains referential indicators
        if not q_tokens.intersection(referential_indicators):
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
        Recognizes greetings, identity/capabilities inquiries, gratitude, farewells,
        reactions, check-ins, feelings, and casual conversation.
        Returns a friendly natural response if matched, or None to fall back to note retrieval.
        Separates pure conversational intent from personal memory-search queries.
        """
        q = query.strip().lower()
        # Remove emojis and punctuation for clean token matching
        q_clean = re.sub(r"[^\w\s]", " ", q)
        q_clean = re.sub(r"\s+", " ", q_clean).strip()
        if not q_clean:
            return "Hey there! How can I help you today?"

        words = q_clean.split()
        num_words = len(words)

        # If the user explicitly asks about saved notes, personal information, or specific knowledge,
        # it is NOT conversational chit-chat; it must be routed to memory retrieval.
        memory_seeking_pattern = (
            r"\b(save|saved|my\s+notes?|notes?\s+about|notes?\s+on|did\s+i\s+save|"
            r"what\s+did\s+i|what\s+do\s+i\s+have|my\s+projects?|my\s+ideas?|my\s+learnings?|"
            r"my\s+meetings?|remind\s+me|search\s+for|find\s+notes?|look\s+up|what\s+were\s+my|"
            r"check\s+my\s+notes?|in\s+my\s+notes?|from\s+my\s+notes?)\b"
        )
        is_about_zuri = bool(re.search(r"\b(who\s+are\s+you|what\s+can\s+you\s+do|who\s+made\s+you|are\s+you)\b", q_clean))
        if re.search(memory_seeking_pattern, q_clean) and not is_about_zuri:
            return None

        # 0. Emotional feedback, criticisms, or corrections
        if re.search(r"\b(liar|lying|you\s+lie|you\s+are\s+a\s+liar|youre\s+a\s+liar|fake)\b", q_clean):
            return "I'm sorry if I gave you an inaccurate or confusing response! I only aim to help you recall what you've saved. What can I look up or clarify for you?"
        if re.search(r"\b(wrong|incorrect|not\s+true|thats\s+wrong|you\s+are\s+wrong|youre\s+wrong)\b", q_clean):
            return "My apologies for the confusion! Let me know what information was incorrect or what you'd like me to look up in your notes."

        # 1. Reactions, interjections, and conversational acknowledgments
        # e.g., 'oh', 'ohh', 'ohhh', 'ooh', 'ah', 'ahh', 'aha', 'i see', 'got it', 'makes sense'
        if q_clean in {"oh", "ohh", "ohhh", "ooh", "ah", "ahh", "aha", "i see", "got it", "makes sense", "understood", "alright", "all right"}:
            return "Got it! Let me know if you want to explore more or jot down a new thought."

        # e.g., 'cool', 'nice', 'sweet', 'awesome', 'great', 'wonderful', 'perfect', 'dope', 'sounds good'
        if q_clean in {"cool", "nice", "sweet", "awesome", "great", "wonderful", "perfect", "sounds good", "dope", "neat"}:
            return "Glad to hear! What else is on your mind?"

        # e.g., 'ok', 'okay', 'k', 'kk'
        if q_clean in {"ok", "okay", "k", "kk", "okie", "okies", "alrighty"}:
            return "Sounds good! I'm right here whenever you need me."

        # e.g., 'wow', 'whoa', 'really', 'seriously', 'for real', 'no way'
        if q_clean in {"wow", "whoa", "really", "seriously", "for real", "no way"}:
            return "Yep! Let me know if you'd like to look deeper into anything."

        # e.g., 'haha', 'hahaha', 'hehe', 'lol', 'lmao', 'rofl'
        if re.search(r"\b(ha(ha)+|he(he)+|lol|lmao|rofl)\b", q_clean):
            return "😄 Always happy to chat! What's next on your agenda?"

        # e.g., 'hm', 'hmm', 'hmmm', 'um', 'umm', 'uh', 'idk', 'maybe'
        if q_clean in {"hm", "hmm", "hmmm", "um", "umm", "uh", "idk", "maybe", "not sure"}:
            return "Take your time! Anything specific you're trying to remember or brainstorm?"

        # e.g., 'yeah', 'yep', 'yup', 'yes', 'sure', 'definitely', 'absolutely'
        if q_clean in {"yeah", "yea", "yep", "yup", "yes", "sure", "definitely", "absolutely"}:
            return "Awesome! How can I help next?"

        # e.g., 'nah', 'nope', 'no', 'nothing', 'not really'
        if q_clean in {"nah", "nope", "no", "nothing", "not really", "nevermind", "never mind"}:
            return "No problem at all! I'm here whenever you need to check your notes or organize your thoughts."

        # 2. Jokes and fun
        if re.search(r"\b(tell\s+me\s+a\s+joke|make\s+me\s+laugh|say\s+something\s+funny)\b", q_clean):
            return "Why do programmers prefer dark mode? Because light attracts bugs! 😄 What would you like to explore next?"

        # 3. How are you / check-ins (including shorthands like 'how is u', 'how r u', 'hru', 'wyd', 'wbu')
        if re.search(
            r"\b(how\s*(are|is|r)\s*(you|u|ya|things|everything)|hru|how\s*u\s*(doin|doing)|"
            r"hows\s*(it\s*going|everything|your\s*day)|how\s*is\s*it\s*going|whats?\s*(up|new|good)|wyd|wbu)\b",
            q_clean,
        ):
            return (
                "I'm doing great, thank you for asking! 😊 How are you doing today? "
                "We can chat, brainstorm, or explore your saved notes."
            )

        # 4. User feelings and states (e.g. 'i am good', 'doing well', 'i'm tired', 'bored')
        if re.search(r"\b(i\s*am\s*(good|fine|well|great|okay|alright|ok)|doing\s*well|not\s*bad|all\s*good|pretty\s*good)\b", q_clean):
            return "Glad to hear that! What would you like to work on or review today?"
        if re.search(r"\b(i\s*am\s*(tired|exhausted|sleepy|bored|busy|stressed)|feeling\s*(tired|down|sad|exhausted|bored))\b", q_clean):
            return "I hear you—take it easy! Whenever you feel like reviewing your notes or brain-dumping some thoughts, I'll be right here."

        # 5. Identity & About Zuri
        if re.search(r"\b(who\s+are\s+you|what\s+is\s+your\s+name|what\s+are\s+you|tell\s+me\s+about\s+yourself|introduce\s+yourself|who\s+made\s+you|who\s+created\s+you|are\s+you\s+(an\s+)?ai|what\s+is\s+zuri|who\s+is\s+zuri)\b", q_clean):
            return (
                "I'm Zuri, your personal AI assistant and memory companion! "
                "I help you remember ideas, organize notes, connect related thoughts, "
                "and chat with you naturally anytime."
            )

        # 6. Capabilities & Help
        if re.search(r"\b(what\s+can\s+you\s+do|how\s+can\s+you\s+help|what\s+do\s+you\s+do|what\s+are\s+your\s+features|help\s+me|help)\b", q_clean):
            return (
                "Here is what I can do for you:\n"
                "• Answer questions based on your saved notes and memories\n"
                "• Remember conversation context across follow-up questions\n"
                "• Connect related ideas across your notebooks\n"
                "• Chat with you naturally and keep your thoughts organized\n\n"
                "Feel free to ask me anything about your notes, or just chat!"
            )

        # 7. Greetings (e.g. 'hi', 'hello', 'hey', 'good morning', 'yo', 'sup')
        greeting_match = re.search(
            r"\b(hello|hi|hey|heyy|heyyy|howdy|greetings|good\s*(morning|afternoon|evening|day)|yo|greet|say\s+hello|say\s+hi)\b",
            q_clean,
        )
        if greeting_match:
            has_question = bool(re.search(r"\b(what|which|where|when|why|who\s+did|how\s+to|how\s+do|how\s+did)\b", q_clean))
            if not has_question or num_words <= 8:
                if "morning" in q_clean:
                    return "Good morning! How can I help you today?"
                elif "afternoon" in q_clean:
                    return "Good afternoon! How is your day going? Let me know if you need to recall or save anything."
                elif "evening" in q_clean:
                    return "Good evening! What would you like to review or brainstorm tonight?"
                return "Hello! I'm Zuri, your personal AI assistant. How can I help you today? You can ask me anything about your notes, or share what's on your mind."

        # 8. Farewells
        if re.search(
            r"\b(goodbye|bye|bye\s*bye|see\s*(you|ya|u)|farewell|talk\s*to\s*you\s*later|good\s*night|cya|catch\s*ya)\b",
            q_clean,
        ) and not re.search(r"\b(what|why|which|how|where|when)\b", q_clean):
            if "night" in q_clean:
                return "Good night! Rest well, and I'll be right here whenever you're ready to pick up your notes again."
            return "Goodbye! Have a great day ahead. Whenever you have a new thought or question, I'll be right here."

        # 9. Thank you / Gratitude
        if re.search(
            r"\b(thank\s*you|thanks|thank\s+you\s+so\s+much|thanks\s+a\s+lot|appreciate\s+it|thx|ty)\b",
            q_clean,
        ) and not re.search(r"\b(what|why|which|how|where|when)\b", q_clean):
            return "You're very welcome! If there's anything else you'd like to check or remember, just let me know."

        # 10. Very short conversational statements (1 to 2 words that aren't specific technical nouns)
        if num_words <= 2 and not re.search(r"\b(note|save|code|pass|key|email|task|todo|project|date|plan|meet|buy|call)\b", q_clean):
            return "I'm listening! Feel free to ask me anything about your notes, or share what you'd like to talk about."

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
                    "There is insufficient information in your saved notes about that. "
                    "Feel free to save a note with more details, or ask me anything else!"
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
        is_age_query = bool(re.search(r"\b(how\s+old\s+am\s+i|what\s+is\s+my\s+age|my\s+age)\b", query.lower()))

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

        # Synthesize natural conversational answer
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
            e1 = self._make_conversational(first["excerpt"])
            e2 = self._make_conversational(second["excerpt"])
            synthesized_answer = (
                f"Based on your notes, there was an update recorded over time: "
                f"in '{first['title']}', you noted that {e1}. "
                f"However, in '{second['title']}', you revised this to: {e2}."
            )
        elif is_comparison and len(answer_items) >= 2:
            first = answer_items[0]
            second = answer_items[1]
            e1 = self._make_conversational(first["excerpt"])
            e2 = self._make_conversational(second["excerpt"])
            synthesized_answer = (
                f"Comparing your saved notes: in '{first['title']}', you noted that {e1}. "
                f"In contrast, in '{second['title']}', you noted that {e2}."
            )
        elif len(answer_items) == 1:
            item = answer_items[0]
            e = self._make_conversational(item["excerpt"])
            if is_age_query:
                age_match = re.search(r"\b(\d{1,3})\b", e)
                if age_match:
                    age_val = age_match.group(1)
                    synthesized_answer = f"You're {age_val} years old! In your note '{item['title']}', you recorded that {e}."
                else:
                    synthesized_answer = f"According to your note '{item['title']}', {e}."
            else:
                synthesized_answer = f"According to your note '{item['title']}', {e}."
        elif len(answer_items) == 2:
            item1, item2 = answer_items[0], answer_items[1]
            e1 = self._make_conversational(item1["excerpt"])
            e2 = self._make_conversational(item2["excerpt"])
            synthesized_answer = (
                f"Based on your saved notes: in '{item1['title']}', you noted that {e1}. "
                f"Additionally, in '{item2['title']}', you noted that {e2}."
            )
        else:
            parts = []
            for i, item in enumerate(answer_items[:4]):
                clean = self._make_conversational(item["excerpt"])
                if i == 0:
                    parts.append(f"Based on your notes, in '{item['title']}' you recorded that {clean}.")
                elif i == len(answer_items[:4]) - 1:
                    parts.append(f"Lastly, in '{item['title']}', you noted that {clean}.")
                else:
                    parts.append(f"Additionally, in '{item['title']}', you noted that {clean}.")
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

    @staticmethod
    def _make_conversational(text: str) -> str:
        """
        Converts raw note snippets into natural, grammatical 2nd-person conversational speech.
        """
        s = text.strip().rstrip(".")
        s = re.sub(r"^[\"']|[\"']$", "", s).strip()
        if re.match(r"^am\s+\d+", s, re.I):
            s = "you are " + s[3:]
        elif re.match(r"^i\s+am\s+", s, re.I):
            s = "you are " + s[5:]
        elif re.match(r"^i\'m\s+", s, re.I):
            s = "you are " + s[4:]
        elif re.match(r"^i\s+", s, re.I):
            s = "you " + s[2:]
        elif re.match(r"^my\s+", s, re.I):
            s = "your " + s[3:]
        return s

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
