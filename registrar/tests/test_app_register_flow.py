from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from registrar.app import PENDING, create_app
from registrar.telegram_login import TwoFactorRequired


@pytest.fixture(autouse=True)
def _clear_pending_between_tests():
    # PENDING is a module-level dict (deliberately not persisted — see app.py).
    # Several tests below reuse the same username ("hoangp47"), so without
    # this the /register/finalize error-path tests (which don't delete their
    # PENDING entry) leak "logged_in" state into later tests and make the
    # suite order-dependent.
    PENDING.clear()
    yield
    PENDING.clear()


def _client(tmp_path):
    app = create_app(
        bot_token="123:abc",
        data_root=str(tmp_path / "data"),
        registrations_path=str(tmp_path / "registrations.json"),
        docker_client=None,  # not exercised in this task's tests
        image="ghcr.io/phamhoang16/mention-mate:latest",
        stagger_seconds=0,
    )
    return TestClient(app)


@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_start_sends_code_and_returns_ok(mock_start_login, tmp_path):
    mock_start_login.return_value = "hash123"
    client = _client(tmp_path)

    response = client.post("/register/start", json={
        "phone": "+84900000000",
        "api_id": 1,
        "api_hash": "h",
        "username": "hoangp47",
    })

    assert response.status_code == 200
    assert response.json() == {"status": "code_sent"}
    mock_start_login.assert_called_once_with(
        api_id=1, api_hash="h", session_path=str(tmp_path / "data" / "hoangp47" / "mentions_session"),
        phone="+84900000000",
    )


@patch("registrar.app.complete_login", new_callable=AsyncMock)
@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_verify_completes_login(mock_start_login, mock_complete_login, tmp_path):
    mock_start_login.return_value = "hash123"
    client = _client(tmp_path)
    client.post("/register/start", json={
        "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
    })

    response = client.post("/register/verify", json={"username": "hoangp47", "code": "12345"})

    assert response.status_code == 200
    assert response.json() == {"status": "logged_in"}
    mock_complete_login.assert_called_once_with(
        api_id=1, api_hash="h", session_path=str(tmp_path / "data" / "hoangp47" / "mentions_session"),
        phone="+84900000000", code="12345", phone_code_hash="hash123", password=None,
    )


@patch("registrar.app.complete_login", new_callable=AsyncMock)
@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_verify_reports_two_factor_required(mock_start_login, mock_complete_login, tmp_path):
    mock_start_login.return_value = "hash123"
    mock_complete_login.side_effect = TwoFactorRequired("2FA required")
    client = _client(tmp_path)
    client.post("/register/start", json={
        "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
    })

    response = client.post("/register/verify", json={"username": "hoangp47", "code": "12345"})

    assert response.status_code == 400
    assert response.json()["detail"] == "two_factor_required"


def test_register_verify_without_prior_start_returns_404(tmp_path):
    client = _client(tmp_path)

    response = client.post("/register/verify", json={"username": "nobody", "code": "12345"})

    assert response.status_code == 404


import aiohttp
from unittest.mock import MagicMock, patch

from registrar.chat_id_resolver import ChatIdNotFoundError


def _logged_in_client(tmp_path):
    with patch("registrar.app.start_login", new_callable=AsyncMock) as mock_start:
        mock_start.return_value = "hash123"
        client = _client(tmp_path)
        client.post("/register/start", json={
            "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
        })
    with patch("registrar.app.complete_login", new_callable=AsyncMock):
        client.post("/register/verify", json={"username": "hoangp47", "code": "12345"})
    return client


@patch("registrar.app.send_confirmation", new_callable=AsyncMock)
@patch("registrar.app.Orchestrator")
@patch("registrar.app.resolve_chat_id", new_callable=AsyncMock)
def test_register_finalize_starts_container(mock_resolve_chat_id, mock_orchestrator_cls, mock_send_confirmation, tmp_path):
    mock_resolve_chat_id.return_value = 987654321
    mock_orchestrator = mock_orchestrator_cls.return_value
    mock_orchestrator.start_user_container.return_value = "container-id"
    client = _logged_in_client(tmp_path)

    response = client.post("/register/finalize", json={"username": "hoangp47"})

    assert response.status_code == 200
    assert response.json() == {"status": "active", "container_id": "container-id"}
    mock_orchestrator.start_user_container.assert_called_once()
    call = mock_orchestrator.start_user_container.call_args
    assert call.args[0] == "hoangp47"
    assert call.args[1]["TG_ALERT_CHAT_ID"] == "987654321"
    assert call.args[1]["TG_BOT_TOKEN"] == "123:abc"
    mock_send_confirmation.assert_called_once()
    confirm_call = mock_send_confirmation.call_args
    assert confirm_call.kwargs["bot_token"] == "123:abc"
    assert confirm_call.kwargs["chat_id"] == 987654321


@patch("registrar.app.resolve_chat_id", new_callable=AsyncMock)
def test_register_finalize_returns_409_when_chat_id_not_found(mock_resolve_chat_id, tmp_path):
    mock_resolve_chat_id.side_effect = ChatIdNotFoundError("not found")
    client = _logged_in_client(tmp_path)

    response = client.post("/register/finalize", json={"username": "hoangp47"})

    assert response.status_code == 409
    assert response.json()["detail"] == "chat_id_not_found"


def test_register_finalize_without_completed_login_returns_404(tmp_path):
    client = _client(tmp_path)

    response = client.post("/register/finalize", json={"username": "hoangp47"})

    assert response.status_code == 404
