# ADR 0004: Two-Way Synchronization Engine & Conflict Preservation Strategy

## Status
Accepted

## Context
Phase 4 requires reliable, multi-device synchronization between the Flutter offline SQLite database and the FastAPI server backend. Network operations may be intermittent, duplicate deliveries can happen due to retries, and concurrent edits on distinct devices can lead to conflicts.

## Decisions

1. **Persistent Local Mutation Queue**:
   - Implemented `SyncQueueDataSource` backed by SQLite table `sync_operations`.
   - Every local mutation (`CREATE`, `UPDATE`, `DELETE`) enqueues a record with an invariant client UUID `op_id`.
   - Local mutations survive application crashes, task termination, and device reboots.

2. **Server-Side Idempotency via Operation Logging**:
   - Created `applied_operations` table in PostgreSQL/SQLite.
   - The server inspects incoming `op_id`s before executing mutations. Duplicate delivery resulting from network timeout retries returns `status="IGNORED"` with 200 OK without re-executing or causing duplicate entries.

3. **Optimistic Version Checking & Conflict Preservation**:
   - Each note record maintains an incrementing integer `version`.
   - Client sends its baseline `client_version` on every `UPDATE`.
   - If the server has already progressed to a higher version (`note.version > op.client_version`), the server rejects overwrite and returns `status="CONFLICT"` alongside the authoritative server note.
   - The mobile `SyncEngine` forks the user's conflicting local edits into a sibling note `"[Conflict] ${title} (Local Edit)"` and accepts the server's version as the primary note.
   - **Guarantees zero data loss**: No user thoughts or edits are ever silently overwritten.

4. **Deletion Propagation & Zombie Prevention**:
   - Soft-deletions on the server (`is_deleted=True`) increment `version`.
   - Incremental pull queries (`GET /api/v1/sync/pull?since_version=...`) return deleted records so clients delete them locally, preventing zombie notes from re-appearing.

5. **Visible Sync States**:
   - Real-time status in `HomeScreen`: "Offline Storage Active", "X changes pending sync", "Syncing...", or error states.
   - Pull-to-refresh triggers two-way sync on demand.
