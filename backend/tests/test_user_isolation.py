def test_user_cannot_access_other_users_note(
    client,
    auth_headers_user_a,
    auth_headers_user_b,
):
    """Verify that User B cannot read, list, modify, or delete User A's private notes."""
    # User A creates a secret note
    create_res = client.post(
        "/api/v1/notes",
        json={
            "title": "User A Private Diary",
            "content": "Confidential information strictly for User A",
            "tags": ["topsecret"],
            "project_id": "secret-project-a",
        },
        headers=auth_headers_user_a,
    )
    assert create_res.status_code == 201
    note_id = create_res.json()["id"]

    # 1. User B lists notes -> Note A must NOT appear
    list_res = client.get("/api/v1/notes", headers=auth_headers_user_b)
    assert list_res.status_code == 200
    assert not any(n["id"] == note_id for n in list_res.json()["items"])

    # 2. User B tries to get Note A directly by ID -> 404 Not Found
    get_res = client.get(f"/api/v1/notes/{note_id}", headers=auth_headers_user_b)
    assert get_res.status_code == 404

    # 3. User B tries to update Note A -> 404 Not Found
    update_res = client.put(
        f"/api/v1/notes/{note_id}",
        json={"title": "Hacked Title"},
        headers=auth_headers_user_b,
    )
    assert update_res.status_code == 404

    # 4. User B tries to delete Note A -> 404 Not Found
    delete_res = client.delete(f"/api/v1/notes/{note_id}", headers=auth_headers_user_b)
    assert delete_res.status_code == 404

    # 5. User B lists tags and projects -> User A's private tags/projects must not leak
    tags_res = client.get("/api/v1/notes/tags/all", headers=auth_headers_user_b)
    assert tags_res.status_code == 200
    assert "topsecret" not in tags_res.json()

    projects_res = client.get("/api/v1/notes/projects/all", headers=auth_headers_user_b)
    assert projects_res.status_code == 200
    assert "secret-project-a" not in projects_res.json()

    # 6. Verify User A's note is completely intact and unchanged
    verify_res = client.get(f"/api/v1/notes/{note_id}", headers=auth_headers_user_a)
    assert verify_res.status_code == 200
    assert verify_res.json()["title"] == "User A Private Diary"
