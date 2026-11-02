from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str = Field(default="ok", description="Overall health status")
    app: str = Field(default="pocketbrain", description="Application identifier")
    version: str = Field(..., description="Application version")
    environment: str = Field(default="development", description="Runtime environment")
