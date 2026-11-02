# ADR 0003: Backend Authentication, PostgreSQL / SQLite Schemas & Multi-Tenant User Isolation

## Status
Accepted

## Context
Phase 3 requires implementing the server-side architecture for PocketBrain, including relational models, database migrations with Alembic, user authentication with password hashing and JWT token lifecycles, and strict per-user authorization to prevent unauthorized cross-tenant data access.

## Decisions

1. **Relational Models & SQLAlchemy 2**:
   - Defined `User`, `Note`, and `NoteTag` models using SQLAlchemy 2 `Mapped` declarations.
   - Enforced client-side UUID primary keys on `notes` to ensure consistency with offline mobile creation.
   - Enforced foreign key `user_id` referencing `users(id)` with cascading deletion.

2. **Schema Migration with Alembic**:
   - Initialized and configured Alembic migrations in `backend/alembic`.
   - Connected `target_metadata` to `Base.metadata` and applied initial schema migration (`0001_initial_schema.py`).

3. **Authentication & Token Lifecycle**:
   - Passwords hashed using bcrypt via `passlib.context.CryptContext`.
   - Access tokens (JWT HS256, 24-hour expiration) and Refresh tokens (JWT HS256, 30-day expiration).
   - OAuth2 Password Flow compatibility for standard API clients.

4. **Strict User Isolation**:
   - All note endpoints (`GET`, `POST`, `PUT`, `DELETE`) require `get_current_user`.
   - Every database query explicitly filters by `Note.user_id == current_user.id`.
   - If User B attempts to access User A's note by ID, the API returns a strict `404 Not Found` (preventing both data leakage and ID enumeration).

5. **Flutter Mobile Integration**:
   - Integrated `dio` (v5.x) and `flutter_secure_storage` (v11.x) in `mobile/`.
   - Configured `ApiClient` with request interceptor automatically attaching the Bearer token.
   - Built `AuthRemoteDataSource` and `NotesRemoteDataSource`.

## Consequences
- Verified complete isolation between users with automated tests.
- Offline notes created on mobile devices with UUIDs can be pushed directly without ID conflicts.
