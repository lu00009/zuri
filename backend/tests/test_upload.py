import base64
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_upload_config():
    response = client.get("/api/v1/upload/config")
    assert response.status_code == 200
    data = response.json()
    assert "configured" in data
    assert "upload_preset" in data

def test_upload_image_fallback():
    # 1x1 transparent png
    dummy_png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
    b64 = base64.b64encode(dummy_png).decode("utf-8")
    data_uri = f"data:image/png;base64,{b64}"

    response = client.post(
        "/api/v1/upload/image",
        json={"image": data_uri, "folder": "test_folder"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "url" in data
    assert "secure_url" in data

