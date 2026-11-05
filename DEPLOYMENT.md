# PocketBrain — Production Deployment & Environment Guide

This guide details the steps and environment configuration required to deploy PocketBrain in production across the **FastAPI backend** and the **Flutter Web frontend (Firebase Hosting)** while preserving its offline-first architecture.

---

## 1. Environment Architecture & Overview

| Component | Target Platform / Host | Configuration Source | Default (Dev) | Production Target |
|---|---|---|---|---|
| **Backend API** | Container / Linux VM / PaaS | `backend/.env` & OS Env | SQLite (`sqlite:///./pocketbrain.db`) | PostgreSQL (`postgresql+psycopg://...`) |
| **Frontend Web** | Firebase Hosting (`proud-maker-453907-b8`) | `--dart-define=API_BASE_URL` | `http://localhost:8000/api/v1` | `https://<backend-domain>/api/v1` |
| **Android Mobile** | Android Emulator / Physical Device | Auto-resolved / `--dart-define` | `http://10.0.2.2:8000/api/v1` | `https://<backend-domain>/api/v1` |
| **Desktop / iOS** | Local Linux / macOS / Windows / iOS | Auto-resolved / `--dart-define` | `http://localhost:8000/api/v1` | `https://<backend-domain>/api/v1` |

---

## 2. Backend Environment Variables (`backend/.env`)

All configuration is parsed and validated using Pydantic Settings in `backend/app/core/config.py`.

### Supported Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `ENVIRONMENT` | string | `development` | Runtime environment (`development`, `staging`, `production`). In `production`, strict secret checks are enforced. |
| `PROJECT_NAME` | string | `PocketBrain API` | OpenAPI & application title. |
| `VERSION` | string | `0.1.0` | Application release version. |
| `API_V1_STR` | string | `/api/v1` | API routing prefix. |
| `DATABASE_URL` | string | `sqlite:///./pocketbrain.db` | SQLAlchemy connection URL (SQLite for dev, PostgreSQL for production). |
| `DB_POOL_SIZE` | integer | `10` | PostgreSQL connection pool size. |
| `DB_MAX_OVERFLOW`| integer | `20` | Max overflow connections beyond pool size. |
| `DB_POOL_TIMEOUT` | integer | `30` | Seconds to wait before timing out on connection checkout. |
| `DB_POOL_RECYCLE` | integer | `300` | Seconds after which idle connections are recycled. |
| `SECRET_KEY` | string | *dev key* | **Required in production.** Min 32 characters (e.g., 64-char hex generated via `openssl rand -hex 32`). |
| `ALGORITHM` | string | `HS256` | JWT signing algorithm. |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | integer | `1440` (24h) | Access token lifetime in minutes. |
| `REFRESH_TOKEN_EXPIRE_DAYS` | integer | `30` | Refresh token lifetime in days. |
| `ALLOWED_ORIGINS` | string / list | *dev + firebase* | Comma-separated list or JSON array of allowed CORS origins. |

### Production Validation Rules
When `ENVIRONMENT=production`:
1. `SECRET_KEY` cannot be the development default or shorter than 32 characters.
2. `ALLOWED_ORIGINS` cannot contain the wildcard `'*'` while credentials are enabled.
3. Automatic table generation (`Base.metadata.create_all()`) is disabled; database migrations must be applied using Alembic.

---

## 3. PostgreSQL Database Configuration

### 1. Connection String Format
SQLAlchemy 2 uses the `psycopg` v3 driver. Supply the connection string in either format:
```bash
DATABASE_URL="postgresql+psycopg://username:password@db-host.internal:5432/pocketbrain_db"
```
*(Legacy `postgres://` URLs supplied by cloud providers like Heroku, Railway, or Supabase are automatically standardized to `postgresql://` at startup.)*

### 2. Running Database Migrations
Always run Alembic migrations prior to starting the production backend:
```bash
cd backend
.venv/bin/alembic upgrade head
```

---

## 4. Backend Production Deployment

### Recommended Execution: Gunicorn + Uvicorn Workers
```bash
cd backend
gunicorn app.main:app \
  --workers 4 \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000 \
  --access-logfile - \
  --error-logfile -
```

### Health Check Verification
```bash
curl -f https://<your-backend-domain>/api/v1/health
# Expected Response:
# {"status":"ok","app":"pocketbrain","version":"0.1.0","environment":"production"}
```

---

## 5. CORS Configuration

To allow secure cross-origin requests from the Flutter Web app hosted on Firebase, configure `ALLOWED_ORIGINS`:

```bash
ALLOWED_ORIGINS="https://proud-maker-453907-b8.web.app,https://proud-maker-453907-b8.firebaseapp.com"
```

The backend explicitly rejects wildcard (`*`) origins when `ENVIRONMENT=production` to uphold browser credential security standards (RFC 6454 / W3C CORS specification).

---

## 6. Flutter Web Production Build & Firebase Hosting

### 1. Web Compilation with Injected API Base URL
In production release builds, Flutter Web **never** defaults to `localhost`. You must inject your live backend domain using `--dart-define=API_BASE_URL=...`:

```bash
cd mobile
flutter build web --release --dart-define=API_BASE_URL=https://<your-backend-domain>/api/v1
```

The compiled output will be generated in `mobile/build/web`.

### 2. Firebase Hosting Configuration (`mobile/firebase.json`)
The repository is pre-configured for the Firebase project `proud-maker-453907-b8`:
- Public directory: `build/web`
- SPA rewrites enabled: all routes forward to `/index.html`

### 3. Deploy to Firebase Hosting
```bash
cd mobile
firebase deploy --only hosting
```
*(Or specify site: `firebase deploy --only hosting:proud-maker-453907-b8`)*

---

## 7. Security Best Practices Checklist

- [x] **No Secrets in Source**: `.env` and `.env.*` (except `.env.example`) are in `.gitignore`.
- [x] **Secure Random JWT Keys**: Generated via `openssl rand -hex 32`.
- [x] **Token Storage**: `flutter_secure_storage` uses Keystore on Android, Keychain on iOS, and Web Cryptography API on Web.
- [x] **No Localhost in Web Release**: `ApiClient.getDefaultBaseUrl()` throws `StateError` if `API_BASE_URL` is omitted during a release Web build.
- [x] **CORS Guard**: Wildcard CORS with `allow_credentials=True` is prohibited in production.
- [x] **PostgreSQL Pooling**: `pool_pre_ping=True`, `pool_recycle=300`, and configurable `pool_size` protect against connection leaks and idle disconnections.
- [x] **Multi-Tenant Isolation**: Every note, mutation, embedding search, and conversation query is strictly user-scoped with foreign-key guarantees.

