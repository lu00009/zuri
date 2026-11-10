from pydantic import BaseModel


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class TokenPayload(BaseModel):
    sub: str | None = None
    exp: int | None = None
    type: str | None = None
    jti: str | None = None


class LoginRequest(BaseModel):
    email: str | None = None
    username: str | None = None
    password: str


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str | None = None


class ForgotPasswordRequest(BaseModel):
    email: str


class ForgotPasswordResponse(BaseModel):
    message: str
    email: str


class ResetPasswordRequest(BaseModel):
    email: str
    code: str
    new_password: str


class ResetPasswordResponse(BaseModel):
    message: str


class GoogleAuthRequest(BaseModel):
    id_token: str | None = None
    email: str
    name: str | None = ""
    google_id: str | None = None


