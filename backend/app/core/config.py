from typing import Any
from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "PocketBrain API"
    VERSION: str = "0.1.0"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = "development"

    # Database configuration
    # Default to local SQLite for frictionless local development, or PostgreSQL in staging/production
    DATABASE_URL: str = "sqlite:///./pocketbrain.db"

    # PostgreSQL Connection Pooling settings (ignored for SQLite)
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20
    DB_POOL_TIMEOUT: int = 30
    DB_POOL_RECYCLE: int = 300

    # Security & JWT Token configuration
    # In development/test a default is tolerated; in production a strong 32+ char secret must be provided
    SECRET_KEY: str = (
        "09d25e094faa6ca2556c818166b7a9563b93f7099f6f0f4caa6cf63b88e8d3e7"
    )
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 24 hours
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # CORS Allowed Origins (accepts JSON array or comma-separated string)
    ALLOWED_ORIGINS: list[str] | str = [
        "http://localhost:3000",
        "http://localhost:8000",
        "http://localhost:8080",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8000",
        "http://127.0.0.1:8080",
        "https://proud-maker-453907-b8.web.app",
        "https://proud-maker-453907-b8.firebaseapp.com",
    ]

    # Cloudinary configuration
    CLOUDINARY_URL: str | None = None
    CLOUDINARY_CLOUD_NAME: str | None = None
    CLOUDINARY_API_KEY: str | None = None
    CLOUDINARY_API_SECRET: str | None = None
    CLOUDINARY_UPLOAD_PRESET: str = "zuri_folders"

    # SMTP / Gmail Verification configuration
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USER: str | None = None
    SMTP_PASSWORD: str | None = None
    SMTP_FROM_EMAIL: str | None = None
    SMTP_FROM_NAME: str = "Zuri"

    # Google OAuth configuration
    GOOGLE_CLIENT_ID: str | None = None

    model_config = SettingsConfigDict(
        env_file=(".env", "backend/.env"),
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    @field_validator("ALLOWED_ORIGINS", mode="after")
    @classmethod
    def ensure_allowed_origins_list(cls, v: Any) -> list[str]:
        if isinstance(v, str):
            v_stripped = v.strip()
            if v_stripped.startswith("[") and v_stripped.endswith("]"):
                import json

                try:
                    return json.loads(v_stripped)
                except Exception:
                    pass
            return [
                origin.strip()
                for origin in v_stripped.split(",")
                if origin.strip()
            ]
        elif isinstance(v, (list, tuple)):
            return [str(item).strip() for item in v if str(item).strip()]
        return []

    @model_validator(mode="after")
    def resolve_integrations(self) -> "Settings":
        # Cloudinary resolution
        if self.CLOUDINARY_URL and not (self.CLOUDINARY_CLOUD_NAME and self.CLOUDINARY_API_KEY and self.CLOUDINARY_API_SECRET):
            try:
                import re
                match = re.match(r"^cloudinary:\/\/([^:]+):([^@]+)@(.+)$", self.CLOUDINARY_URL.strip())
                if match:
                    if not self.CLOUDINARY_API_KEY:
                        self.CLOUDINARY_API_KEY = match.group(1)
                    if not self.CLOUDINARY_API_SECRET:
                        self.CLOUDINARY_API_SECRET = match.group(2)
                    if not self.CLOUDINARY_CLOUD_NAME:
                        self.CLOUDINARY_CLOUD_NAME = match.group(3)
            except Exception:
                pass
        elif self.CLOUDINARY_CLOUD_NAME and self.CLOUDINARY_API_KEY and self.CLOUDINARY_API_SECRET and not self.CLOUDINARY_URL:
            self.CLOUDINARY_URL = f"cloudinary://{self.CLOUDINARY_API_KEY}:{self.CLOUDINARY_API_SECRET}@{self.CLOUDINARY_CLOUD_NAME}"

        # SMTP fallback aliases from environment
        import os
        if not self.SMTP_USER:
            self.SMTP_USER = os.getenv("GMAIL_USER") or os.getenv("MAIL_USERNAME") or os.getenv("SMTP_USERNAME")
        if not self.SMTP_PASSWORD:
            self.SMTP_PASSWORD = (
                os.getenv("GMAIL_PASSWORD")
                or os.getenv("GMAIL_APP_PASSWORD")
                or os.getenv("MAIL_PASSWORD")
                or os.getenv("SMTP_PASS")
            )
        if not self.SMTP_FROM_EMAIL and self.SMTP_USER:
            self.SMTP_FROM_EMAIL = self.SMTP_USER

        return self

    @model_validator(mode="after")
    def validate_production_settings(self) -> "Settings":
        env_lower = self.ENVIRONMENT.lower()
        if env_lower == "production":
            insecure_default = (
                "09d25e094faa6ca2556c818166b7a9563b93f7099f6f0f4caa6cf63b88e8d3e7"
            )
            if (
                not self.SECRET_KEY
                or self.SECRET_KEY == insecure_default
                or len(self.SECRET_KEY) < 32
            ):
                raise ValueError(
                    "Production requires a strong, unique SECRET_KEY (at least 32 characters) "
                    "configured via environment variables or secret manager."
                )
            if "*" in self.ALLOWED_ORIGINS:
                raise ValueError(
                    "Wildcard '*' in ALLOWED_ORIGINS is strictly prohibited in production when credentials are enabled."
                )
        return self


settings = Settings()
