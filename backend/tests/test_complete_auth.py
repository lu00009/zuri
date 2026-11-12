import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.models.user import User
from app.core.rate_limiter import auth_rate_limiter
from app.core.security import verify_password, normalize_recovery_code


@pytest.fixture(autouse=True)
def clear_rate_limits():
    auth_rate_limiter.clear_all()
    yield
    auth_rate_limiter.clear_all()


def test_registration_with_recovery_code_and_auto_login(client: TestClient, db_session: Session):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "sarah@example.com",
            "name": "Sarah Connor",
            "password": "StrongPassword123!",
        },
    )
    assert response.status_code == 201
    data = response.json()

    assert data["email"] == "sarah@example.com"
    assert data["name"] == "Sarah Connor"
    assert "recovery_code" in data
    assert len(data["recovery_code"].replace("-", "")) == 16
    assert "access_token" in data
    assert "refresh_token" in data

    # Verify recovery code hash is stored in DB
    user = db_session.query(User).filter(User.email == "sarah@example.com").first()
    assert user is not None
    assert user.recovery_code_hash is not None
    assert verify_password(normalize_recovery_code(data["recovery_code"]), user.recovery_code_hash)


def test_registration_password_strength_and_duplicate_prevention(client: TestClient):
    # Short password
    res1 = client.post(
        "/api/v1/auth/register",
        json={"email": "short@example.com", "name": "Short", "password": "123"},
    )
    assert res1.status_code in [400, 422]

    # All digits password
    res2 = client.post(
        "/api/v1/auth/register",
        json={"email": "digits@example.com", "name": "Digits", "password": "12345678"},
    )
    assert res2.status_code in [400, 422]
    assert "cannot consist solely of digits" in res2.json()["detail"]

    # Duplicate registration
    client.post(
        "/api/v1/auth/register",
        json={"email": "unique@example.com", "name": "Unique", "password": "ValidPassword123"},
    )
    res_dup = client.post(
        "/api/v1/auth/register",
        json={"email": "unique@example.com", "name": "Unique 2", "password": "ValidPassword123"},
    )
    assert res_dup.status_code == 400
    assert "already exists" in res_dup.json()["detail"]


def test_login_and_rate_limiting(client: TestClient):
    # Register test user
    client.post(
        "/api/v1/auth/register",
        json={"email": "rate@example.com", "name": "Rate User", "password": "SecretPassword123"},
    )

    # 5 failed login attempts
    for i in range(5):
        fail_res = client.post(
            "/api/v1/auth/login",
            json={"email": "rate@example.com", "password": "wrongPassword"},
        )
        assert fail_res.status_code == 400

    # 6th attempt should be rate limited (429)
    locked_res = client.post(
        "/api/v1/auth/login",
        json={"email": "rate@example.com", "password": "SecretPassword123"},
    )
    assert locked_res.status_code == 429
    assert "temporarily locked" in locked_res.json()["detail"]


def test_recovery_reset_flow_and_one_time_use(client: TestClient, db_session: Session):
    reg = client.post(
        "/api/v1/auth/register",
        json={"email": "recover@example.com", "name": "Recover User", "password": "OldPassword123"},
    )
    recovery_code = reg.json()["recovery_code"]

    # Invalid code attempt
    bad_reset = client.post(
        "/api/v1/auth/recovery-reset",
        json={
            "email": "recover@example.com",
            "recovery_code": "WRONG-CODE-XXXX-YYYY",
            "new_password": "NewSecretPassword123",
        },
    )
    assert bad_reset.status_code == 400
    assert "Invalid email address or recovery code" in bad_reset.json()["detail"]

    # Successful recovery reset
    good_reset = client.post(
        "/api/v1/auth/recovery-reset",
        json={
            "email": "recover@example.com",
            "recovery_code": recovery_code,
            "new_password": "NewSecretPassword123",
        },
    )
    assert good_reset.status_code == 200
    assert "successfully reset" in good_reset.json()["message"]

    # Verify login works with new password
    login_new = client.post(
        "/api/v1/auth/login",
        json={"email": "recover@example.com", "password": "NewSecretPassword123"},
    )
    assert login_new.status_code == 200

    # Code cannot be reused (one-time use)
    reuse_reset = client.post(
        "/api/v1/auth/recovery-reset",
        json={
            "email": "recover@example.com",
            "recovery_code": recovery_code,
            "new_password": "AnotherPassword456",
        },
    )
    assert reuse_reset.status_code == 400
    assert "Invalid email address or recovery code" in reuse_reset.json()["detail"]


def test_authenticated_recovery_code_regeneration(client: TestClient):
    reg = client.post(
        "/api/v1/auth/register",
        json={"email": "regen@example.com", "name": "Regen User", "password": "Password123!"},
    )
    token = reg.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Check status
    status_res = client.get("/api/v1/auth/recovery-code/status", headers=headers)
    assert status_res.status_code == 200
    assert status_res.json()["has_recovery_code"] is True

    # Regenerate code
    regen_res = client.post("/api/v1/auth/recovery-code/regenerate", headers=headers)
    assert regen_res.status_code == 200
    new_code = regen_res.json()["recovery_code"]
    assert len(new_code.replace("-", "")) == 16

    # Verify password can be reset with the newly regenerated code
    reset_res = client.post(
        "/api/v1/auth/recovery-reset",
        json={
            "email": "regen@example.com",
            "recovery_code": new_code,
            "new_password": "BrandNewPassword999",
        },
    )
    assert reset_res.status_code == 200


def test_google_auth_verification(client: TestClient, db_session: Session):
    # Verify mock google token in dev/test environment
    response = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "mock-google-token:gtest@example.com:Google Guy",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data

    # Verify user was created in DB
    user = db_session.query(User).filter(User.email == "gtest@example.com").first()
    assert user is not None
    assert user.google_id == "mock-gtest@example.com"
    assert user.name == "Google Guy"

    # Subsequent sign in with same google token returns valid tokens
    response2 = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "mock-google-token:gtest@example.com:Google Guy",
        },
    )
    assert response2.status_code == 200
    assert "access_token" in response2.json()
