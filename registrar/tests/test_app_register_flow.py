from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from registrar.app import create_app
from registrar.telegram_login import TwoFactorRequired


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
