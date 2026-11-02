# PocketBrain Synchronization Specification

## 1. Principles of Offline-First Design

1. **Local-First Writes**: The user must never be blocked by network availability or latency. Every mutation is written to SQLite immediately.
2. **Stable Identifiers**: Client notes and sync operations are assigned UUIDv4 identifiers at creation time.
3. **Idempotent Mutations**: Each operation carries a unique `op_id`. If a network retry causes duplicate delivery, the server recognizes the operation and avoids duplicate records.
4. **No Destructive Last-Write-Wins**: Conflicting concurrent updates must preserve content rather than silently overwriting either party.

---

## 2. Sync Engine Lifecycle

```
[Local Mutation] 
      │
      ▼
1. Write to SQLite (notes table)
2. Enqueue mutation in sync_operations table
      │
      ▼
[Network Available?]
      ├─ No  --> Stay in queue, retry on network reconnect
      └─ Yes -->
            ▼
3. Batch Push pending operations (POST /api/v1/sync/push)
            ├─ Success (200 OK) -> Mark operations as synced, purge from queue
            ├─ Conflict (409)    -> Fork conflicting content into a conflict note
            └─ Failure (5xx/Net) -> Backoff with jitter, leave in queue
            │
            ▼
4. Incremental Pull (GET /api/v1/sync/pull?since_version=...)
            ├─ Apply remote changes to local SQLite
            └─ Update local highest_server_version watermark
```

---

## 3. Conflict Resolution Strategy

When device A and device B edit the same note offline:
- Device A syncs first: Server note updates to Version 2.
- Device B attempts to sync against Version 1:
  - The server detects a version mismatch.
  - Device B receives a `ConflictResolutionRequired` response containing Server Version 2.
  - PocketBrain preserves Device B's changes by creating a sibling note: `"[Conflict] Note Title (Device B)"` and updating the primary note to Version 2.
  - The user is notified with an in-app banner to review or merge changes manually.
  - **Zero data loss guaranteed.**
