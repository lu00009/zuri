import json
from pathlib import Path


def _seed_evaluation_notes(client, auth_headers):
    eval_file = Path(__file__).parent / "evaluation_dataset.json"
    with open(eval_file, "r") as f:
        data = json.load(f)

    for note in data["test_notes"]:
        client.post(
            "/api/v1/notes",
            json={
                "id": note["id"],
                "title": note["title"],
                "content": note["content"],
                "tags": note["tags"],
            },
            headers=auth_headers,
        )


def test_ai_ask_positive_query_returns_citation(client, auth_headers_user_a):
    _seed_evaluation_notes(client, auth_headers_user_a)

    # Ask factual question
    response = client.post(
        "/api/v1/ai/ask",
        json={"query": "Which state management solution was selected for Flutter?"},
        headers=auth_headers_user_a,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["has_sufficient_evidence"] is True
    assert "Riverpod" in data["answer"]
    assert len(data["citations"]) > 0
    assert data["citations"][0]["note_id"] == "eval-note-2"
    assert data["citations"][0]["note_title"] == "Flutter State Management"
    assert data["latency_ms"] >= 0.0


def test_ai_ask_missing_evidence_indicates_insufficient_information(client, auth_headers_user_a):
    _seed_evaluation_notes(client, auth_headers_user_a)

    # Ask about something not in user notes
    response = client.post(
        "/api/v1/ai/ask",
        json={"query": "What is the secret recipe for chocolate cake?"},
        headers=auth_headers_user_a,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["has_sufficient_evidence"] is False
    assert "insufficient information" in data["answer"].lower()
    assert len(data["citations"]) == 0


def test_ai_ask_user_isolation(client, auth_headers_user_a, auth_headers_user_b):
    """Ensure User B cannot retrieve or cite User A's private notes."""
    _seed_evaluation_notes(client, auth_headers_user_a)

    # User B asks about Flutter state management
    response = client.post(
        "/api/v1/ai/ask",
        json={"query": "Which state management solution was selected for Flutter?"},
        headers=auth_headers_user_b,
    )
    assert response.status_code == 200
    data = response.json()
    # User B has no notes -> must report insufficient evidence
    assert data["has_sufficient_evidence"] is False
    assert len(data["citations"]) == 0


def test_stale_embedding_detection_and_reindex(client, auth_headers_user_a):
    create_res = client.post(
        "/api/v1/notes",
        json={"title": "Cloud Strategy", "content": "Initial plan was AWS EC2."},
        headers=auth_headers_user_a,
    )
    note_id = create_res.json()["id"]

    # Initial query
    q1 = client.post(
        "/api/v1/ai/ask",
        json={"query": "What was the cloud provider plan?"},
        headers=auth_headers_user_a,
    )
    assert "AWS" in q1.json()["answer"]

    # Update note to GCP
    client.put(
        f"/api/v1/notes/{note_id}",
        json={"content": "Revised decision is Google Cloud Platform with Kubernetes."},
        headers=auth_headers_user_a,
    )

    # Subsequent query must reflect the updated content, not stale embedding!
    q2 = client.post(
        "/api/v1/ai/ask",
        json={"query": "What was the cloud provider plan?"},
        headers=auth_headers_user_a,
    )
    assert "Google Cloud" in q2.json()["answer"]


def test_semantic_search_endpoint(client, auth_headers_user_a):
    _seed_evaluation_notes(client, auth_headers_user_a)

    res = client.get(
        "/api/v1/ai/semantic-search?query=PostgreSQL+and+Alembic",
        headers=auth_headers_user_a,
    )
    assert res.status_code == 200
    results = res.json()["results"]
    assert len(results) > 0
    assert results[0]["note_id"] == "eval-note-1"
    assert results[0]["similarity"] > 0.0
