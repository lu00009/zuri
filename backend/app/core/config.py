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

    model_config = SettingsConfigDict(
        env_file=".env",
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
