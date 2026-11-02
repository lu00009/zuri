# ADR 0001: Project Structure and Phase 1 Foundation

## Status
Accepted

## Context
The project needs to implement PocketBrain, an offline-first personal knowledge application consisting of a Flutter mobile client (targeting Android) and a Python FastAPI backend. Previously, the workspace contained an untracked food-delivery starter app with no backend or automated tests.

## Decisions

1. **Repository Structure**:
   - Organized the workspace into isolated sub-projects: `mobile/` for Flutter, `backend/` for FastAPI, and `docs/` for architectural specifications.
   - Flutter and Python dependencies are strictly isolated. Python uses a dedicated `.venv/` virtual environment, while Flutter uses standard Dart pub management.

2. **State Management & Routing**:
   - Selected `flutter_riverpod` (v2.6.x) for predictable, testable, compile-safe dependency injection and state management.
   - Selected `go_router` (v14.x) for declarative routing.

3. **Backend Framework & Health Endpoint**:
   - Selected `FastAPI` with `Pydantic v2` and `pydantic-settings` for type-safe environment and schema handling.
   - Implemented a standardized health endpoint at `GET /api/v1/health` returning application identity, version, and operational status.
   - Configured `pytest` with `fastapi.testclient.TestClient` for automated regression testing.

## Consequences
- Clean separation allows independent testing and development of frontend and backend.
- Full testing can be executed independently in each subsystem (`flutter test` and `pytest`).
