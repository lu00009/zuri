from fastapi import APIRouter
from app.api.v1.endpoints import ai, auth, health, notes, sync

api_router = APIRouter()
api_router.include_router(health.router, tags=["Health"])
api_router.include_router(auth.router, prefix="/auth", tags=["Authentication"])
api_router.include_router(notes.router, prefix="/notes", tags=["Notes"])
api_router.include_router(sync.router, prefix="/sync", tags=["Synchronization"])
api_router.include_router(ai.router, prefix="/ai", tags=["AI Memory"])
