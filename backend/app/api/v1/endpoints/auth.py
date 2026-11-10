import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.config import settings
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_password_hash,
    verify_password,
)
from app.db.session import get_db
from app.models.password_reset import PasswordResetToken
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.schemas.token import (
    ForgotPasswordRequest,
    ForgotPasswordResponse,
    GoogleAuthRequest,
    LogoutRequest,
    RefreshTokenRequest,
    ResetPasswordRequest,
    ResetPasswordResponse,
    Token,
)
from app.schemas.user import UserCreate, UserResponse
from app.services.email_service import send_verification_email

router = APIRouter()


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register(
    user_in: UserCreate,
    db: Annotated[Session, Depends(get_db)],
) -> UserResponse:
    """Register a new user account."""
    existing = db.query(User).filter(User.email == user_in.email.lower()).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email address already exists.",
        )

    user = User(
        email=user_in.email.lower(),
        name=user_in.name,
        hashed_password=get_password_hash(user_in.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return UserResponse.model_validate(user)


@router.post("/login", response_model=Token)
async def login_for_access_token(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> Token:
    """OAuth2 and JSON compatible token login, returning access and refresh tokens."""
    username: str | None = None
    password: str | None = None

    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        try:
            body = await request.json()
            username = body.get("email") or body.get("username")
            password = body.get("password")
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid JSON payload",
            )
    else:
        try:
            form = await request.form()
            username = form.get("username") or form.get("email")
            password = form.get("password")
        except Exception:
            pass

    if not username or not password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incorrect email or password",
        )

    user = db.query(User).filter(User.email == username.lower()).first()
    if not user or not verify_password(password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incorrect email or password",
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Inactive user profile",
        )

    jti = str(uuid.uuid4())
    access_token = create_access_token(subject=user.id)
    refresh_token = create_refresh_token(subject=user.id, jti=jti)

    # Persist refresh token for rotation and revocation tracking
    expires_at = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    token_record = RefreshToken(
        token_jti=jti,
        user_id=user.id,
        expires_at=expires_at,
        revoked=False,
    )
    db.add(token_record)
    db.commit()

    return Token(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
    )


@router.post("/refresh", response_model=Token)
async def refresh_token(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    refresh_token: str | None = None,
) -> Token:
    """Refresh access token using a valid refresh token with token rotation."""
    raw_token = refresh_token

    if not raw_token:
        content_type = request.headers.get("content-type", "")
        if "application/json" in content_type:
            try:
                body = await request.json()
                raw_token = body.get("refresh_token")
            except Exception:
                pass
        else:
            try:
                form = await request.form()
                raw_token = form.get("refresh_token")
            except Exception:
                pass

    if not raw_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token required",
        )

    try:
        payload = decode_token(raw_token)
        user_id = payload.get("sub")
        token_type = payload.get("type")
        jti = payload.get("jti")
        if user_id is None or token_type != "refresh":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid refresh token",
            )
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )

    user = db.query(User).filter(User.id == user_id).first()
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive",
        )

    # Validate against database if JTI present (Rotation & Revocation)
    if jti:
        token_record = db.query(RefreshToken).filter(RefreshToken.token_jti == jti).first()
        if not token_record:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid refresh token",
            )
        if token_record.revoked:
            # Token reuse detected! Revoke all tokens for this user for security
            db.query(RefreshToken).filter(RefreshToken.user_id == user.id).update({"revoked": True})
            db.commit()
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Refresh token has been revoked or already used",
            )

        now = datetime.now(timezone.utc)
        record_expires_at = token_record.expires_at
        if record_expires_at.tzinfo is None:
            record_expires_at = record_expires_at.replace(tzinfo=timezone.utc)
        if record_expires_at < now:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Refresh token expired",
            )

        # Revoke the used refresh token (Rotation)
        token_record.revoked = True
        db.add(token_record)

    # Issue new token pair
    new_jti = str(uuid.uuid4())
    new_access_token = create_access_token(subject=user.id)
    new_refresh_token = create_refresh_token(subject=user.id, jti=new_jti)
    new_expires_at = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    new_token_record = RefreshToken(
        token_jti=new_jti,
        user_id=user.id,
        expires_at=new_expires_at,
        revoked=False,
    )
    db.add(new_token_record)
    db.commit()

    return Token(
        access_token=new_access_token,
        refresh_token=new_refresh_token,
        token_type="bearer",
    )


@router.post("/logout", status_code=status.HTTP_200_OK)
async def logout(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> dict[str, str]:
    """Logout endpoint that revokes the active refresh token."""
    user_id: str | None = None
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        try:
            payload = decode_token(auth_header.split(" ")[1])
            user_id = payload.get("sub")
        except Exception:
            pass

    body_refresh_token: str | None = None
    try:
        content_type = request.headers.get("content-type", "")
        if "application/json" in content_type:
            body = await request.json()
            body_refresh_token = body.get("refresh_token")
        else:
            form = await request.form()
            body_refresh_token = form.get("refresh_token")
    except Exception:
        pass

    revoked_count = 0
    if body_refresh_token:
        try:
            payload = decode_token(body_refresh_token)
            jti = payload.get("jti")
            if jti:
                revoked_count = db.query(RefreshToken).filter(
                    RefreshToken.token_jti == jti
                ).update({"revoked": True})
                db.commit()
        except Exception:
            pass

    if user_id:
        revoked_count += db.query(RefreshToken).filter(
            RefreshToken.user_id == user_id,
            RefreshToken.revoked == False,
        ).update({"revoked": True})
        db.commit()

    if not auth_header and not body_refresh_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication credentials or refresh token required for logout",
        )

    return {"message": "Successfully logged out"}


@router.get("/me", response_model=UserResponse)
def read_current_user(
    current_user: Annotated[User, Depends(get_current_user)],
) -> UserResponse:
    """Get the profile of the currently authenticated user."""
    return UserResponse.model_validate(current_user)


@router.post("/forgot-password", response_model=ForgotPasswordResponse)
def forgot_password(
    payload: ForgotPasswordRequest,
    db: Annotated[Session, Depends(get_db)],
) -> ForgotPasswordResponse:
    """Send a 6-digit password reset verification code to the user's Gmail / email."""
    email = payload.email.strip().lower()
    if not email or "@" not in email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A valid email address is required.",
        )

    user = db.query(User).filter(User.email == email).first()
    # Generate 6-digit verification code
    code = "".join([str(secrets.randbelow(10)) for _ in range(6)])

    # Invalidate prior unused codes for this email
    db.query(PasswordResetToken).filter(
        PasswordResetToken.email == email,
        PasswordResetToken.used == False,
    ).update({"used": True})

    # Save new reset token record with 15-minute expiration
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    reset_record = PasswordResetToken(
        email=email,
        code=code,
        expires_at=expires_at,
        used=False,
    )
    db.add(reset_record)
    db.commit()

    # Deliver verification email via Gmail SMTP
    send_verification_email(email, code)

    return ForgotPasswordResponse(
        message="A 6-digit verification code has been sent to your email.",
        email=email,
    )


@router.post("/reset-password", response_model=ResetPasswordResponse)
def reset_password(
    payload: ResetPasswordRequest,
    db: Annotated[Session, Depends(get_db)],
) -> ResetPasswordResponse:
    """Verify the 6-digit code and reset the user's password."""
    email = payload.email.strip().lower()
    code = payload.code.strip()
    new_password = payload.new_password

    if not email or not code or not new_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email, verification code, and new password are required.",
        )

    if len(new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be at least 6 characters.",
        )

    token_record = db.query(PasswordResetToken).filter(
        PasswordResetToken.email == email,
        PasswordResetToken.code == code,
        PasswordResetToken.used == False,
    ).first()

    if not token_record:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or already used verification code.",
        )

    now = datetime.now(timezone.utc)
    token_expires_at = token_record.expires_at
    if token_expires_at.tzinfo is None:
        token_expires_at = token_expires_at.replace(tzinfo=timezone.utc)

    if token_expires_at < now:
        token_record.used = True
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Verification code has expired. Please request a new one.",
        )

    # Code is valid; mark as used
    token_record.used = True

    # Update user password if user exists
    user = db.query(User).filter(User.email == email).first()
    if user:
        user.hashed_password = get_password_hash(new_password)
        db.add(user)
        # Revoke all existing refresh tokens for security
        db.query(RefreshToken).filter(
            RefreshToken.user_id == user.id,
            RefreshToken.revoked == False,
        ).update({"revoked": True})

    db.commit()

    return ResetPasswordResponse(
        message="Your password has been successfully reset. You can now log in.",
    )


@router.post("/google", response_model=Token)
def google_auth(
    payload: GoogleAuthRequest,
    db: Annotated[Session, Depends(get_db)],
) -> Token:
    """Authenticate or register a user with Google OAuth credentials."""
    email = payload.email.strip().lower()
    if not email or "@" not in email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Valid Google account email is required.",
        )

    user = db.query(User).filter(User.email == email).first()
    if not user:
        # Create user account for Google sign-in
        user_name = (payload.name or email.split("@")[0]).strip()
        user = User(
            email=email,
            name=user_name,
            hashed_password=get_password_hash(secrets.token_urlsafe(32)),
            is_active=True,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    elif not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User account is inactive.",
        )
    elif payload.name and not user.name:
        user.name = payload.name
        db.add(user)
        db.commit()

    # Issue access and refresh tokens
    jti = str(uuid.uuid4())
    access_token = create_access_token(subject=user.id)
    refresh_token = create_refresh_token(subject=user.id, jti=jti)

    expires_at = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    token_record = RefreshToken(
        token_jti=jti,
        user_id=user.id,
        expires_at=expires_at,
        revoked=False,
    )
    db.add(token_record)
    db.commit()

    return Token(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
    )

