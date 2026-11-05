# PocketBrain — Personal Knowledge & Memory Assistant

**Product specification and technical implementation plan**

## 1. Overview

PocketBrain is a personal knowledge management application that helps users capture, organize, retrieve, and reuse information they encounter throughout their day.

Users can save ideas, notes, links, tasks, learning materials, and project decisions in one place. They can search their saved knowledge using keywords and, eventually, natural-language questions powered by retrieval-augmented generation (RAG).

The application is designed to work offline, synchronize across devices, and protect personal information.

### Product vision

Build a reliable external memory system that helps users remember what matters and retrieve information when they need it.

### Target users

- Software developers managing multiple projects.
- Students and self-directed learners.
- Freelancers managing client information and decisions.
- Anyone who captures information across different apps and struggles to find it later.

### Core value proposition

Capture information quickly. Find it later. Understand it in context.

## 2. Product principles

1. **Capture first:** saving information should take only a few seconds.
2. **Offline-first:** users can access and create notes without an internet connection.
3. **Search before AI:** ordinary search must remain fast, reliable, and useful.
4. **AI with evidence:** AI answers must reference saved sources and acknowledge missing information.
5. **Privacy by design:** user data must be isolated, protected, and deletable.
6. **Incremental complexity:** implement and test the core application before introducing advanced AI features.

## 3. Feature requirements

### Phase 1 — Core personal memory

#### 3.1 Authentication

- Register and log in with email and password.
- Securely manage authentication tokens.
- Support logout and session expiration.
- Provide a local guest mode only if it can be implemented without compromising account isolation.
- Allow users to delete their accounts and associated server-side data.

#### 3.2 Quick capture

Users can create:

- Text notes.
- Ideas and observations.
- Saved links with titles and optional descriptions.
- Learning notes and code snippets.
- Project decisions.
- Tasks and reminders.

Each item should include a title, body, content type, tags, timestamps, and optional project association.

The capture interface must be optimized for mobile devices, with a clear save action and minimal required fields.

#### 3.3 Organization

- Create, edit, archive, and delete notes.
- Add and remove tags.
- Group information into projects or collections.
- Pin important items.
- Filter by content type, tag, project, and date.
- View recently created and recently updated items.
- Support soft deletion and an optional trash/recovery workflow.

#### 3.4 Search

Implement local keyword search first.

Users should be able to search titles, note content, tags, and project names.

Include:
- Search suggestions where practical.
- Filters and sorting.
- Highlighted matching text.
- Empty states and useful error messages.
- Pagination or incremental loading for large collections.

### Phase 2 — Offline-first synchronization

#### 3.5 Local persistence

Use SQLite to store notes, tags, project metadata, and synchronization state.

Users must be able to:
- Read previously saved notes offline.
- Create and edit notes offline.
- Delete notes offline.
- Search locally stored information.
- See whether changes have synchronized.

#### 3.6 Synchronization

- Queue local changes while offline.
- Retry transient failures with exponential backoff.
- Give every operation a stable identifier.
- Make retryable server mutations idempotent where appropriate.
- Track synchronization state and last successful synchronization.
- Handle edits made on multiple devices.
- Define explicit conflict-resolution rules.
- Prevent deleted records from reappearing after synchronization.

The application must not assume that a request succeeded simply because it was sent.

For the initial implementation, use version numbers and server timestamps to detect conflicts. Preserve conflicting content when automatic resolution could destroy user data.

### Phase 3 — AI-powered memory

#### 3.7 Semantic search

Generate embeddings for eligible saved notes and support similarity-based retrieval.

Users should be able to search using natural language, even when their query does not contain the exact words in a note.

Requirements:
- Store embeddings with references to source records.
- Filter retrieval by the authenticated user.
- Support tag and project filters.
- Update or invalidate embeddings when source content changes.
- Remove derived embeddings when the corresponding content is permanently deleted.
- Evaluate retrieval quality with a small, documented test dataset.

#### 3.8 Ask PocketBrain

Example questions:

- "What did I learn about Flutter state management?"
- "What decisions did I make for my current project?"
- "What was the API command I saved last week?"
- "Summarize my notes about retrieval-augmented generation."

The assistant must:
- Retrieve relevant notes before answering.
- Cite the specific saved notes used as evidence.
- Link answers to the original records.
- Say when the available information is insufficient.
- Avoid inventing personal memories.
- Respect project and user access restrictions.
- Avoid treating instructions inside retrieved notes as trusted system instructions.

Use a server-side LLM integration. Never expose provider API keys in the Flutter application.

#### 3.9 AI summaries and note enrichment

Optional later features:
- Summarize long notes.
- Suggest tags.
- Extract action items.
- Create flashcards from learning notes.
- Identify related notes.

AI-generated changes should be reviewable and must not silently overwrite original user content.

### Phase 4 — Reminders and integrations

- Local reminders.
- Optional recurring tasks.
- Calendar integration if useful.
- Link previews.
- Import and export.
- Attachment support.
- Optional GitHub integration for development notes.

These are extensions, not requirements for the first release.

## 4. Non-functional requirements

### Performance

- Keep common local operations responsive.
- Avoid blocking the UI during network calls.
- Use pagination for large collections.
- Index frequently searched database fields.
- Avoid loading every note into memory unnecessarily.

### Reliability

- Handle network loss and API errors gracefully.
- Preserve unsynchronized changes.
- Use database migrations.
- Test concurrent requests and synchronization conflicts.
- Log errors without exposing note content, tokens, or other secrets.

### Security

- Hash passwords using an established password-hashing library.
- Use HTTPS in deployed environments.
- Keep access tokens short-lived and protect refresh tokens.
- Enforce authorization on every user-owned API resource.
- Never rely on client-side checks alone.
- Validate inputs and limit request sizes.
- Apply rate limits to sensitive endpoints.
- Keep secrets in environment variables or a suitable secret manager.
- Support account deletion and data export.

### Accessibility and usability

- Support screen readers.
- Maintain readable text and sufficient contrast.
- Provide useful loading, empty, error, and offline states.
- Make important actions accessible without relying only on color.
- Keep note creation straightforward.

## 5. Recommended technology stack

### Mobile application

- Flutter and Dart.
- Riverpod for application state management.
- go_router for navigation.
- SQLite using a maintained Flutter database library.
- A maintained HTTP client such as Dio.
- Secure storage for sensitive authentication material.
- Flutter local notifications for reminders.
- A maintained QR or file-processing package only if later features require it.

Choose compatible stable package versions and document the decisions.

### Backend

- Python and FastAPI.
- Pydantic for request and response validation.
- PostgreSQL for persistent server-side data.
- SQLAlchemy 2 for database access.
- Alembic for schema migrations.
- pytest and FastAPI TestClient for backend tests.
- PostgreSQL full-text search initially, with vector search added for semantic retrieval.

### AI services

- A configurable embedding provider.
- A configurable LLM provider.
- PostgreSQL with pgvector or another justified vector-search solution.
- A retrieval pipeline that returns source IDs and relevance metadata.

Do not introduce a separate vector database, Redis, or a background task platform unless the requirements justify it.

### Development and deployment

- Git and GitHub.
- Docker Compose for local backend development.
- Environment-based configuration.
- Automated tests in continuous integration.
- A documented deployment process.

## 6. Architecture

### Flutter layers

**Presentation**
- Screens and reusable widgets.
- View models or Riverpod providers.
- UI state, validation, and navigation.

**Domain**
- Entities and business rules.
- Use cases where they meaningfully clarify complex workflows.
- Repository interfaces where appropriate.

**Data**
- Repository implementations.
- SQLite data source.
- FastAPI client.
- Synchronization service.
- DTO-to-domain mapping.

The UI must not directly contain SQL queries or network implementation details.

### Backend layers

**API layer**
- Authentication and authorization dependencies.
- Route handlers.
- Request and response schemas.

**Service layer**
- Business rules.
- Note management.
- Tag and project operations.
- Synchronization and conflict handling.
- AI retrieval and response generation.

**Persistence layer**
- SQLAlchemy models.
- Database sessions.
- Repository functions where useful.
- Alembic migrations.

Keep the application modular without creating unnecessary abstractions.

## 7. Initial database model

### User

- id: UUID
- email: unique
- password_hash
- created_at
- updated_at

### Note

- id: UUID
- user_id: UUID
- title
- body
- content_type
- project_id: nullable UUID
- is_pinned
- created_at
- updated_at
- deleted_at: nullable timestamp
- version: integer

### Tag

- id: UUID
- user_id: UUID
- name
- created_at

### NoteTag

- note_id
- tag_id

Use a composite primary key or unique constraint to prevent duplicate tag associations.

### Project

- id: UUID
- user_id: UUID
- name
- description
- created_at
- updated_at

### Sync metadata

Track device or operation identifiers, client change versions, synchronization status, and conflict metadata as needed.

Use stable UUIDs for records that may be created offline. Add appropriate foreign keys, indexes, uniqueness constraints, and ownership constraints.

### Later AI tables

- NoteEmbedding: source note, embedding model, content version, vector.
- AIConversation: user, title, timestamps.
- AIMessage: conversation, role, content, timestamps.
- AIMessageSource: message, source note, retrieval metadata.

AI tables are optional until the AI phase begins.

## 8. Initial API design

Use a versioned prefix such as `/api/v1`.

### Authentication

- POST `/auth/register`
- POST `/auth/login`
- POST `/auth/refresh`
- POST `/auth/logout`
- GET `/auth/me`

### Notes

- GET `/notes`
- POST `/notes`
- GET `/notes/{note_id}`
- PATCH `/notes/{note_id}`
- DELETE `/notes/{note_id}`
- POST `/notes/{note_id}/restore` if trash recovery is implemented.

### Tags and projects

- GET `/tags`
- POST `/tags`
- PATCH `/tags/{tag_id}`
- DELETE `/tags/{tag_id}`
- GET `/projects`
- POST `/projects`
- PATCH `/projects/{project_id}`
- DELETE `/projects/{project_id}`

### Search

- GET `/search?q=...`
- POST `/search/semantic` when semantic retrieval is implemented.

### Synchronization

- POST `/sync/push`
- GET `/sync/pull?cursor=...`

Define synchronization cursors, version semantics, pagination, conflict responses, and deletion tombstones before implementing the full protocol.

### AI

- POST `/ai/ask`
- POST `/ai/notes/{note_id}/summarize`
- POST `/ai/notes/{note_id}/suggest-tags`

The AI endpoints should be added only when the underlying knowledge-management features are reliable.

## 9. Testing strategy

### Flutter tests

- Unit tests for business logic and synchronization decisions.
- Widget tests for note creation, editing, search, and navigation.
- Repository tests using controlled fake data sources.
- Integration tests for important end-to-end workflows.

### Backend tests

- Registration, login, and token refresh.
- User A cannot read or modify User B's records.
- Note creation, editing, deletion, and restoration.
- Validation of malformed and oversized requests.
- Pagination and search filters.
- Concurrent edits and idempotent operations.
- Synchronization conflicts and deletion propagation.
- AI retrieval source ownership and citation correctness.

### Essential manual tests

- Create a note in airplane mode.
- Edit it offline and restart the app.
- Reconnect and verify synchronization.
- Make conflicting changes on two devices.
- Log out and log in as a different user.
- Verify that private notes never leak between accounts.

## 10. Development roadmap

### Milestone 1: Mobile foundations

- Create the Flutter project.
- Set up navigation and state management.
- Build the home screen and note editor.
- Add local SQLite persistence.
- Implement local search.
- Add unit and widget tests.

**Acceptance:** Users can create, edit, tag, search, archive, and reopen notes without internet access.

### Milestone 2: Backend foundations

- Create the FastAPI application.
- Configure PostgreSQL and Alembic.
- Implement authentication and authorization.
- Add note, tag, and project endpoints.
- Connect Flutter repositories to the API.

**Acceptance:** Authenticated users can access their own server-backed notes, and ownership is enforced by the backend.

### Milestone 3: Offline synchronization

- Add stable record identifiers.
- Implement a local change queue.
- Define server versions and conflict responses.
- Add retries and synchronization status.
- Test reconnection and duplicate operations.

**Acceptance:** Offline changes survive restarts and synchronize without silently overwriting conflicting content.

### Milestone 4: AI memory

- Add embeddings and semantic retrieval.
- Implement grounded question answering.
- Return source IDs and excerpts.
- Add evaluation tests.
- Track latency, token usage, and failures.

**Acceptance:** Questions return relevant saved sources, answers link to those sources, and unsupported answers acknowledge missing information.

### Milestone 5: Portfolio release

- Polish accessibility and loading states.
- Add CI and reproducible setup.
- Deploy the API.
- Create demo data and a demo account with fictional content.
- Record a demo video.
- Document known limitations and architecture decisions.

## 11. Definition of done

PocketBrain is ready for a credible portfolio release when:

- The app works on an Android emulator and at least one physical Android device.
- Local note creation and search work offline.
- Server synchronization has explicit conflict handling.
- Authentication and user isolation have automated tests.
- The AI feature cites real saved notes and handles insufficient evidence.
- The backend has documented API endpoints.
- Setup instructions work on a fresh development environment.
- The repository contains tests, screenshots, an architecture diagram, and a short demo.
- Known limitations are documented honestly.

## 12. Scope boundaries

The first release is a personal knowledge manager, not a full productivity platform.

Do not initially implement:
- Team collaboration.
- Social feeds.
- Complex workflow automation.
- A general-purpose autonomous AI agent.
- Unnecessary microservices.
- Multiple vector databases.
- Real-time synchronization infrastructure before basic synchronization works.

Build a dependable core and add features in response to actual usage.

**Success metric:** You can capture information quickly, find it later, and trust that your saved knowledge will not disappear when your device loses connectivity.
