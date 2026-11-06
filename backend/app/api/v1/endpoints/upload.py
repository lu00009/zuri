from __future__ import annotations

import base64
import logging
from typing import Any
from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile, status
from pydantic import BaseModel
import cloudinary
import cloudinary.uploader

from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()


def _configure_cloudinary() -> bool:
    """Configures Cloudinary SDK from environment settings."""
    if settings.CLOUDINARY_URL and settings.CLOUDINARY_URL.strip():
        cloudinary.config(cloudinary_url=settings.CLOUDINARY_URL.strip())
        return True
    elif settings.CLOUDINARY_CLOUD_NAME and settings.CLOUDINARY_CLOUD_NAME.strip():
        cloudinary.config(
            cloud_name=settings.CLOUDINARY_CLOUD_NAME.strip(),
            api_key=settings.CLOUDINARY_API_KEY.strip() if settings.CLOUDINARY_API_KEY else None,
            api_secret=settings.CLOUDINARY_API_SECRET.strip() if settings.CLOUDINARY_API_SECRET else None,
        )
        return True
    return False


def _get_cloud_name() -> str:
    if settings.CLOUDINARY_CLOUD_NAME:
        return settings.CLOUDINARY_CLOUD_NAME.strip()
    if settings.CLOUDINARY_URL:
        try:
            return settings.CLOUDINARY_URL.split("@")[-1].strip()
        except Exception:
            pass
    return ""


class ImageUploadRequest(BaseModel):
    image: str  # Base64 data URI (data:image/...;base64,...) or URL
    folder: str | None = "zuri_folders"


class ImageUploadResponse(BaseModel):
    url: str
    secure_url: str
    public_id: str | None = None
    is_cloudinary: bool = False


@router.get("/config")
def get_upload_config() -> dict[str, Any]:
    """
    Returns client-facing upload configuration so frontend can use Cloudinary
    from backend .env settings.
    """
    cloud_name = _get_cloud_name()
    is_configured = bool(settings.CLOUDINARY_URL or settings.CLOUDINARY_CLOUD_NAME)
    return {
        "configured": is_configured,
        "cloud_name": cloud_name,
        "upload_preset": settings.CLOUDINARY_UPLOAD_PRESET or "zuri_folders",
    }


@router.post("/image", response_model=ImageUploadResponse)
async def upload_image(
    request: Request,
    payload: ImageUploadRequest | None = None,
) -> ImageUploadResponse:
    """
    Uploads an image (base64 data URI or multipart) to Cloudinary using .env credentials.
    Falls back gracefully if Cloudinary credentials are not configured.
    """
    image_data: str | None = None
    folder = "zuri_folders"

    # Support JSON payload
    if payload and payload.image:
        image_data = payload.image
        if payload.folder:
            folder = payload.folder
    else:
        # Support multipart form upload or raw json body
        try:
            content_type = request.headers.get("content-type", "")
            if "application/json" in content_type:
                body = await request.json()
                image_data = body.get("image") or body.get("file")
                folder = body.get("folder", folder)
            elif "multipart/form-data" in content_type:
                form = await request.form()
                folder = form.get("folder", folder)
                file_field = form.get("file") or form.get("image")
                if isinstance(file_field, UploadFile):
                    file_bytes = await file_field.read()
                    b64 = base64.b64encode(file_bytes).decode("utf-8")
                    content_type = file_field.content_type or "image/jpeg"
                    image_data = f"data:{content_type};base64,{b64}"
                elif isinstance(file_field, str):
                    image_data = file_field
        except Exception as e:
            logger.warning("Error parsing upload request: %s", e)

    if not image_data or not image_data.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Image data is required (base64 data URI or file)",
        )

    # Attempt upload using Cloudinary SDK if configured
    is_configured = _configure_cloudinary()
    if is_configured:
        try:
            upload_result = cloudinary.uploader.upload(
                image_data,
                folder=folder,
                resource_type="image",
            )
            secure_url = upload_result.get("secure_url") or upload_result.get("url")
            public_id = upload_result.get("public_id")
            if secure_url:
                return ImageUploadResponse(
                    url=secure_url,
                    secure_url=secure_url,
                    public_id=public_id,
                    is_cloudinary=True,
                )
        except Exception as err:
            logger.error("Cloudinary upload failed: %s. Using fallback data URI.", err)

    # Fallback: Return the data URI so user image is never lost and always displays
    return ImageUploadResponse(
        url=image_data,
        secure_url=image_data,
        public_id=None,
        is_cloudinary=False,
    )

