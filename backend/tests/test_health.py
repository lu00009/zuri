def test_health_check_endpoint(client):
    """Verify that the health check endpoint returns 200 and expected schema values."""
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["app"] == "pocketbrain"
    assert data["version"] == "0.1.0"
    assert "environment" in data


def test_root_endpoint(client):
    """Verify that root endpoint provides discoverable links to docs and health check."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["app"] == "PocketBrain API"
    assert "/api/v1/health" in data["health"]
    assert "/api/v1/docs" in data["docs"]
