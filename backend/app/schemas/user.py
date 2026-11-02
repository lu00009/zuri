from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


class UserBase(BaseModel):
    email: str = Field(..., min_length=3, max_length=255, description="User email address")


class UserCreate(UserBase):
    password: str = Field(..., min_length=6, max_length=128, description="User raw password")


class UserResponse(UserBase):
    id: str
    is_active: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
