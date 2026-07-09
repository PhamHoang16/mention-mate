from unittest.mock import AsyncMock, patch

import pytest
from telethon.errors import SessionPasswordNeededError

from registrar.telegram_login import TwoFactorRequired, complete_login, start_login


@patch("registrar.telegram_login.TelegramClient")
async def test_start_login_returns_phone_code_hash(mock_client_cls):
    client = mock_client_cls.return_value
    client.connect = AsyncMock()
    client.disconnect = AsyncMock()
    client.send_code_request = AsyncMock(return_value=type("Sent", (), {"phone_code_hash": "hash123"})())

    result = await start_login(api_id=1, api_hash="h", session_path="data/hoangp47/session", phone="+84900000000")

    assert result == "hash123"
    client.send_code_request.assert_called_once_with("+84900000000")
    client.connect.assert_called_once()
    client.disconnect.assert_called_once()


@patch("registrar.telegram_login.TelegramClient")
async def test_complete_login_signs_in_with_code(mock_client_cls):
    client = mock_client_cls.return_value
    client.connect = AsyncMock()
    client.disconnect = AsyncMock()
    client.sign_in = AsyncMock()

    await complete_login(
        api_id=1, api_hash="h", session_path="data/hoangp47/session",
        phone="+84900000000", code="12345", phone_code_hash="hash123",
    )

    client.sign_in.assert_called_once_with(phone="+84900000000", code="12345", phone_code_hash="hash123")
    client.disconnect.assert_called_once()


@patch("registrar.telegram_login.TelegramClient")
async def test_complete_login_uses_password_when_2fa_required(mock_client_cls):
    client = mock_client_cls.return_value
    client.connect = AsyncMock()
    client.disconnect = AsyncMock()
    client.sign_in = AsyncMock(side_effect=[SessionPasswordNeededError(request=None), None])

    await complete_login(
        api_id=1, api_hash="h", session_path="data/hoangp47/session",
        phone="+84900000000", code="12345", phone_code_hash="hash123", password="s3cret",
    )

    assert client.sign_in.call_count == 2
    client.sign_in.assert_any_call(password="s3cret")


@patch("registrar.telegram_login.TelegramClient")
async def test_complete_login_raises_two_factor_required_without_password(mock_client_cls):
    client = mock_client_cls.return_value
    client.connect = AsyncMock()
    client.disconnect = AsyncMock()
    client.sign_in = AsyncMock(side_effect=SessionPasswordNeededError(request=None))

    with pytest.raises(TwoFactorRequired):
        await complete_login(
            api_id=1, api_hash="h", session_path="data/hoangp47/session",
            phone="+84900000000", code="12345", phone_code_hash="hash123",
        )

    client.disconnect.assert_called_once()
