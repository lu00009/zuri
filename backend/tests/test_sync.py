import uuid


def test_sync_push_create_and_pull(client, auth_headers_user_a, user_a):
    note_id = str(uuid.uuid4())
    op_id = str(uuid.uuid4())

    push_payload = {
        "operations": [
            {
                "op_id": op_id,
                "entity_id": note_id,
                "op_type": "CREATE",
                "client_version": 0,
                "payload": {
                    "title": "Offline Created Idea",
                    "content": "Sync engine push test",
                    "tags": ["sync", "offline"],
                    "project_id": "pocketbrain",
                },
            }
        ]
    }

    # 1. Push
    push_res = client.post("/api/v1/sync/push", json=push_payload, headers=auth_headers_user_a)
    assert push_res.status_code == 200
    results = push_res.json()["results"]
    assert len(results) == 1
    assert results[0]["op_id"] == op_id
    assert results[0]["status"] == "APPLIED"
    assert results[0]["server_version"] == 1

    # 2. Pull with since_version = 0
    pull_res = client.get("/api/v1/sync/pull?since_version=0", headers=auth_headers_user_a)
    assert pull_res.status_code == 200
    pull_data = pull_res.json()
    assert pull_data["server_version_watermark"] == 1
    assert len(pull_data["notes"]) == 1
    assert pull_data["notes"][0]["id"] == note_id
    assert pull_data["notes"][0]["title"] == "Offline Created Idea"

    # 3. Pull with since_version = 1 -> should return 0 new updates
    empty_pull = client.get("/api/v1/sync/pull?since_version=1", headers=auth_headers_user_a)
    assert empty_pull.status_code == 200
    assert len(empty_pull.json()["notes"]) == 0


def test_sync_push_idempotent_duplicate_replay(client, auth_headers_user_a):
    note_id = str(uuid.uuid4())
    op_id = str(uuid.uuid4())

    payload = {
        "operations": [
            {
                "op_id": op_id,
                "entity_id": note_id,
                "op_type": "CREATE",
                "payload": {"title": "Idempotent Note", "content": "Test"},
            }
        ]
    }

    # First attempt: APPLIED
    res1 = client.post("/api/v1/sync/push", json=payload, headers=auth_headers_user_a)
    assert res1.status_code == 200
    assert res1.json()["results"][0]["status"] == "APPLIED"

    # Duplicate delivery (network retry): IGNORED
    res2 = client.post("/api/v1/sync/push", json=payload, headers=auth_headers_user_a)
    assert res2.status_code == 200
    assert res2.json()["results"][0]["status"] == "IGNORED"


def test_sync_conflict_detection_preserves_server_data(client, auth_headers_user_a):
    note_id = str(uuid.uuid4())

    # Create note at version 1
    client.post(
        "/api/v1/sync/push",
        json={
            "operations": [
                {
                    "op_id": str(uuid.uuid4()),
                    "entity_id": note_id,
                    "op_type": "CREATE",
                    "payload": {"title": "V1 Title", "content": "Initial"},
                }
            ]
        },
        headers=auth_headers_user_a,
    )

    # Device A syncs an update to version 2
    client.post(
        "/api/v1/sync/push",
        json={
            "operations": [
                {
                    "op_id": str(uuid.uuid4()),
                    "entity_id": note_id,
                    "op_type": "UPDATE",
                    "client_version": 1,
                    "payload": {"title": "V2 Title from Device A", "content": "Updated by Device A"},
                }
            ]
        },
        headers=auth_headers_user_a,
    )

    # Device B (offline) tries to push an update based on stale Version 1
    stale_update_op_id = str(uuid.uuid4())
    conflict_res = client.post(
        "/api/v1/sync/push",
        json={
            "operations": [
                {
                    "op_id": stale_update_op_id,
                    "entity_id": note_id,
                    "op_type": "UPDATE",
                    "client_version": 1,  # Outdated! Server is already at version 2
                    "payload": {"title": "Conflicting Title from Device B", "content": "Device B Edit"},
                }
            ]
        },
        headers=auth_headers_user_a,
    )

    assert conflict_res.status_code == 200
    result = conflict_res.json()["results"][0]
    assert result["status"] == "CONFLICT"
    assert result["server_version"] == 2
    assert result["conflict_note"]["title"] == "V2 Title from Device A"

    # Verify server content was NOT overwritten
    note_check = client.get(f"/api/v1/notes/{note_id}", headers=auth_headers_user_a)
    assert note_check.json()["title"] == "V2 Title from Device A"


def test_sync_deletion_propagation(client, auth_headers_user_a):
    note_id = str(uuid.uuid4())

    # Create note
    client.post(
        "/api/v1/sync/push",
        json={
            "operations": [
                {
                    "op_id": str(uuid.uuid4()),
                    "entity_id": note_id,
                    "op_type": "CREATE",
                    "payload": {"title": "To Be Deleted", "content": "Content"},
                }
            ]
        },
        headers=auth_headers_user_a,
    )

    # Push DELETE
    del_res = client.post(
        "/api/v1/sync/push",
        json={
            "operations": [
                {
                    "op_id": str(uuid.uuid4()),
                    "entity_id": note_id,
                    "op_type": "DELETE",
                    "client_version": 1,
                    "payload": {},
                }
            ]
        },
        headers=auth_headers_user_a,
    )
    assert del_res.status_code == 200
    assert del_res.json()["results"][0]["status"] == "APPLIED"

    # Pull since_version = 1 -> Must contain the soft-deleted note with is_deleted = True
    pull_res = client.get("/api/v1/sync/pull?since_version=1", headers=auth_headers_user_a)
    assert pull_res.status_code == 200
    notes = pull_res.json()["notes"]
    assert len(notes) == 1
    assert notes[0]["id"] == note_id
    assert notes[0]["is_deleted"] is True
