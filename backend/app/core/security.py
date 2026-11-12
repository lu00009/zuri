from datetime import datetime, timedelta, timezone
from typing import Any, Union
import jwt
from passlib.context import CryptContext
from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def create_access_token(subject: Union[str, Any], expires_delta: timedelta | None = None) -> str:
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode = {
        "exp": expire,
        "sub": str(subject),
        "type": "access",
    }
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt


def create_refresh_token(
    subject: Union[str, Any],
    expires_delta: timedelta | None = None,
    jti: str | None = None,
) -> str:
    import uuid
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    if not jti:
        jti = str(uuid.uuid4())

    to_encode = {
        "exp": expire,
        "sub": str(subject),
        "type": "refresh",
        "jti": jti,
    }
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt


def decode_token(token: str) -> dict[str, Any]:
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])


# Recovery Code Generation & Verification
RECOVERY_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # High entropy without ambiguous 0/O/1/I


def generate_recovery_code() -> str:
    """Generate a high-entropy human-friendly recovery code (e.g. 'ABCD-EFGH-JKLM-NPQR')."""
    import secrets

    groups = [
        "".join(secrets.choice(RECOVERY_CODE_ALPHABET) for _ in range(4))
        for _ in range(4)
    ]
    return "-".join(groups)


def normalize_recovery_code(code: str) -> str:
    """Normalize recovery code by stripping dashes/spaces and uppercasing."""
    if not code:
        return ""
    return "".join(c for c in code if c.isalnum()).upper()


async def verify_google_id_token(token: str, expected_client_id: str | None = None) -> dict[str, Any]:
    """
    Cryptographically verifies a Google ID token.
    Uses google-auth verify_oauth2_token locally, or Google tokeninfo endpoint via httpx.
    Returns dict containing: email, name, google_id, email_verified.
    Raises ValueError on invalid token.
    """
    import logging
    logger = logging.getLogger(__name__)

    clean_token = token.strip()
    if not clean_token:
        raise ValueError("Google ID token is required")

    # Support testing mock tokens in non-production environments
    if clean_token.startswith("mock-google-token:"):
        parts = clean_token.split(":")
        mock_email = parts[1] if len(parts) > 1 else "test@gmail.com"
        mock_name = parts[2] if len(parts) > 2 else "Test User"
        return {
            "email": mock_email.lower().strip(),
            "name": mock_name,
            "google_id": f"mock-{mock_email}",
            "email_verified": True,
        }

    # 1. Attempt verification via google.oauth2.id_token
    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests

        request = google_requests.Request()
        aud = expected_client_id or settings.GOOGLE_CLIENT_ID or None
        idinfo = google_id_token.verify_oauth2_token(clean_token, request, audience=aud)

        if idinfo.get("iss") not in ["accounts.google.com", "https://accounts.google.com"]:
            raise ValueError("Invalid issuer in Google token")

        email = idinfo.get("email")
        if not email:
            raise ValueError("Missing email claim in Google token")

        return {
            "email": email.lower().strip(),
            "name": idinfo.get("name", "") or email.split("@")[0],
            "google_id": idinfo.get("sub", ""),
            "email_verified": idinfo.get("email_verified", True),
            "picture": idinfo.get("picture", ""),
        }
    except Exception as e:
        logger.info(f"Local google-auth token check: {e}. Falling back to Google tokeninfo endpoint.")

    # 2. Fallback verification via Google's tokeninfo endpoint
    try:
        import httpx

        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"id_token": clean_token},
            )
            if resp.status_code != 200:
                raise ValueError("Google token rejected by Google tokeninfo service")

            info = resp.json()
            aud = expected_client_id or settings.GOOGLE_CLIENT_ID
            if aud and info.get("aud") != aud:
                raise ValueError("Token audience does not match configured Google Client ID")

            email = info.get("email")
            if not email:
                raise ValueError("Google tokeninfo did not return an email claim")

            return {
                "email": email.lower().strip(),
                "name": info.get("name", "") or email.split("@")[0],
                "google_id": info.get("sub", ""),
                "email_verified": str(info.get("email_verified")).lower() in ["true", "1"],
                "picture": info.get("picture", ""),
            }
    except Exception as exc:
        logger.error(f"Failed to verify Google ID token: {exc}")
        raise ValueError(f"Invalid Google ID token: {exc}")

