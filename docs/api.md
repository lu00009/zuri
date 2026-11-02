# PocketBrain API Specification

All endpoints are versioned under `/api/v1/`.

## 1. System & Health

### `GET /api/v1/health`
Checks backend operational status, service identifier, and running environment.

**Request:** None
**Response Headers:** `Content-Type: application/json`
**Response Body (200 OK):**
```json
{
  "status": "ok",
  "app": "pocketbrain",
  "version": "0.1.0",
  "environment": "development"
}
```

---

## 2. Authentication & Authorization (Phase 3)

All protected routes require a Bearer token in the `Authorization` header:
`Authorization: Bearer <jwt_access_token>`

### `POST /api/v1/auth/register`
Creates a new user profile.
- Body: `{"email": "user@example.com", "password": "secure_password"}`
- Returns: `201 Created` with user metadata (passwords are hashed using argon2/bcrypt).

### `POST /api/v1/auth/token`
Exchanges user credentials for an access token and refresh token.
- Body: OAuth2 Password flow (`username`, `password`)
- Returns: `{"access_token": "...", "token_type": "bearer", "expires_in": 3600}`

---

## 3. Synchronization (Phase 4)

### `POST /api/v1/sync/push`
Pushes pending client mutation operations.
- Request includes a batch of `SyncOperation` objects with idempotency UUIDs.
- Returns operation status map (`applied`, `conflict`, `ignored`).

### `GET /api/v1/sync/pull?since_version=<version>`
Retrieves all note and tag updates that occurred on the server since `since_version`.
