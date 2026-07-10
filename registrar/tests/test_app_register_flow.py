import os
import stat
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient
from telethon.errors import RPCError

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
        host_data_root=str(tmp_path / "data"),
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


@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_start_creates_the_users_session_directory(mock_start_login, tmp_path):
    """Regression test: Telethon's SQLiteSession does not create missing
    parent directories itself — without this, /register/start 500s with
    sqlite3.OperationalError: unable to open database file the first time
    a brand-new REGISTRAR_DATA_ROOT is used (e.g. a fresh VPS volume mount).
    """
    mock_start_login.return_value = "hash123"
    client = _client(tmp_path)

    client.post("/register/start", json={
        "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
    })

    user_dir = tmp_path / "data" / "hoangp47"
    assert user_dir.is_dir()
    assert stat.S_IMODE(os.stat(user_dir).st_mode) == 0o700


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


@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_start_reports_telethon_rpc_error_as_400(mock_start_login, tmp_path):
    """Regression: a real tester hit ApiIdInvalidError (mistyped API_ID/HASH)
    and got a bare 500 with no explanation. Telethon's RPCError message
    describes the failure class without echoing back the phone/api_hash
    value, so it's safe to relay directly instead of a generic 500.
    """
    mock_start_login.side_effect = RPCError(
        request=None, message="The api_id/api_hash combination is invalid"
    )
    client = _client(tmp_path)

    response = client.post("/register/start", json={
        "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
    })

    assert response.status_code == 400
    assert "api_id/api_hash combination is invalid" in response.json()["detail"]


@patch("registrar.app.complete_login", new_callable=AsyncMock)
@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_verify_reports_telethon_rpc_error_as_400(mock_start_login, mock_complete_login, tmp_path):
    """Regression: a real tester entered the wrong 2FA password and got a
    bare 500 (PasswordHashInvalidError) with no explanation.
    """
    mock_start_login.return_value = "hash123"
    mock_complete_login.side_effect = RPCError(
        request=None, message="The password (and thus its hash value) you entered is invalid"
    )
    client = _client(tmp_path)
    client.post("/register/start", json={
        "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
    })

    response = client.post("/register/verify", json={"username": "hoangp47", "code": "12345"})

    assert response.status_code == 400
    assert "password" in response.json()["detail"].lower()


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
@patch("registrar.app.complete_login", new_callable=AsyncMock)
@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_finalize_mounts_the_host_path_not_the_container_path(
    mock_start_login, mock_complete_login, mock_resolve_chat_id, mock_orchestrator_cls, mock_send_confirmation, tmp_path,
):
    """Regression: the registrar talks to the HOST's Docker daemon over the
    mounted docker.sock (Docker-outside-of-Docker). A bind-mount source path
    it hands the Docker API is resolved against the HOST filesystem, not
    this container's own namespace — so the per-user container's data
    volume must be built from host_data_root, not data_root. Using data_root
    here silently mounted the wrong (often nonexistent) host directory,
    and the launched container's MentionMate process then failed with
    sqlite3.OperationalError: unable to open database file because the
    Telethon session the registrar had just written wasn't where the
    container's mount pointed.
    """
    mock_start_login.return_value = "hash123"
    mock_resolve_chat_id.return_value = 987654321
    mock_orchestrator = mock_orchestrator_cls.return_value
    mock_orchestrator.start_user_container.return_value = "container-id"

    app = create_app(
        bot_token="123:abc",
        data_root=str(tmp_path / "container-side-data"),
        host_data_root=str(tmp_path / "actual-host-data"),
        registrations_path=str(tmp_path / "registrations.json"),
        docker_client=None,
        image="ghcr.io/phamhoang16/mention-mate:latest",
        stagger_seconds=0,
    )
    client = TestClient(app)
    client.post("/register/start", json={
        "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
    })
    client.post("/register/verify", json={"username": "hoangp47", "code": "12345"})

    client.post("/register/finalize", json={"username": "hoangp47"})

    mock_orchestrator.start_user_container.assert_called_once()
    call = mock_orchestrator.start_user_container.call_args
    assert call.args[2] == str(tmp_path / "actual-host-data" / "hoangp47")


@patch("registrar.app.send_confirmation", new_callable=AsyncMock)
@patch("registrar.app.Orchestrator")
@patch("registrar.app.resolve_chat_id", new_callable=AsyncMock)
def test_register_finalize_starts_container(mock_resolve_chat_id, mock_orchestrator_cls, mock_send_confirmation, tmp_path):
    mock_resolve_chat_id.return_value = 987654321
    mock_orchestrator = mock_orchestrator_cls.return_value
    mock_orchestrator.start_user_container.return_value = "container-id"
    client = _logged_in_client(tmp_path)

    response = client.post("/register/finalize", json={"username": "hoangp47"})

    # Fix 2: the request returns immediately (202 queued) instead of blocking
    # for up to stagger_seconds; the actual launch + confirmation happen in a
    # background task. FastAPI's TestClient runs background tasks to
    # completion as part of the same request/response cycle, so we can still
    # assert on their side effects right after client.post() returns.
    assert response.status_code == 202
    assert response.json() == {"status": "queued"}
    mock_orchestrator.start_user_container.assert_called_once()
    call = mock_orchestrator.start_user_container.call_args
    assert call.args[0] == "hoangp47"
    assert call.args[1]["TG_ALERT_CHAT_ID"] == "987654321"
    assert call.args[1]["TG_BOT_TOKEN"] == "123:abc"
    mock_send_confirmation.assert_called_once()
    confirm_call = mock_send_confirmation.call_args
    assert confirm_call.kwargs["bot_token"] == "123:abc"
    assert confirm_call.kwargs["chat_id"] == 987654321
    # Fix 4: successful finalize still cleans up the in-memory PENDING entry.
    assert "hoangp47" not in PENDING


@patch("registrar.app.send_confirmation", new_callable=AsyncMock)
@patch("registrar.app.Orchestrator")
@patch("registrar.app.resolve_chat_id", new_callable=AsyncMock)
def test_register_finalize_completes_registration_even_if_confirmation_dm_fails(
    mock_resolve_chat_id, mock_orchestrator_cls, mock_send_confirmation, tmp_path
):
    """Fix 3: send_confirmation failing (e.g. Bot API returns non-ok) must not
    abort a registration whose container already launched successfully."""
    mock_resolve_chat_id.return_value = 987654321
    mock_orchestrator = mock_orchestrator_cls.return_value
    mock_orchestrator.start_user_container.return_value = "container-id"
    mock_send_confirmation.side_effect = RuntimeError("Bot API error sending confirmation: {'ok': False}")
    client = _logged_in_client(tmp_path)

    response = client.post("/register/finalize", json={"username": "hoangp47"})

    assert response.status_code == 202
    mock_orchestrator.start_user_container.assert_called_once()
    # Registration bookkeeping still completes despite the DM failure.
    assert "hoangp47" not in PENDING


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
