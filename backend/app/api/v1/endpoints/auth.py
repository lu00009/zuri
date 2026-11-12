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
import re
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.config import settings
from app.core.rate_limiter import auth_rate_limiter
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    generate_recovery_code,
    get_password_hash,
    normalize_recovery_code,
    verify_google_id_token,
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
    RecoveryRegenerateResponse,
    RecoveryResetRequest,
    RecoveryResetResponse,
    RecoveryStatusResponse,
    RefreshTokenRequest,
    ResetPasswordRequest,
    ResetPasswordResponse,
    Token,
)
from app.schemas.user import RegisterResponse, UserCreate, UserResponse
from app.services.email_service import send_verification_email

router = APIRouter()


def get_client_ip(request: Request) -> str:
    """Extract client IP respecting X-Forwarded-For when behind reverse proxies."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "127.0.0.1"


@router.post("/register", response_model=RegisterResponse, status_code=status.HTTP_201_CREATED)
def register(
    user_in: UserCreate,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> RegisterResponse:
    """
    Register a new user account with secure password hashing,
    automatic session establishment, and a one-time account recovery code.
    """
    email_clean = user_in.email.strip().lower()
    if not email_clean or "@" not in email_clean or "." not in email_clean.split("@")[-1]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A valid email address is required.",
        )

    # Password strength validation
    password = user_in.password
    if len(password) < 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be at least 6 characters.",
        )
    if password.isnumeric():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password cannot consist solely of digits.",
        )

    existing = db.query(User).filter(User.email == email_clean).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email address already exists.",
        )

    # Generate one-time account recovery code
    recovery_code = generate_recovery_code()
    recovery_code_hash = get_password_hash(normalize_recovery_code(recovery_code))

    user = User(
        email=email_clean,
        name=user_in.name.strip(),
        hashed_password=get_password_hash(password),
        recovery_code_hash=recovery_code_hash,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    # Automatically authenticate the newly registered user
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

    return RegisterResponse(
        id=user.id,
        email=user.email,
        name=user.name,
        is_active=user.is_active,
        created_at=user.created_at,
        recovery_code=recovery_code,
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
    )


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

    client_ip = get_client_ip(request)
    rate_key = f"login:{client_ip}:{username.lower()}"
    auth_rate_limiter.check_rate_limit(
        rate_key,
        max_attempts=5,
        window_seconds=300,
        action_name="login attempts",
    )

    user = db.query(User).filter(User.email == username.lower()).first()
    if not user or not verify_password(password, user.hashed_password):
        auth_rate_limiter.record_attempt(rate_key)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incorrect email or password",
        )
    if not user.is_active:
        auth_rate_limiter.record_attempt(rate_key)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Inactive user profile",
        )

    # Reset rate limiting upon valid credentials
    auth_rate_limiter.reset(rate_key)

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
async def google_auth(
    payload: GoogleAuthRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> Token:
    """
    Authenticate or register a user with verified Google OAuth ID tokens.
    Never trusts untrusted client claims; cryptographically validates token.
    """
    client_ip = get_client_ip(request)
    rate_key = f"google:{client_ip}"
    auth_rate_limiter.check_rate_limit(
        rate_key,
        max_attempts=15,
        window_seconds=300,
        action_name="Google authentication requests",
    )

    id_token = payload.id_token.strip()
    if not id_token:
        auth_rate_limiter.record_attempt(rate_key)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Google ID token is required for authentication.",
        )

    try:
        google_info = await verify_google_id_token(
            token=id_token,
            expected_client_id=payload.client_id,
        )
    except ValueError as err:
        auth_rate_limiter.record_attempt(rate_key)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Google authentication failed: {err}",
        )

    email = google_info["email"]
    name = google_info.get("name") or payload.name or email.split("@")[0]
    google_id = google_info.get("google_id")

    user = db.query(User).filter(User.email == email).first()
    if not user:
        # Create new user for verified Google profile
        recovery_code = generate_recovery_code()
        user = User(
            email=email,
            name=name.strip(),
            hashed_password=get_password_hash(secrets.token_urlsafe(32)),
            recovery_code_hash=get_password_hash(normalize_recovery_code(recovery_code)),
            google_id=google_id,
            is_active=True,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    elif not user.is_active:
        auth_rate_limiter.record_attempt(rate_key)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User account is inactive.",
        )
    else:
        # Existing user: update missing metadata
        if google_id and not user.google_id:
            user.google_id = google_id
            db.add(user)
        if name and not user.name:
            user.name = name.strip()
            db.add(user)
        db.commit()

    # Reset rate limiter upon successful Google auth
    auth_rate_limiter.reset(rate_key)

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


@router.post("/recovery-reset", response_model=RecoveryResetResponse)
def recovery_reset(
    payload: RecoveryResetRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> RecoveryResetResponse:
    """
    Reset user password using their offline Account Recovery Code (No Email OTP).
    Rate-limited and protects account existence privacy.
    Invalidates the recovery code immediately upon successful use.
    """
    client_ip = get_client_ip(request)
    email_clean = payload.email.strip().lower()
    rate_key = f"recovery:{client_ip}:{email_clean}"

    auth_rate_limiter.check_rate_limit(
        rate_key,
        max_attempts=5,
        window_seconds=900,
        action_name="account recovery attempts",
    )

    # Password strength validation
    new_password = payload.new_password
    if len(new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be at least 6 characters.",
        )
    if new_password.isnumeric():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password cannot consist solely of digits.",
        )

    user = db.query(User).filter(User.email == email_clean).first()
    normalized_input_code = normalize_recovery_code(payload.recovery_code)

    # Generic rejection if user doesn't exist, has no code, or code doesn't match
    if (
        not user
        or not user.recovery_code_hash
        or not normalized_input_code
        or not verify_password(normalized_input_code, user.recovery_code_hash)
    ):
        auth_rate_limiter.record_attempt(rate_key)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid email address or recovery code. If you have lost both, administrative verification is required.",
        )

    # Reset rate limit counter on success
    auth_rate_limiter.reset(rate_key)

    # Update password and invalidate the single-use recovery code
    user.hashed_password = get_password_hash(new_password)
    user.recovery_code_hash = None
    db.add(user)

    # Revoke all active refresh tokens for the user
    db.query(RefreshToken).filter(
        RefreshToken.user_id == user.id,
        RefreshToken.revoked == False,
    ).update({"revoked": True})
    db.commit()

    return RecoveryResetResponse(
        message="Your password has been successfully reset. Please sign in with your new password.",
    )


@router.post("/recovery-code/regenerate", response_model=RecoveryRegenerateResponse)
def regenerate_recovery_code(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
) -> RecoveryRegenerateResponse:
    """Generate and store a new recovery code for an authenticated user."""
    new_code = generate_recovery_code()
    current_user.recovery_code_hash = get_password_hash(normalize_recovery_code(new_code))
    db.add(current_user)
    db.commit()

    return RecoveryRegenerateResponse(
        recovery_code=new_code,
        message="A new recovery code has been generated. Store it safely.",
    )


@router.get("/recovery-code/status", response_model=RecoveryStatusResponse)
def get_recovery_code_status(
    current_user: Annotated[User, Depends(get_current_user)],
) -> RecoveryStatusResponse:
    """Check whether the authenticated user has an active recovery code."""
    return RecoveryStatusResponse(
        has_recovery_code=bool(current_user.recovery_code_hash),
    )


