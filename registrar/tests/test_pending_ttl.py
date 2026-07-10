"""Fix 4: abandoned /register/start entries (phone/api_id/api_hash/
phone_code_hash sitting in the in-memory PENDING dict) must not be kept
forever. A lazy TTL sweep runs on every /register/start call and evicts
anything older than PENDING_TTL_SECONDS.
"""
from unittest.mock import AsyncMock, patch

import pytest

from registrar.app import PENDING, create_app


@pytest.fixture(autouse=True)
def _clear_pending_between_tests():
    PENDING.clear()
    yield
    PENDING.clear()


def _client(tmp_path):
    from fastapi.testclient import TestClient

    app = create_app(
        bot_token="123:abc",
        data_root=str(tmp_path / "data"),
        host_data_root=str(tmp_path / "data"),
        registrations_path=str(tmp_path / "registrations.json"),
        docker_client=None,
        image="ghcr.io/phamhoang16/mention-mate:latest",
        stagger_seconds=0,
    )
    return TestClient(app)


@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_expired_pending_entry_is_evicted_on_next_register_start(mock_start_login, tmp_path):
    mock_start_login.return_value = "hash123"
    client = _client(tmp_path)

    # Simulate an abandoned registration from long ago (older than the TTL).
    PENDING["stale-user"] = {
        "phone": "+84900000001",
        "api_id": 1,
        "api_hash": "leaked-hash",
        "phone_code_hash": "hash-old",
        "nonce": "old-nonce",
        "created_at": 0.0,  # time.monotonic() started long before "now"
    }

    response = client.post("/register/start", json={
        "phone": "+84900000002",
        "api_id": 2,
        "api_hash": "h2",
        "username": "fresh-user",
    })

    assert response.status_code == 200
    assert "stale-user" not in PENDING
    assert "fresh-user" in PENDING


@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_recent_pending_entry_is_not_evicted(mock_start_login, tmp_path):
    import time

    mock_start_login.return_value = "hash123"
    client = _client(tmp_path)

    PENDING["recent-user"] = {
        "phone": "+84900000001",
        "api_id": 1,
        "api_hash": "h1",
        "phone_code_hash": "hash-old",
        "nonce": "recent-nonce",
        "created_at": time.monotonic(),
    }

    client.post("/register/start", json={
        "phone": "+84900000002",
        "api_id": 2,
        "api_hash": "h2",
        "username": "fresh-user-2",
    })

    assert "recent-user" in PENDING
