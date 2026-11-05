# Zuri: Offline-First Personal Knowledge & Memory Assistant

[![Flutter](https://img.shields.io/badge/Flutter-3.47.8-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.110.0-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![SQLite](https://img.shields.io/badge/SQLite-Offline--First-003B57?logo=sqlite&logoColor=white)](https://www.sqlite.org)
[![Pytest](https://img.shields.io/badge/Pytest-22%20passed-brightgreen?logo=pytest&logoColor=white)](https://pytest.org)
[![Flutter Tests](https://img.shields.io/badge/Flutter%20Tests-22%20passed-brightgreen?logo=flutter&logoColor=white)](https://flutter.dev)

PocketBrain is an offline-first personal knowledge repository and conversational memory assistant built with **Flutter** (Android and Linux desktop) and a **FastAPI** backend (Python 3.12).

PocketBrain empowers users to capture notes, ideas, links, learning reflections, and architectural decisions with zero network latency. When connectivity is present, it securely synchronizes changes across devices using an **idempotent, conflict-preserving sync engine** and provides **source-grounded AI memory retrieval** with verifiable citations and zero hallucination.

---

## 1. Architectural Highlights

```
                                  POCKETBRAIN SYSTEM
 ┌──────────────────────────────────────────────────────────────────────────────────┐
 │                               FLUTTER MOBILE APP                                 │
 │  ┌───────────────────────┐  ┌───────────────────────┐  ┌───────────────────────┐ │
 │  │      HomeScreen       │  │   NoteEditorScreen    │  │    AiMemoryScreen     │ │
 │  │ (Search, Filter, Sync)│  │(Live Edit, Tags, Pin) │  │(Grounded Q&A, Sources)│ │
 │  └───────────┬───────────┘  └───────────┬───────────┘  └───────────┬───────────┘ │
 │              │                          │                          │             │
 │              └──────────────────┐       │       ┌──────────────────┘             │
 │                                 ▼       ▼       ▼                                │
 │                              [ Riverpod 2.x State ]                              │
 │                                 │               │                                │
 │             ┌───────────────────┘               └───────────────────┐            │
 │             ▼                                                       ▼            │
 │    [ NotesLocalRepository ]                               [ SyncEngine / Queue ] │
 │             │                                                       │            │
 │             ▼                                                       ▼            │
 │     [( SQLite Device DB )]                                 [ ApiClient (Dio) ]   │
 └─────────────┼───────────────────────────────────────────────────────┼────────────┘
               │                                                       │ HTTPS
               │ (100% Offline Autonomy)                               ▼
 ┌─────────────┼────────────────────────────────────────────────────────────────────┐
 │             │                      FASTAPI BACKEND                               │
 │             │               ┌──────────────────────────────┐                     │
 │             │               │    /api/v1/auth (JWT)        │                     │
 │             │               │    /api/v1/notes (CRUD)      │                     │
 │             │               │    /api/v1/sync (Push/Pull)  │                     │
 │             │               │    /api/v1/ai (Ask & Search) │                     │
 │             │               └──────────────┬───────────────┘                     │
 │             │                              ▼                                     │
 │             │                [ Multi-Tenant Auth Guard ]                         │
 │             │                              ▼                                     │
 │             │           ┌──────────────────┴──────────────────┐                  │
 │             │           ▼                                     ▼                  │
 │             │   [ Sync Engine ]                     [ Grounded AI Service ]      │
 │             │   - Idempotency Table                 - Subword Vectorizer         │
 │             │   - Version Conflict Check            - SHA-256 Stale Sync         │
 │             │   - Soft-Deletion Watermark           - Verifiable Citations       │
 │             │           │                                     │                  │
 │             │           └──────────────────┬──────────────────┘                  │
 │             │                              ▼                                     │
 │             │                  [( SQLAlchemy 2.0 / Alembic )]                    │
 └─────────────┴────────────────────────────────────────────────────────────────────┘
```

### Core Architectural Principles
1. **Client Autonomy & Offline-First**: Every creation, tag update, search, and deletion writes immediately to local SQLite using client UUIDv4 identifiers. Zero blocking on network calls.
2. **Conflict Preservation Over Last-Write-Wins**: Traditional sync engines silently overwrite concurrent changes with timestamps. PocketBrain rejects stale updates, preserves the server's record, and automatically branches conflicting local edits into sibling notes (`"[Conflict] $title (Local Edit)"`), guaranteeing zero data loss.
3. **Strict Multi-Tenant Isolation**: Every note, tag, sync operation, and vector embedding is strictly scoped to `user_id == current_user.id` at the database level.
4. **Anti-Hallucination AI Grounding**: Generative memory queries only synthesize answers when evidence exceeds the semantic threshold (`>= 0.25`). Every response contains clickable verbatim source citations linking to original notes.

---

## 2. Repository Layout

```text
.
├── mobile/                                # Flutter Client Application
│   ├── lib/
│   │   ├── app.dart                       # GoRouter navigation & app theme
│   │   ├── main.dart                      # App entrypoint with Riverpod ProviderScope
│   │   ├── domain/entities/note.dart      # Immutable Note domain model & UUIDv4
│   │   ├── data/
│   │   │   ├── datasources/local/         # SQLite AppDatabase & SyncQueueDataSource
│   │   │   ├── datasources/remote/        # Dio ApiClient, Auth, Sync, & AI data sources
│   │   │   ├── repositories/              # NotesLocalRepository with transactions
│   │   │   └── sync/sync_engine.dart      # Two-way sync coordinator & conflict resolver
│   │   └── presentation/
│   │       ├── providers/                 # Riverpod notifiers (notes, sync, ai)
│   │       ├── screens/                   # HomeScreen, NoteEditorScreen, AiMemoryScreen
│   │       └── widgets/                   # NoteCard, TagFilterList, SyncBadge
│   └── test/                              # 22 unit & widget tests (100% passing)
├── backend/                               # FastAPI Backend Service
│   ├── app/
│   │   ├── main.py                        # FastAPI entrypoint & router configuration
│   │   ├── core/                          # Settings, Security (bcrypt/JWT), Database
│   │   ├── models/                        # SQLAlchemy 2: User, Note, NoteTag, Embedding, Op
│   │   ├── schemas/                       # Pydantic v2 validation models
│   │   ├── api/v1/endpoints/              # Health, Auth, Notes, Sync, AI Memory
│   │   └── ai/                            # DeterministicEmbedder, GroundedLLM, Retrieval
│   ├── alembic/                           # Database migration scripts
│   ├── scripts/seed_demo_data.py          # Interactive/automated demo database seeder
│   └── tests/                             # 22 pytest suites with TestClient (100% passing)
├── docs/                                  # Engineering Documentation
│   ├── architecture.md                    # System architecture & component responsibilities
│   ├── database.md                        # SQLite & PostgreSQL relational schemas
│   ├── api.md                             # REST API contracts & payloads
│   ├── synchronization.md                 # Two-way sync engine protocol & conflict logic
│   └── decisions/                         # Architecture Decision Records (ADRs 0001 - 0005)
└── README.md
```

---

## 3. Quick Start & Running Locally

### Step 1: Backend Setup & Launch
```bash
cd backend

# Create and activate Python virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run database migrations
alembic upgrade head

# Seed demo user & realistic knowledge base notes
python3 scripts/seed_demo_data.py

# Launch FastAPI development server
uvicorn main:app --reload --port 8000
```
- API Docs: `http://localhost:8000/docs`
- Health check: `http://localhost:8000/api/v1/health`
- Demo user: `demo@pocketbrain.app` / `PocketBrain2026!`

### Step 2: Mobile Setup & Launch
```bash
cd mobile

# Fetch Flutter dependencies
flutter pub get

# Run static analysis (zero warnings)
flutter analyze

# Run mobile application on Linux desktop or connected Android device
flutter run -d linux
# Or Android emulator:
# flutter run -d emulator-5554
```

---

## 4. Automated Testing Verification

Both mobile and backend codebases maintain comprehensive automated test suites with physical verification:

### Backend Test Suite (Pytest)
```bash
cd backend
.venv/bin/pytest -v
```
**Results (22 / 22 Passed)**:
- `test_auth.py`: User registration, duplicate email rejection, JWT login, token expiration, `/me`.
- `test_notes.py`: Note creation with client UUIDs, tag filtering, project filtering, soft-deletion.
- `test_sync.py`: Batch operation push, idempotent re-delivery, version conflict detection, deletion propagation.
- `test_user_isolation.py`: Strict tenant boundary verification (User B cannot read/modify User A's data).
- `test_ai_memory.py`: Grounded queries, verbatim citation verification, anti-hallucination insufficient evidence fallback, SHA-256 stale embedding detection.

### Mobile Test Suite (Flutter)
```bash
cd mobile
flutter --no-version-check test
```
**Results (22 / 22 Passed)**:
- `test/unit/note_entity_test.dart`: Entity serialization, copyWith immutability, JSON conversion.
- `test/unit/notes_repository_test.dart`: SQLite CRUD, transaction safety, full-text search, tag query, archive toggle.
- `test/unit/sync_queue_test.dart`: Local mutation queueing, UUID persistence, pending operation count.
- `test/unit/ai_remote_data_source_test.dart`: Grounded response parsing, citation deserialization, error handling.
- `test/widget/ai_memory_screen_test.dart`: AI query flow, suggestion chips, grounded cards, citation clicks.
- `test/widget_test.dart`: Home screen empty state, note card rendering, pinning, search, and sync indicator.

---

## 5. Synchronization Protocol Specification

| Action | Mobile Behavior | Backend Behavior | Conflict Handling |
| :--- | :--- | :--- | :--- |
| **CREATE** | Enqueues op with client UUID in `sync_operations` | Inserts note with `version=1`; logs in `applied_operations` | Idempotent replay: if `op_id` exists, returns `IGNORED` |
| **UPDATE** | Enqueues op with `client_version` baseline | Verifies `op.client_version == server_version`; increments version | If `server_version > client_version`, returns `CONFLICT` with server note. Client branches local edit to `[Conflict] $title` |
| **DELETE** | Soft-deletes locally (`is_deleted=1`); enqueues op | Sets `is_deleted=True`; increments version | Propagates on pull to remote clients to prevent zombie notes |
| **PULL** | Requests changes since local `watermark` | Queries `WHERE version > since_version AND user_id == current_user` | Returns active notes and soft-deleted records to sync state |

---

## 6. Grounded AI Memory Specification

Unlike generic RAG implementations that hallucinate when notes lack answers, PocketBrain enforces:
1. **Relevance Bar**: Queries require a minimum cosine similarity of `0.25` against tenant notes.
2. **Deterministic Vectorization**: 256-dimensional subword and unigram features with stopword filtering; executes in sub-millisecond time with zero external API dependencies.
3. **Explicit Failure Mode**: When relevance falls below threshold, PocketBrain explicitly returns:
   > *"Insufficient information in your saved notes to answer this question."*
4. **Verifiable Citations**: Every grounded answer includes source note titles, match confidence percentages, and exact verbatim excerpt snippets.

---

## 7. Architecture Decision Records (ADRs)

Detailed architectural justifications are located in `docs/decisions/`:
- [ADR 0001: Project Structure & Phase 1 Foundation](file:///home/lelo/projects/delivery/flutter_application_1/docs/decisions/0001-project-structure-and-phase-1.md)
- [ADR 0002: Offline-First SQLite Architecture](file:///home/lelo/projects/delivery/flutter_application_1/docs/decisions/0002-offline-first-sqlite-architecture.md)
- [ADR 0003: Backend Authentication & Multi-Tenant Isolation](file:///home/lelo/projects/delivery/flutter_application_1/docs/decisions/0003-backend-auth-and-user-isolation.md)
- [ADR 0004: Two-Way Synchronization Engine & Conflict Preservation](file:///home/lelo/projects/delivery/flutter_application_1/docs/decisions/0004-sync-engine-and-conflict-resolution.md)
- [ADR 0005: Grounded Personal AI Memory & Anti-Hallucination Retrieval](file:///home/lelo/projects/delivery/flutter_application_1/docs/decisions/0005-grounded-ai-retrieval.md)

---

## 8. License

PocketBrain is open-source software licensed under the MIT License.
