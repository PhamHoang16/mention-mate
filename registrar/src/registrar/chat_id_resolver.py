"""Resolves a user's chat_id with the shared alert bot via getUpdates.

Mirrors scripts/mention-mate.sh's discover_chat_id, ported to Python so the
registrar can call it directly instead of shelling out.
"""
import asyncio


class ChatIdNotFoundError(Exception):
    pass


def _extract_latest_chat_id(payload: dict) -> int | None:
    results = payload.get("result") or []
    if not results:
        return None
    last = results[-1]
    message = last.get("message") or last.get("channel_post")
    if not message:
        return None
    return message["chat"]["id"]


async def resolve_chat_id(session, bot_token: str, max_attempts: int = 3, poll_interval: float = 2.0) -> int:
    url = f"https://api.telegram.org/bot{bot_token}/getUpdates"
    for attempt in range(1, max_attempts + 1):
        async with session.get(url) as resp:
            payload = await resp.json()
        chat_id = _extract_latest_chat_id(payload)
        if chat_id is not None:
            return chat_id
        if attempt < max_attempts:
            await asyncio.sleep(poll_interval)
    raise ChatIdNotFoundError(f"Could not detect chat_id after {max_attempts} attempts")
