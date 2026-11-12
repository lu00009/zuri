import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.models.user import User
from app.models.password_reset import PasswordResetToken
from app.core.security import verify_password


def test_forgot_password_flow(client: TestClient, db_session: Session):
    # Register test user
    client.post(
        "/api/v1/auth/register",
        json={"email": "forgot@example.com", "password": "oldPassword123", "name": "Forgot User"},
    )

    # Request password reset
    response = client.post(
        "/api/v1/auth/forgot-password",
        json={"email": "forgot@example.com"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "verification code" in data["message"].lower()
    assert data["email"] == "forgot@example.com"

    # Verify a token record was created in the database
    record = db_session.query(PasswordResetToken).filter(PasswordResetToken.email == "forgot@example.com").first()
    assert record is not None
    assert len(record.code) == 6
    assert record.used is False

    # Reset password with invalid code
    bad_res = client.post(
        "/api/v1/auth/reset-password",
        json={"email": "forgot@example.com", "code": "000000", "new_password": "newSecurePassword456"},
    )
    assert bad_res.status_code == 400

    # Reset password with correct code
    good_res = client.post(
        "/api/v1/auth/reset-password",
        json={"email": "forgot@example.com", "code": record.code, "new_password": "newSecurePassword456"},
    )
    assert good_res.status_code == 200
    assert "successfully reset" in good_res.json()["message"]

    # Verify code is now used
    db_session.refresh(record)
    assert record.used is True

    # Verify user can log in with new password
    login_res = client.post(
        "/api/v1/auth/login",
        json={"email": "forgot@example.com", "password": "newSecurePassword456"},
    )
    assert login_res.status_code == 200
    assert "access_token" in login_res.json()


def test_google_auth_flow(client: TestClient, db_session: Session):
    # New user Google sign in
    response = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "mock-google-token:googleuser@gmail.com:Google User",
            "email": "googleuser@gmail.com",
            "name": "Google User",
            "google_id": "google-123456",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data

    # Verify user exists in DB
    user = db_session.query(User).filter(User.email == "googleuser@gmail.com").first()
    assert user is not None
    assert user.name == "Google User"

    # Subsequent Google sign in for existing user
    response2 = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "mock-google-token:googleuser@gmail.com:Google User",
            "email": "googleuser@gmail.com",
            "name": "Google User Updated",
        },
    )
    assert response2.status_code == 200
    data2 = response2.json()
    assert "access_token" in data2
