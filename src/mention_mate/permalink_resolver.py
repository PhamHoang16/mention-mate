"""Resolve a Telegram message permalink for a chat object.

Centralises Telethon's t.me URL discrimination so the rest of the
codebase can stay free of telethon.tl.types imports. The only module
in mention_mate that knows about Telethon TL types.

URL forms:
    Channel + public username → https://t.me/{username}/{message_id}
    Channel + private         → https://t.me/c/{chat.id}/{message_id}
    Chat (basic group) / User → None (Telegram has no permalink scheme)

Telegram's t.me/c/<id> path only resolves for Channel (supergroups,
megagroups, broadcast channels). For Chat (basic groups) it lands on an
unrelated channel and shows "no permission". Returning None lets the
caller substitute a fallback hint instead of emitting a broken link.
"""
from telethon.tl.types import Channel


def resolve_message_link(chat, message_id: int) -> str | None:
    """Return a t.me link for the message, or None if no scheme exists.

    Accepts ``chat`` as a duck-typed object (``object`` rather than a
    specific union) because Telethon's ``event.get_chat()`` returns a
    union and the call site shouldn't need to import each type just to
    pass it through.
    """
    if not isinstance(chat, Channel):
        return None
    username = getattr(chat, "username", None)
    if username:
        return f"https://t.me/{username}/{message_id}"
    return f"https://t.me/c/{chat.id}/{message_id}"
