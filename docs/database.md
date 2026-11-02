# PocketBrain Database Specification

## 1. Local SQLite Schema (Mobile)

All records generated offline utilize UUIDv4 primary keys to ensure collision-free generation without server roundtrips.

### `notes`
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | TEXT | PRIMARY KEY | Client-generated UUIDv4 |
| `title` | TEXT | NOT NULL | Title or short excerpt |
| `content` | TEXT | NOT NULL DEFAULT '' | Markdown body text |
| `project_id` | TEXT | NULL, REFERENCES `projects(id)` | Optional project grouping |
| `is_pinned` | INTEGER | NOT NULL DEFAULT 0 | 1 = pinned to top |
| `is_archived` | INTEGER | NOT NULL DEFAULT 0 | 1 = moved to archive |
| `is_deleted` | INTEGER | NOT NULL DEFAULT 0 | Soft-deletion flag |
| `client_updated_at` | INTEGER | NOT NULL | Unix epoch timestamp (ms) |
| `server_version` | INTEGER | NOT NULL DEFAULT 0 | Server synchronization version |

### `sync_operations`
| Column | Type | Constraints | Description |
|---|---|---|---|
| `op_id` | TEXT | PRIMARY KEY | Stable mutation identifier (UUID) |
| `entity_type` | TEXT | NOT NULL | e.g. `'note'`, `'tag'`, `'project'` |
| `entity_id` | TEXT | NOT NULL | Target entity UUID |
| `op_type` | TEXT | NOT NULL | `'CREATE'`, `'UPDATE'`, `'DELETE'` |
| `payload` | TEXT | NOT NULL | JSON string representation of mutation |
| `created_at` | INTEGER | NOT NULL | Timestamp when operation occurred |
| `attempts` | INTEGER | NOT NULL DEFAULT 0 | Number of push attempts |
| `last_error` | TEXT | NULL | Last error string if failed |

---

## 2. Server PostgreSQL Schema (FastAPI)

Enforces strict user isolation via `user_id` on every private record.

### `users`
- `id` (UUID, PK)
- `email` (VARCHAR(255), UNIQUE, INDEX)
- `hashed_password` (VARCHAR(255), NOT NULL)
- `created_at` (TIMESTAMPTZ, NOT NULL)

### `notes`
- `id` (UUID, PK)
- `user_id` (UUID, FK -> `users(id)`, INDEX)
- `title` (VARCHAR(500), NOT NULL)
- `content` (TEXT, NOT NULL)
- `is_pinned` (BOOLEAN, DEFAULT FALSE)
- `is_archived` (BOOLEAN, DEFAULT FALSE)
- `is_deleted` (BOOLEAN, DEFAULT FALSE)
- `version` (BIGINT, DEFAULT 1)
- `created_at` (TIMESTAMPTZ, NOT NULL)
- `updated_at` (TIMESTAMPTZ, NOT NULL)
- `deleted_at` (TIMESTAMPTZ, NULL)

### Indexes and Integrity Constraints
- Unique index on `(user_id, id)`
- Index on `(user_id, updated_at)` for incremental synchronization queries
- Soft-deletion prevents foreign key cascading anomalies during active sync
