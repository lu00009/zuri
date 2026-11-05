import sys
from pathlib import Path

# Add backend directory to path
backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from app.db.session import SessionLocal
from app.core.security import get_password_hash
from app.models.user import User
from app.models.note import Note, NoteTag
from app.ai.retrieval_service import retrieval_service

DEMO_USER_EMAIL = "demo@pocketbrain.app"
DEMO_USER_PASSWORD = "PocketBrain2026!"

DEMO_NOTES = [
    {
        "id": "demo-note-1",
        "title": "Flutter State Management Architecture",
        "content": (
            "We selected Riverpod 2.x as our primary state management architecture for PocketBrain. "
            "Key advantages include compile-time safety, seamless dependency injection, absence of BuildContext "
            "limitations in business logic, and trivial unit test mocking via ProviderContainer."
        ),
        "project_id": "PocketBrain Core",
        "tags": ["flutter", "architecture", "state-management"],
        "is_pinned": True,
    },
    {
        "id": "demo-note-2",
        "title": "Database & Migrations (SQLite & Alembic)",
        "content": (
            "Database & Migrations: All note mutations are written synchronously to device SQLite first using sqflite. "
            "Backend schema migrations are managed through Alembic and SQLAlchemy ORM. "
            "Local client UUIDs (v4) guarantee zero-roundtrip offline note creation. "
            "A dedicated sync_operations table enqueues pending mutations to ensure no edits are lost across app restarts."
        ),
        "project_id": "PocketBrain Core",
        "tags": ["database", "migrations", "sqlite", "offline-first", "mobile"],
        "is_pinned": True,
    },
    {
        "id": "demo-note-3",
        "title": "Project Decisions & Conflict Preservation",
        "content": (
            "Project Decisions: Silent last-write-wins is strictly forbidden. When the server detects an edit conflict "
            "(client_version < server_version), it rejects the overwrite and returns status CONFLICT. "
            "The client preserves local edits by creating a sibling note '[Conflict] Title (Local Edit)', "
            "ensuring 100% human thought preservation."
        ),
        "project_id": "PocketBrain Core",
        "tags": ["project-decisions", "sync", "distributed-systems", "architecture"],
        "is_pinned": False,
    },
    {
        "id": "demo-note-4",
        "title": "API Tokens & Security Hardening",
        "content": (
            "API Tokens & Security: Backend is implemented in FastAPI (Python 3.12) with SQLAlchemy 2.0 ORM. "
            "Authentication uses short-lived JWT API tokens (15m expiry) and long-lived refresh tokens (30d). "
            "Passwords use bcrypt hashing with salted rounds. Multi-tenant isolation is enforced at query level."
        ),
        "project_id": "PocketBrain Backend",
        "tags": ["api-tokens", "security", "backend", "fastapi", "jwt"],
        "is_pinned": False,
    },
    {
        "id": "demo-note-5",
        "title": "AI Grounded Personal Memory Engine",
        "content": (
            "PocketBrain AI memory strictly grounds answers in the user's private notes. "
            "Embeddings are computed deterministically with sub-millisecond latency. "
            "If evidence falls below the 0.25 similarity threshold, it reports insufficient evidence rather than hallucinating."
        ),
        "project_id": "PocketBrain Core",
        "tags": ["ai", "retrieval", "grounding", "anti-hallucination"],
        "is_pinned": False,
    },
    {
        "id": "demo-note-6",
        "title": "Reading Notes: Designing Data-Intensive Applications",
        "content": (
            "Chapter 5 Notes on Replication and Consensus. In leaderless or multi-leader replication, "
            "conflict resolution requires either CRDTs, version vectors, or explicit conflict preservation. "
            "LWW often silently destroys causal data. Always prefer explicit conflict branches."
        ),
        "project_id": "Personal Reading",
        "tags": ["books", "distributed-systems", "reading"],
        "is_pinned": False,
    },
]


def seed_demo_data():
    db = SessionLocal()
    try:
        # 1. Create or retrieve demo user
        user = db.query(User).filter(User.email == DEMO_USER_EMAIL).first()
        if not user:
            user = User(
                email=DEMO_USER_EMAIL,
                hashed_password=get_password_hash(DEMO_USER_PASSWORD),
                is_active=True,
            )
            db.add(user)
            db.commit()
            db.refresh(user)
            print(f"[+] Created demo user: {DEMO_USER_EMAIL}")
        else:
            print(f"[*] Demo user already exists: {DEMO_USER_EMAIL}")

        # 2. Seed demo notes
        seeded_notes = 0
        for item in DEMO_NOTES:
            existing = db.query(Note).filter(Note.id == item["id"]).first()
            if not existing:
                note = Note(
                    id=item["id"],
                    user_id=user.id,
                    title=item["title"],
                    content=item["content"],
                    project_id=item.get("project_id"),
                    is_pinned=item.get("is_pinned", False),
                    version=1,
                )
                db.add(note)
                for tag_name in item["tags"]:
                    tag = NoteTag(note_id=note.id, tag=tag_name)
                    db.add(tag)
                seeded_notes += 1
            else:
                existing.title = item["title"]
                existing.content = item["content"]
                existing.project_id = item.get("project_id")
                existing.is_pinned = item.get("is_pinned", False)
                db.query(NoteTag).filter(NoteTag.note_id == existing.id).delete()
                for tag_name in item["tags"]:
                    tag = NoteTag(note_id=existing.id, tag=tag_name)
                    db.add(tag)
                seeded_notes += 1

        db.commit()
        print(f"[+] Seeded {seeded_notes} demo notes.")

        # 3. Synchronize vector embeddings
        updated_embeddings = retrieval_service.sync_user_embeddings(db, user.id)
        print(f"[+] Synchronized {updated_embeddings} vector embeddings.")

        print("\n" + "=" * 60)
        print("Demo data seeded successfully!")
        print(f"Credentials:")
        print(f"  Email:    {DEMO_USER_EMAIL}")
        print(f"  Password: {DEMO_USER_PASSWORD}")
        print("=" * 60 + "\n")

    finally:
        db.close()


if __name__ == "__main__":
    seed_demo_data()
