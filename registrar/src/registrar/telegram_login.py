"""Wraps Telethon's interactive OTP login for use from the Web UI instead of
an interactive terminal prompt (compare src/mention_mate/auth.py, which is
the terminal version used by self-hosters).
"""
from telethon import TelegramClient
from telethon.errors import SessionPasswordNeededError


class TwoFactorRequired(Exception):
    pass


async def start_login(api_id: int, api_hash: str, session_path: str, phone: str) -> str:
    client = TelegramClient(session_path, api_id, api_hash)
    await client.connect()
    try:
        sent = await client.send_code_request(phone)
        return sent.phone_code_hash
    finally:
        await client.disconnect()


async def complete_login(
    api_id: int,
    api_hash: str,
    session_path: str,
    phone: str,
    code: str,
    phone_code_hash: str,
    password: str | None = None,
) -> None:
    client = TelegramClient(session_path, api_id, api_hash)
    await client.connect()
    try:
        try:
            await client.sign_in(phone=phone, code=code, phone_code_hash=phone_code_hash)
        except SessionPasswordNeededError:
            if password is None:
                raise TwoFactorRequired("Account has 2FA enabled; password required")
            await client.sign_in(password=password)
    finally:
        await client.disconnect()
