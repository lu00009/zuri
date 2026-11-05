from datetime import timedelta
import pytest
from app.core.security import create_access_token


def test_registration_with_name_and_login(client):
    # 1. Register with name
    reg_res = client.post(
        "/api/v1/auth/register",
        json={
            "name": "Alice Wonderland",
            "email": "alice@example.com",
            "password": "Password123!",
        },
    )
    assert reg_res.status_code == 201
    reg_data = reg_res.json()
    assert reg_data["email"] == "alice@example.com"
    assert reg_data["name"] == "Alice Wonderland"
    assert "id" in reg_data

    # 2. Duplicate registration rejection
    dup_res = client.post(
        "/api/v1/auth/register",
        json={
            "name": "Alice Duplicate",
            "email": "alice@example.com",
            "password": "Password123!",
        },
    )
    assert dup_res.status_code == 400
    assert "already exists" in dup_res.json()["detail"]

    # 3. Successful login with JSON
    login_json_res = client.post(
        "/api/v1/auth/login",
        json={
            "email": "alice@example.com",
            "password": "Password123!",
        },
    )
    assert login_json_res.status_code == 200
    login_data = login_json_res.json()
    assert "access_token" in login_data
    assert "refresh_token" in login_data
    assert login_data["token_type"] == "bearer"

    # 4. Successful login with Form Data
    login_form_res = client.post(
        "/api/v1/auth/login",
        data={
            "username": "alice@example.com",
            "password": "Password123!",
        },
    )
    assert login_form_res.status_code == 200

    # 5. Invalid password rejection
    bad_login_res = client.post(
        "/api/v1/auth/login",
        json={
            "email": "alice@example.com",
            "password": "WrongPassword",
        },
    )
    assert bad_login_res.status_code == 400
    assert "Incorrect email or password" in bad_login_res.json()["detail"]


def test_token_expiration_rejection(client, user_a):
    # Expired access token (negative expiration delta)
    expired_token = create_access_token(
        subject=user_a.id,
        expires_delta=timedelta(seconds=-10),
    )
    res = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {expired_token}"},
    )
    assert res.status_code == 401
    assert "Could not validate credentials" in res.json()["detail"]


def test_refresh_token_rotation_and_reuse_rejection(client):
    # Register & Login
    client.post(
        "/api/v1/auth/register",
        json={"email": "rotate@example.com", "password": "Password123!"},
    )
    login_res = client.post(
        "/api/v1/auth/login",
        json={"email": "rotate@example.com", "password": "Password123!"},
    )
    tokens = login_res.json()
    r1 = tokens["refresh_token"]

    # First refresh: Should succeed and rotate tokens
    refresh_res1 = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": r1},
    )
    assert refresh_res1.status_code == 200
    rotated_tokens = refresh_res1.json()
    r2 = rotated_tokens["refresh_token"]
    assert r2 != r1

    # Second refresh using old refresh token r1 (REUSE ATTEMPT): Must be rejected!
    reuse_res = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": r1},
    )
    assert reuse_res.status_code == 401
    assert "revoked or already used" in reuse_res.json()["detail"]

    # Since r1 was reused, r2 is also revoked (family invalidation)
    r2_after_reuse = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": r2},
    )
    assert r2_after_reuse.status_code == 401


def test_logout_revokes_token(client):
    # Register & Login
    client.post(
        "/api/v1/auth/register",
        json={"email": "logout_user@example.com", "password": "Password123!"},
    )
    login_res = client.post(
        "/api/v1/auth/login",
        json={"email": "logout_user@example.com", "password": "Password123!"},
    )
    tokens = login_res.json()
    access_token = tokens["access_token"]
    refresh_token = tokens["refresh_token"]

    # Logout with refresh_token in payload
    logout_res = client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"refresh_token": refresh_token},
    )
    assert logout_res.status_code == 200
    assert "Successfully logged out" in logout_res.json()["message"]

    # Attempting to refresh using revoked token must fail with 401
    refresh_res = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert refresh_res.status_code == 401
