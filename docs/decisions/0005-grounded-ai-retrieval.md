# ADR 0005: Grounded Personal AI Memory & Anti-Hallucination Retrieval

## Status
Accepted

## Context
Phase 5 introduces personal memory retrieval and conversational querying over a user's private notes and knowledge base. Traditional generative AI approaches suffer from two fatal flaws in personal knowledge management:
1. **Hallucination**: Generating plausible-sounding facts, dates, or decisions that the user never actually wrote or agreed to.
2. **Privacy & Tenant Isolation**: Leaking confidential personal data across multiple tenant accounts during vector similarity retrieval.

## Decisions

1. **Strict Personal Tenant Isolation**:
   - Embeddings are persisted in the `note_embeddings` table with foreign key `user_id`.
   - Every semantic search query (`/api/v1/ai/semantic-search`) and grounded query (`/api/v1/ai/ask`) enforces `NoteEmbedding.user_id == current_user.id`.
   - Notes belonging to other users are never retrieved, embedded in prompts, or cited under any circumstance.

2. **Source Grounding with Verbatim Excerpt Citations**:
   - The LLM provider (`GroundedLocalLLMProvider`) guarantees that answers are synthesized strictly from retrieved notes that exceed the similarity threshold (`similarity >= 0.25`).
   - Every generated answer includes source citations with:
     - Note ID
     - Note title
     - Verbatim excerpt snippet
     - Cosine similarity relevance score
   - Tapping citations in the mobile client opens the original note for immediate verification.

3. **Fallback on Insufficient Evidence**:
   - If no user notes pass the relevance threshold, or if retrieved notes lack sufficient evidence to answer the query, the system explicitly returns:
     `"Insufficient information in your saved notes to answer this question."`
   - It sets `has_sufficient_evidence = false` and returns zero citations rather than guessing or hallucinating facts.

4. **Stale Embedding Detection via Content Hashing**:
   - `NoteEmbedding` stores a SHA-256 `content_hash` of `{title}:{content}`.
   - Upon querying, `RetrievalService.sync_user_embeddings` inspects the user's active notes and updates embeddings only for notes that were created, edited, or deleted.
   - Prevents stale search results after note updates without requiring expensive background reindexing workers.

5. **Sub-millisecond Deterministic Embedding Vectorizer**:
   - Uses `DeterministicEmbeddingProvider` combining word unigrams (filtered for English stopwords) and character 3-grams for stem-matching into a normalized 256-dimensional space.
   - Operates with zero network roundtrips, sub-millisecond execution latency, and 100% cross-process determinism.

## Consequences
- Guaranteed zero hallucination for unrecorded memories.
- Total tenant privacy and security.
- Instant, auditable citations for all answers in the Flutter client.
