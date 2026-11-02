from fastapi import APIRouter
from app.core.config import settings
from app.schemas.health import HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse, summary="Service Health Check")
def get_health() -> HealthResponse:
    """Return application operational status, name, version, and environment."""
    return HealthResponse(
        status="ok",
        app="pocketbrain",
        version=settings.VERSION,
        environment=settings.ENVIRONMENT,
    )
