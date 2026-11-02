def test_register_new_user(client):
    response = client.post(
        "/api/v1/auth/register",
        json={"email": "newuser@example.com", "password": "securepassword123"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "newuser@example.com"
    assert "id" in data
    assert data["is_active"] is True


def test_register_duplicate_email_fails(client, user_a):
    response = client.post(
        "/api/v1/auth/register",
        json={"email": user_a.email, "password": "anotherpassword"},
    )
    assert response.status_code == 400
    assert "already exists" in response.json()["detail"]


def test_login_success(client, user_a):
    response = client.post(
        "/api/v1/auth/login",
        data={"username": user_a.email, "password": "password123"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


def test_login_invalid_password_fails(client, user_a):
    response = client.post(
        "/api/v1/auth/login",
        data={"username": user_a.email, "password": "wrongpassword"},
    )
    assert response.status_code == 400
    assert "Incorrect email or password" in response.json()["detail"]


def test_me_endpoint_with_auth(client, auth_headers_user_a, user_a):
    response = client.get("/api/v1/auth/me", headers=auth_headers_user_a)
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == user_a.email
    assert data["id"] == user_a.id


def test_me_endpoint_without_auth_fails(client):
    response = client.get("/api/v1/auth/me")
    assert response.status_code == 401
