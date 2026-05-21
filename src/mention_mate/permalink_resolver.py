"""Resolve a Telegram message permalink for a chat object.

Centralises Telethon's URL discrimination so the rest of the codebase can
stay free of telethon.tl.types imports. The only module in mention_mate
that knows about Telethon TL types.

URL forms:
    Channel + public username → https://t.me/{username}/{message_id}
    Channel + private         → https://t.me/c/{chat.id}/{message_id}
    Chat (basic group)        → tg://openmessage?chat_id={chat.id}
    User (1-1 DM)             → tg://user?id={sender.id}   (sender required)
    Migrated Chat / unknown   → None

Telegram's t.me/c/<id> path only resolves for Channel (supergroups, megagroups,
broadcast channels). For Chat (basic groups) it lands on an unrelated channel
and shows "no permission". The tg:// deep-link scheme is honored by iOS,
Android and Desktop clients; the Web client renders it as inert text — still a
strict UX improvement over no link at all.
"""
from telethon.tl.types import Channel, Chat, User


def resolve_message_link(chat, message_id: int, *, sender=None) -> str | None:
    """Return a URL for the message, or None if no scheme exists.

    ``chat`` is duck-typed (``object``) because Telethon's ``event.get_chat()``
    returns a union and the call site shouldn't need to import each TL type
    just to pass it through. ``sender`` is keyword-only so future additions
    can't accidentally collide with the positional signature.
    """
    if isinstance(chat, Channel):
        username = getattr(chat, "username", None)
        if username:
            return f"https://t.me/{username}/{message_id}"
        return f"https://t.me/c/{chat.id}/{message_id}"
    if isinstance(chat, Chat):
        # Basic group migrated to a supergroup — the channel_id lives on
        # the migrated_to peer; we'd rather link nothing than send the user
        # to a dead chat.
        if getattr(chat, "migrated_to", None):
            return None
        return f"tg://openmessage?chat_id={chat.id}"
    if isinstance(chat, User) and sender is not None:
        return f"tg://user?id={sender.id}"
    return None
