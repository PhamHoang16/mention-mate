"""Tests for permalink_resolver.

Telethon's Channel/Chat/User classes have many required constructor args,
so we build fakes via ``cls.__new__(cls)`` and set only the attributes the
resolver actually reads. The resulting object IS a real Channel/Chat/User
for ``isinstance`` purposes, but every attribute is explicit — typo-safe
in a way MagicMock isn't.
"""
from telethon.tl.types import Channel, Chat, User

from mention_mate.permalink_resolver import resolve_message_link


def _fake_channel(*, id: int = 0, username: str | None = None) -> Channel:
    obj = Channel.__new__(Channel)
    obj.id = id
    obj.username = username
    return obj


def _fake_chat(*, id: int = 0, migrated_to=None) -> Chat:
    obj = Chat.__new__(Chat)
    obj.id = id
    obj.migrated_to = migrated_to
    return obj


def _fake_user(*, id: int = 0) -> User:
    obj = User.__new__(User)
    obj.id = id
    return obj


def test_supergroup_with_username():
    chat = _fake_channel(id=12345, username="ai_team")
    assert resolve_message_link(chat, 99) == "https://t.me/ai_team/99"


def test_supergroup_without_username():
    chat = _fake_channel(id=12345, username=None)
    assert resolve_message_link(chat, 99) == "https://t.me/c/12345/99"


def test_supergroup_empty_string_username():
    # Empty string is falsy → falls through to the bare-ID branch.
    chat = _fake_channel(id=12345, username="")
    assert resolve_message_link(chat, 99) == "https://t.me/c/12345/99"


def test_basic_group_uses_tme_jump_link():
    # Basic groups (Chat) get the same t.me/c jump link as private channels;
    # it resolves for basic groups too and is clickable on every client.
    chat = _fake_chat(id=12345)
    assert resolve_message_link(chat, 99) == "https://t.me/c/12345/99"


def test_migrated_basic_group_returns_none():
    # A basic group migrated to a supergroup: live messages live on the new
    # peer, so the old-id link would be dead — return None.
    chat = _fake_chat(id=12345, migrated_to=object())
    assert resolve_message_link(chat, 99) is None


def test_dm_returns_none():
    chat = _fake_user(id=42)
    assert resolve_message_link(chat, 99) is None


def test_none_chat_returns_none():
    assert resolve_message_link(None, 99) is None
