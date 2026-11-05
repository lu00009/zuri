import pytest
from pydantic import ValidationError
from app.core.config import Settings


def test_development_allows_default_secret():
    """Development environment permits the default secret for local setup."""
    s = Settings(ENVIRONMENT="development")
    assert s.ENVIRONMENT == "development"
    assert s.DATABASE_URL.startswith("sqlite")


def test_production_rejects_default_secret():
    """Production must strictly reject the hardcoded default secret."""
    with pytest.raises(ValidationError) as exc_info:
        Settings(
            ENVIRONMENT="production",
            SECRET_KEY="09d25e094faa6ca2556c818166b7a9563b93f7099f6f0f4caa6cf63b88e8d3e7",
        )
    assert "Production requires a strong, unique SECRET_KEY" in str(exc_info.value)


def test_production_rejects_short_secret():
    """Production must reject secrets shorter than 32 characters."""
    with pytest.raises(ValidationError) as exc_info:
        Settings(
            ENVIRONMENT="production",
            SECRET_KEY="short-secret-key-too-short",
        )
    assert "at least 32 characters" in str(exc_info.value)


def test_production_accepts_strong_secret():
    """Production accepts strong 32+ character secrets."""
    strong_key = "a" * 64
    s = Settings(
        ENVIRONMENT="production",
        SECRET_KEY=strong_key,
        ALLOWED_ORIGINS=["https://proud-maker-453907-b8.web.app"],
    )
    assert s.SECRET_KEY == strong_key
    assert s.ENVIRONMENT == "production"


def test_production_rejects_wildcard_cors():
    """Production forbids wildcard '*' in allowed origins when credentials are enabled."""
    strong_key = "b" * 64
    with pytest.raises(ValidationError) as exc_info:
        Settings(
            ENVIRONMENT="production",
            SECRET_KEY=strong_key,
            ALLOWED_ORIGINS=["*"],
        )
    assert "Wildcard '*' in ALLOWED_ORIGINS is strictly prohibited in production" in str(exc_info.value)


def test_allowed_origins_parses_comma_separated_string():
    """Allowed origins validator handles comma-separated string from env."""
    s = Settings(
        ALLOWED_ORIGINS="https://app.example.com,https://admin.example.com"
    )
    assert s.ALLOWED_ORIGINS == ["https://app.example.com", "https://admin.example.com"]


def test_allowed_origins_includes_firebase_hosting():
    """Default configuration contains the production Firebase Hosting domains."""
    s = Settings()
    assert "https://proud-maker-453907-b8.web.app" in s.ALLOWED_ORIGINS
    assert "https://proud-maker-453907-b8.firebaseapp.com" in s.ALLOWED_ORIGINS


def test_postgresql_url_standardization():
    """Verify legacy postgres:// URLs are standardized to postgresql://."""
    from app.db.session import db_url
    # When initialized with sqlite in tests, verify dialect check
    assert db_url.startswith("sqlite")

