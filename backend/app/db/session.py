import logging
from collections.abc import Generator
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from app.core.config import settings

logger = logging.getLogger(__name__)


def get_normalized_db_url(raw_url: str) -> str:
    """
    Normalizes database connection URL for PostgreSQL and Neon.
    - Replaces legacy postgres:// prefix with postgresql://
    - Enforces sslmode=require for Neon serverless PostgreSQL endpoints
    """
    url = raw_url.strip()
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)

    # Neon serverless PostgreSQL requires SSL
    if "neon.tech" in url and "sslmode=" not in url:
        separator = "&" if "?" in url else "?"
        url = f"{url}{separator}sslmode=require"

    return url


db_url = get_normalized_db_url(settings.DATABASE_URL)

engine_kwargs: dict = {"pool_pre_ping": True}

if db_url.startswith("sqlite"):
    engine_kwargs["connect_args"] = {"check_same_thread": False}
else:
    # PostgreSQL / Neon Connection Pooling for production resilience
    engine_kwargs["pool_size"] = settings.DB_POOL_SIZE
    engine_kwargs["max_overflow"] = settings.DB_MAX_OVERFLOW
    engine_kwargs["pool_timeout"] = settings.DB_POOL_TIMEOUT
    # Neon serverless compute suspends after inactivity;
    # recycling connections every 120s avoids stale connection drops
    engine_kwargs["pool_recycle"] = min(settings.DB_POOL_RECYCLE, 120)

engine = create_engine(db_url, **engine_kwargs)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db() -> Generator[Session, None, None]:
    """Dependency that provides a database session and guarantees closure/rollback on failure."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

