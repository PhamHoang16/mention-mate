"""Resolves a user's chat_id with the shared alert bot via getUpdates.

The bot is shared across every registering user, so `getUpdates` returns a
mix of everyone's recent messages. We correlate the right chat_id for THIS
registration by having the user send `/start <nonce>` — a unique per-
registration token generated in /register/start — and scanning all updates
in the response for a message containing that nonce, instead of blindly
trusting the most recent update (which could belong to a different user who
happened to message the bot around the same time).
"""
import asyncio


class ChatIdNotFoundError(Exception):
    pass


def _find_chat_id_for_nonce(payload: dict, nonce: str) -> int | None:
    results = payload.get("result") or []
    for item in results:
        message = item.get("message") or item.get("channel_post")
        if not message:
            continue
        text = message.get("text") or ""
        if nonce and nonce in text:
            return message["chat"]["id"]
    return None


async def resolve_chat_id(
    session, bot_token: str, nonce: str, max_attempts: int = 3, poll_interval: float = 2.0
) -> int:
    url = f"https://api.telegram.org/bot{bot_token}/getUpdates"
    for attempt in range(1, max_attempts + 1):
        async with session.get(url) as resp:
            payload = await resp.json()
        chat_id = _find_chat_id_for_nonce(payload, nonce)
        if chat_id is not None:
            return chat_id
        if attempt < max_attempts:
            await asyncio.sleep(poll_interval)
    raise ChatIdNotFoundError(f"Could not detect chat_id for nonce after {max_attempts} attempts")
