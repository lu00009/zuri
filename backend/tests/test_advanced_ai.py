import pytest
from datetime import datetime, timedelta, timezone


def _seed_test_memories(client, auth_headers):
    notes = [
        {
            "id": "mem-1",
            "title": "PostgreSQL Database Architecture",
            "content": "For our backend relational persistence, we selected PostgreSQL for relational data management and structured ACID transactions.",
            "tags": ["database", "postgres", "backend", "architecture"],
        },
        {
            "id": "mem-2",
            "title": "SQLite Local Persistence",
            "content": "For client-side offline storage, SQLite was chosen with sqflite to support zero-latency local operations.",
            "tags": ["database", "sqlite", "mobile", "offline"],
        },
        {
            "id": "mem-3",
            "title": "Cloud Provider Initial Strategy",
            "content": "Initial infrastructure plan was AWS EC2 with Docker containers.",
            "tags": ["cloud", "infrastructure", "devops"],
        },
        {
            "id": "mem-4",
            "title": "Cloud Provider Strategy Revised",
            "content": "We revised the decision from AWS to Google Cloud Platform using Google Kubernetes Engine for managed scalability.",
            "tags": ["cloud", "infrastructure", "gcp", "decision"],
        },
        {
            "id": "mem-5",
            "title": "Machine Learning Research",
            "content": "Studied semantic vector embeddings and cosine similarity for offline knowledge retrieval.",
            "tags": ["learning", "ai", "embeddings"],
        },
        {
            "id": "mem-6",
            "title": "Future Ideas and Backlog",
            "content": "Todo: explore automatic related memory discovery and background graph generation.",
            "tags": ["idea", "future", "todo"],
        },
    ]

    for n in notes:
        client.post("/api/v1/notes", json=n, headers=auth_headers)


# ---------------------------------------------------------------------------
# Feature 1: Conversational Memory Tests
# ---------------------------------------------------------------------------

def test_conversation_lifecycle_and_multi_turn_followup(client, auth_headers_user_a):
    _seed_test_memories(client, auth_headers_user_a)

    # 1. Create a new conversation
    res = client.post(
        "/api/v1/ai/conversations",
        json={"title": "Tech Stack Questions"},
        headers=auth_headers_user_a,
    )
    assert res.status_code == 201
    conv = res.json()
    conv_id = conv["id"]
    assert conv["title"] == "Tech Stack Questions"
    assert len(conv["messages"]) == 0

    # 2. First turn: "What database did I choose for my project?"
    turn1_res = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "What database did I choose for my project?"},
        headers=auth_headers_user_a,
    )
    assert turn1_res.status_code == 201
    turn1_data = turn1_res.json()
    assert turn1_data["user_message"]["content"] == "What database did I choose for my project?"
    assistant_content = turn1_data["assistant_message"]["content"]
    assert "PostgreSQL" in assistant_content or "SQLite" in assistant_content
    assert len(turn1_data["assistant_message"]["citations"]) > 0

    # 3. Follow-up turn with pronoun: "Why did I choose it?"
    turn2_res = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "Why did I choose it?"},
        headers=auth_headers_user_a,
    )
    assert turn2_res.status_code == 201
    turn2_data = turn2_res.json()
    followup_answer = turn2_data["assistant_message"]["content"]
    # The follow-up must understand what 'it' refers to (PostgreSQL or SQLite persistence)
    assert any(term in followup_answer for term in ["PostgreSQL", "SQLite", "relational", "transactions", "offline"])
    assert len(turn2_data["assistant_message"]["citations"]) > 0

    # 4. Check conversation history persistence
    get_conv = client.get(
        f"/api/v1/ai/conversations/{conv_id}",
        headers=auth_headers_user_a,
    )
    assert get_conv.status_code == 200
    detail = get_conv.json()
    # 2 turns = 4 messages (2 user + 2 assistant)
    assert len(detail["messages"]) == 4
    assert detail["messages"][0]["role"] == "user"
    assert detail["messages"][1]["role"] == "assistant"
    assert detail["messages"][2]["role"] == "user"
    assert detail["messages"][3]["role"] == "assistant"

    # 5. Rename conversation
    patch_res = client.patch(
        f"/api/v1/ai/conversations/{conv_id}",
        json={"title": "Databases Discussion"},
        headers=auth_headers_user_a,
    )
    assert patch_res.status_code == 200
    assert patch_res.json()["title"] == "Databases Discussion"

    # 6. List conversations
    list_res = client.get(
        "/api/v1/ai/conversations",
        headers=auth_headers_user_a,
    )
    assert list_res.status_code == 200
    conv_list = list_res.json()
    assert len(conv_list) >= 1
    assert conv_list[0]["id"] == conv_id
    assert conv_list[0]["message_count"] == 4

    # 7. Delete conversation
    del_res = client.delete(
        f"/api/v1/ai/conversations/{conv_id}",
        headers=auth_headers_user_a,
    )
    assert del_res.status_code == 204

    # Verify deleted
    verify_del = client.get(
        f"/api/v1/ai/conversations/{conv_id}",
        headers=auth_headers_user_a,
    )
    assert verify_del.status_code == 404


# ---------------------------------------------------------------------------
# Feature 2: Related Memories Tests
# ---------------------------------------------------------------------------

def test_related_memories_discovery(client, auth_headers_user_a):
    _seed_test_memories(client, auth_headers_user_a)

    # Note 1: PostgreSQL Database Architecture
    res = client.get(
        "/api/v1/ai/notes/mem-1/related",
        headers=auth_headers_user_a,
    )
    assert res.status_code == 200
    data = res.json()
    assert data["note_id"] == "mem-1"
    related = data["related"]
    assert len(related) > 0

    # Note 2 (SQLite Local Persistence) should be related since both share 'database' tag and themes
    related_ids = [r["note_id"] for r in related]
    assert "mem-2" in related_ids

    # Explanation must be present and informative
    item_mem_2 = next(r for r in related if r["note_id"] == "mem-2")
    assert item_mem_2["similarity"] > 0.0
    assert len(item_mem_2["explanation"]) > 5
    assert "database" in item_mem_2["shared_tags"] or "database" in item_mem_2["explanation"].lower()


# ---------------------------------------------------------------------------
# Feature 3: Memory Recap Tests
# ---------------------------------------------------------------------------

def test_memory_recap_weekly_and_categories(client, auth_headers_user_a):
    _seed_test_memories(client, auth_headers_user_a)

    res = client.get(
        "/api/v1/ai/recap?period=weekly",
        headers=auth_headers_user_a,
    )
    assert res.status_code == 200
    data = res.json()

    assert data["period"] == "weekly"
    assert data["total_notes"] == 6
    assert len(data["categories"]) > 0

    # Categories should identify Projects, Learning, Decisions, Ideas
    category_names = [c["category"] for c in data["categories"]]
    assert any(c in category_names for c in ["Learning", "Important Decisions", "Ideas", "Projects"])

    # Important decisions and unfinished ideas should be extracted
    assert len(data["important_decisions"]) > 0
    assert len(data["unfinished_ideas"]) > 0
    assert any("explore" in idea.lower() or "graph" in idea.lower() for idea in data["unfinished_ideas"])


def test_memory_recap_empty_period(client, auth_headers_user_a):
    # Empty user with no notes in custom past date range
    past_start = (datetime.now(timezone.utc) - timedelta(days=200)).isoformat()
    past_end = (datetime.now(timezone.utc) - timedelta(days=190)).isoformat()

    res = client.get(
        f"/api/v1/ai/recap?period=custom&start_date={past_start}&end_date={past_end}",
        headers=auth_headers_user_a,
    )
    assert res.status_code == 200
    data = res.json()
    assert data["total_notes"] == 0
    assert len(data["categories"]) == 0
    assert "no notes" in data["overview"].lower()


# ---------------------------------------------------------------------------
# Feature 4: Ask Across Memories (Comparisons & Contradictions)
# ---------------------------------------------------------------------------

def test_ask_across_memories_detects_decision_change(client, auth_headers_user_a):
    _seed_test_memories(client, auth_headers_user_a)

    # Ask about cloud provider changes over time (AWS vs GCP)
    res = client.post(
        "/api/v1/ai/ask",
        json={"query": "What changed in my cloud provider strategy?"},
        headers=auth_headers_user_a,
    )
    assert res.status_code == 200
    data = res.json()
    assert data["has_sufficient_evidence"] is True
    answer = data["answer"]
    # Should capture both AWS and Google Cloud Platform / revision
    assert "AWS" in answer
    assert "Google Cloud" in answer or "GCP" in answer or "revised" in answer.lower()
    assert len(data["citations"]) >= 2


def test_ask_across_memories_comparison(client, auth_headers_user_a):
    _seed_test_memories(client, auth_headers_user_a)

    res = client.post(
        "/api/v1/ai/ask",
        json={"query": "Compare PostgreSQL and SQLite in my project."},
        headers=auth_headers_user_a,
    )
    assert res.status_code == 200
    data = res.json()
    assert data["has_sufficient_evidence"] is True
    answer = data["answer"]
    assert "PostgreSQL" in answer
    assert "SQLite" in answer
    assert len(data["citations"]) >= 2


# ---------------------------------------------------------------------------
# Strict Multi-Tenant Isolation Tests
# ---------------------------------------------------------------------------

def test_advanced_ai_user_isolation(client, auth_headers_user_a, auth_headers_user_b):
    _seed_test_memories(client, auth_headers_user_a)

    # 1. User A creates a conversation
    create_res = client.post(
        "/api/v1/ai/conversations",
        json={"title": "Private Chat A"},
        headers=auth_headers_user_a,
    )
    conv_id = create_res.json()["id"]

    # User B cannot access User A's conversation
    get_res = client.get(
        f"/api/v1/ai/conversations/{conv_id}",
        headers=auth_headers_user_b,
    )
    assert get_res.status_code == 404

    # User B cannot post message to User A's conversation
    msg_res = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "Hello?"},
        headers=auth_headers_user_b,
    )
    assert msg_res.status_code == 404

    # User B cannot delete User A's conversation
    del_res = client.delete(
        f"/api/v1/ai/conversations/{conv_id}",
        headers=auth_headers_user_b,
    )
    assert del_res.status_code == 404

    # User B cannot get related notes for User A's note
    rel_res = client.get(
        "/api/v1/ai/notes/mem-1/related",
        headers=auth_headers_user_b,
    )
    assert rel_res.status_code == 404

    # User B gets empty recap
    recap_b = client.get(
        "/api/v1/ai/recap?period=weekly",
        headers=auth_headers_user_b,
    )
    assert recap_b.status_code == 200
    assert recap_b.json()["total_notes"] == 0


def test_conversational_greetings_and_chit_chat(client, auth_headers_user_a):
    """
    Verifies that Zuri naturally responds to greetings, identity, well-being,
    gratitude, and farewells without returning 'insufficient information'.
    """
    conv_res = client.post(
        "/api/v1/ai/conversations",
        json={"title": "Chit Chat Test"},
        headers=auth_headers_user_a,
    )
    assert conv_res.status_code == 201
    conv_id = conv_res.json()["id"]

    # 1. Greeting
    msg1 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "Hello!"},
        headers=auth_headers_user_a,
    )
    assert msg1.status_code == 201
    reply1 = msg1.json()["assistant_message"]
    assert "Zuri" in reply1["content"]
    assert reply1["has_sufficient_evidence"] is True
    assert len(reply1["citations"]) == 0

    # 2. Who are you / What can you do
    msg2 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "Who are you?"},
        headers=auth_headers_user_a,
    )
    assert msg2.status_code == 201
    reply2 = msg2.json()["assistant_message"]
    assert "Zuri" in reply2["content"]
    assert "assistant" in reply2["content"].lower()

    # 3. How are you
    msg3 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "How are you doing today?"},
        headers=auth_headers_user_a,
    )
    assert msg3.status_code == 201
    assert "doing great" in msg3.json()["assistant_message"]["content"].lower() or "doing well" in msg3.json()["assistant_message"]["content"].lower()

    # 4. Thank you
    msg4 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "Thank you so much!"},
        headers=auth_headers_user_a,
    )
    assert msg4.status_code == 201
    assert "welcome" in msg4.json()["assistant_message"]["content"].lower()

    # 5. Farewell
    msg5 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "Goodbye, see you later!"},
        headers=auth_headers_user_a,
    )
    assert msg5.status_code == 201
    assert "goodbye" in msg5.json()["assistant_message"]["content"].lower()

    # 6. Exact greeting with emoji and "hi"
    msg6 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "Say hello to Zuri 👋"},
        headers=auth_headers_user_a,
    )
    assert msg6.status_code == 201
    reply6 = msg6.json()["assistant_message"]
    assert reply6["has_sufficient_evidence"] is True
    assert len(reply6["citations"]) == 0
    assert "Zuri" in reply6["content"]

    msg7 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "hi"},
        headers=auth_headers_user_a,
    )
    assert msg7.status_code == 201
    reply7 = msg7.json()["assistant_message"]
    assert reply7["has_sufficient_evidence"] is True
    assert len(reply7["citations"]) == 0
    assert "Zuri" in reply7["content"] or "hello" in reply7["content"].lower()

    # 7. Agent Intent: Writing assistance ("i want to write something")
    msg8 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "i want to write something"},
        headers=auth_headers_user_a,
    )
    assert msg8.status_code == 201
    reply8 = msg8.json()["assistant_message"]
    assert reply8["has_sufficient_evidence"] is True
    assert len(reply8["citations"]) == 0
    assert "write" in reply8["content"].lower() or "help" in reply8["content"].lower()

    # 8. Agent Intent: Schedule generation ("i want you to write me scedule i have at 9 pm")
    msg9 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "i want you to write me scedule i have at 9 pm"},
        headers=auth_headers_user_a,
    )
    assert msg9.status_code == 201
    reply9 = msg9.json()["assistant_message"]
    assert reply9["has_sufficient_evidence"] is True
    assert len(reply9["citations"]) == 0
    assert "schedule" in reply9["content"].lower()
    assert "9 pm" in reply9["content"].lower() or "9:00" in reply9["content"]


def test_agent_schedule_clarification_and_approval_flow(client, auth_headers_user_a):
    """
    Tests the complete user journey:
    1. User requests schedule without specifying activities.
    2. Agent asks user what they have planned instead of hallucinating.
    3. User provides actual activities.
    4. Agent drafts the schedule and asks for approval ("Reply 'approve' to save it").
    5. User replies 'approve'.
    6. Agent confirms save, and the note is created in the user's database.
    """
    # 1. Start conversation
    conv_res = client.post(
        "/api/v1/ai/conversations",
        json={"title": "Schedule Planning"},
        headers=auth_headers_user_a,
    )
    assert conv_res.status_code == 201
    conv_id = conv_res.json()["id"]

    # 2. Step 1: User asks for schedule without activities
    turn1 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "i want you to write me scedule i have at 9 pm"},
        headers=auth_headers_user_a,
    )
    assert turn1.status_code == 201
    ans1 = turn1.json()["assistant_message"]["content"]
    # Agent MUST ask what user has planned, not invent fake deep work activities
    assert "what do you have planned" in ans1.lower()
    assert "9" in ans1

    # 3. Step 2: User provides their activities
    turn2 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "team meeting, code review, then dinner with family"},
        headers=auth_headers_user_a,
    )
    assert turn2.status_code == 201
    ans2 = turn2.json()["assistant_message"]["content"]
    assert "team meeting" in ans2.lower()
    assert "code review" in ans2.lower()
    assert "dinner with family" in ans2.lower()
    assert "approve" in ans2.lower()

    # 4. Step 3: User approves saving to notes
    turn3 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "approve"},
        headers=auth_headers_user_a,
    )
    assert turn3.status_code == 201
    ans3 = turn3.json()["assistant_message"]["content"]
    assert "approved" in ans3.lower()
    assert "saved this to your notes" in ans3.lower()

    # 5. Verify note was created in the database
    notes_res = client.get("/api/v1/notes", headers=auth_headers_user_a)
    assert notes_res.status_code == 200
    user_notes = notes_res.json()["items"]
    schedule_notes = [n for n in user_notes if "schedule" in n["title"].lower() or "team meeting" in n["content"].lower()]
    assert len(schedule_notes) >= 1
    saved_note = schedule_notes[0]
    assert "team meeting" in saved_note["content"].lower()
    assert "code review" in saved_note["content"].lower()

    # 6. Step 4: User appends another item: "also add i have grocery too"
    turn4 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "also add i have grocery too"},
        headers=auth_headers_user_a,
    )
    assert turn4.status_code == 201
    ans4 = turn4.json()["assistant_message"]["content"]
    assert "grocery" in ans4.lower()
    assert "team meeting" in ans4.lower() or "dinner" in ans4.lower()
    assert "approve" in ans4.lower()

    # 7. Step 5: User approves updated note
    turn5 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "approve"},
        headers=auth_headers_user_a,
    )
    assert turn5.status_code == 201
    ans5 = turn5.json()["assistant_message"]["content"]
    assert "approved" in ans5.lower()

    # Verify updated note in database includes grocery
    notes_res2 = client.get("/api/v1/notes", headers=auth_headers_user_a)
    assert notes_res2.status_code == 200
    updated_schedule_notes = [n for n in notes_res2.json()["items"] if "schedule" in n["title"].lower()]
    assert len(updated_schedule_notes) >= 1
    assert "grocery" in updated_schedule_notes[0]["content"].lower()


def test_agent_intent_create_note_schedule_colloquial(client, auth_headers_user_a):
    """
    Test user query with typos and colloquial phrasing:
    'create mea note which chedule my meeting at 5'
    Should recognize schedule intent without failing with 'insufficient information',
    draft the schedule with 5:00 and Meeting, and allow saving upon approval.
    """
    create_conv = client.post(
        "/api/v1/ai/conversations",
        json={"title": "Colloquial Schedule"},
        headers=auth_headers_user_a,
    )
    assert create_conv.status_code == 201
    conv_id = create_conv.json()["id"]

    turn1 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "create mea note which chedule my meeting at 5"},
        headers=auth_headers_user_a,
    )
    assert turn1.status_code == 201
    ans1 = turn1.json()["assistant_message"]["content"]
    assert "insufficient information" not in ans1.lower()
    assert "5:00" in ans1 or "5" in ans1
    assert "meeting" in ans1.lower()
    assert "approve" in ans1.lower()

    # User approves
    turn2 = client.post(
        f"/api/v1/ai/conversations/{conv_id}/messages",
        json={"query": "approve"},
        headers=auth_headers_user_a,
    )
    assert turn2.status_code == 201
    ans2 = turn2.json()["assistant_message"]["content"]
    assert "approved" in ans2.lower()

    # Verify saved in notes
    notes_res = client.get("/api/v1/notes", headers=auth_headers_user_a)
    assert notes_res.status_code == 200
    matching_notes = [n for n in notes_res.json()["items"] if "5:00 schedule" in n["title"].lower() or "schedule" in n["title"].lower()]
    assert len(matching_notes) >= 1
    assert "meeting" in matching_notes[0]["content"].lower()







