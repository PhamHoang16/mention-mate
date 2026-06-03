"""Resolve a Telegram message permalink for a chat object.

Centralises Telethon's URL discrimination so the rest of the codebase can
stay free of telethon.tl.types imports. The only module in mention_mate
that knows about Telethon TL types.

URL forms:
    Channel + public username → https://t.me/{username}/{message_id}
    Channel + private         → https://t.me/c/{chat.id}/{message_id}
    Chat (basic group)        → https://t.me/c/{chat.id}/{message_id}
    User (1-1 DM)             → tg://user?id={sender.id}   (sender required)
    Migrated Chat / unknown   → None

The t.me/c/<id>/<msg> deep link jumps straight to the message and is clickable
on every client, including Telegram Web. It resolves for basic groups (Chat) as
well as supergroups/channels — the bare chat id is all Telegram needs. We use it
for both rather than tg://openmessage, which only opens the chat (no message
jump) and renders as inert text on the Web client.

Migrated basic groups are the exception: their live messages now live on the
linked supergroup, so a t.me/c link built from the old basic-group id would be
dead — we return None instead.
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
        # Basic group migrated to a supergroup — the live messages now live on
        # the migrated_to peer, so a t.me/c link from the old id would be dead;
        # we'd rather link nothing.
        if getattr(chat, "migrated_to", None):
            return None
        # Same t.me/c jump link as a private channel: it resolves for basic
        # groups too and is clickable on every client (incl. Web).
        return f"https://t.me/c/{chat.id}/{message_id}"
    if isinstance(chat, User) and sender is not None:
        return f"tg://user?id={sender.id}"
    return None
