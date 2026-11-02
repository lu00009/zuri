# ADR 0002: Offline-First SQLite Architecture & Local Notes

## Status
Accepted

## Context
Phase 2 requires an offline-first personal knowledge storage layer in Flutter where users can create, edit, search, pin, and archive notes with zero latency and zero dependency on a network connection.

## Decisions

1. **Local Storage Engine**:
   - Selected `sqflite` for Android/iOS native SQLite bindings, complemented by `sqflite_common_ffi` for Linux desktop and deterministic test environments.
   - Database operations run against an isolated SQLite database file (`pocketbrain.db`).

2. **Schema & Normalization**:
   - Used UUIDv4 identifiers for client-side note creation to avoid collision during offline operations.
   - Designed a normalized `note_tags` table for tags to enable efficient relational filtering without comma-separated string hacks.
   - Added `sync_operations` queue table to record mutations for subsequent sync phases.
   - Indexed `updated_at`, `is_pinned`, and `is_archived` to ensure fast querying and sorting.

3. **State Management**:
   - Used `StateNotifier` (`NotesListNotifier`) for clean, unidirectional state flow.
   - Exposed `NotesRepository` via a Riverpod `Provider` to permit swapping with `FakeNotesRepository` in unit and widget test environments.

## Consequences
- Fast local read and write operations that work completely offline.
- High testability: All unit tests execute directly in-memory using SQLite FFI, while widget tests run deterministically with in-memory test doubles.
