from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.v1.api import api_router
from app.db.base import Base
from app.db.session import engine
import app.models  # noqa: F401

# Auto-create tables if missing on startup and ensure columns exist
try:
    Base.metadata.create_all(bind=engine)
    from sqlalchemy import text
    with engine.connect() as conn:
        url_str = str(engine.url).lower()
        if "postgresql" in url_str or "postgres" in url_str:
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS recovery_code_hash VARCHAR(255);"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(255);"))
            conn.commit()
        elif "sqlite" in url_str:
            cols = [row[1] for row in conn.execute(text("PRAGMA table_info(users)")).fetchall()]
            if cols and "recovery_code_hash" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN recovery_code_hash VARCHAR(255);"))
            if cols and "google_id" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN google_id VARCHAR(255);"))
            conn.commit()
except Exception as e:
    import logging
    logging.getLogger(__name__).warning("Database initialization note: %s", e)

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="PocketBrain - Offline-first personal knowledge and synchronization backend API.",
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=f"{settings.API_V1_STR}/docs",
    redoc_url=f"{settings.API_V1_STR}/redoc",
)

# Configurable CORS with production origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.API_V1_STR)


@app.get("/", include_in_schema=False)
def root_redirect():
    return {
        "app": "PocketBrain API",
        "docs": f"{settings.API_V1_STR}/docs",
        "health": f"{settings.API_V1_STR}/health",
    }
