import uuid


def test_create_note_with_tags_and_project(client, auth_headers_user_a, user_a):
    payload = {
        "title": "FastAPI Architecture",
        "content": "Designing resilient offline-first backends",
        "project_id": "pocketbrain",
        "tags": ["python", "fastapi"],
        "is_pinned": True,
    }
    response = client.post("/api/v1/notes", json=payload, headers=auth_headers_user_a)
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == payload["title"]
    assert data["content"] == payload["content"]
    assert data["project_id"] == "pocketbrain"
    assert "python" in data["tags"]
    assert "fastapi" in data["tags"]
    assert data["is_pinned"] is True
    assert data["user_id"] == user_a.id
    assert data["version"] == 1


def test_create_note_with_client_uuid(client, auth_headers_user_a):
    client_id = str(uuid.uuid4())
    payload = {
        "id": client_id,
        "title": "Offline Created Note",
        "content": "Created on device with UUIDv4",
    }
    response = client.post("/api/v1/notes", json=payload, headers=auth_headers_user_a)
    assert response.status_code == 201
    data = response.json()
    assert data["id"] == client_id


def test_list_notes_with_search_and_tag_filter(client, auth_headers_user_a):
    client.post(
        "/api/v1/notes",
        json={"title": "Flutter Basics", "content": "Widgets and State", "tags": ["flutter"]},
        headers=auth_headers_user_a,
    )
    client.post(
        "/api/v1/notes",
        json={"title": "Python Basics", "content": "Decorators and Generators", "tags": ["python"]},
        headers=auth_headers_user_a,
    )

    # Search query
    res = client.get("/api/v1/notes?search=Decorators", headers=auth_headers_user_a)
    assert res.status_code == 200
    items = res.json()["items"]
    assert len(items) == 1
    assert items[0]["title"] == "Python Basics"

    # Tag filter
    tag_res = client.get("/api/v1/notes?tag=flutter", headers=auth_headers_user_a)
    assert tag_res.status_code == 200
    tag_items = tag_res.json()["items"]
    assert len(tag_items) == 1
    assert tag_items[0]["title"] == "Flutter Basics"


def test_update_and_soft_delete_note(client, auth_headers_user_a):
    create_res = client.post(
        "/api/v1/notes",
        json={"title": "Original Title", "content": "Original Content"},
        headers=auth_headers_user_a,
    )
    note_id = create_res.json()["id"]

    # Update
    update_res = client.put(
        f"/api/v1/notes/{note_id}",
        json={"title": "Updated Title", "is_archived": True},
        headers=auth_headers_user_a,
    )
    assert update_res.status_code == 200
    assert update_res.json()["title"] == "Updated Title"
    assert update_res.json()["is_archived"] is True
    assert update_res.json()["version"] == 2

    # Soft delete
    del_res = client.delete(f"/api/v1/notes/{note_id}", headers=auth_headers_user_a)
    assert del_res.status_code == 204

    # Note should no longer be in active listing
    list_res = client.get("/api/v1/notes", headers=auth_headers_user_a)
    assert not any(n["id"] == note_id for n in list_res.json()["items"])
