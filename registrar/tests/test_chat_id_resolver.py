import pytest

from registrar.chat_id_resolver import ChatIdNotFoundError, resolve_chat_id


class _FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    async def json(self):
        return self._payload


class _FakeSession:
    def __init__(self, payloads):
        self._payloads = list(payloads)
        self.calls = 0

    def get(self, url):
        payload = self._payloads[min(self.calls, len(self._payloads) - 1)]
        self.calls += 1
        return _FakeResponse(payload)


async def test_resolve_chat_id_returns_id_for_matching_nonce():
    session = _FakeSession([
        {
            "ok": True,
            "result": [
                {"update_id": 1, "message": {"chat": {"id": 987654321}, "text": "/start abc123"}},
            ],
        },
    ])

    chat_id = await resolve_chat_id(session, bot_token="123:abc", nonce="abc123", max_attempts=3, poll_interval=0)

    assert chat_id == 987654321
    assert session.calls == 1


async def test_resolve_chat_id_retries_until_matching_update_appears():
    session = _FakeSession([
        {"ok": True, "result": []},
        {"ok": True, "result": []},
        {"ok": True, "result": [{"update_id": 2, "message": {"chat": {"id": 42}, "text": "/start nonce2"}}]},
    ])

    chat_id = await resolve_chat_id(session, bot_token="123:abc", nonce="nonce2", max_attempts=3, poll_interval=0)

    assert chat_id == 42
    assert session.calls == 3


async def test_resolve_chat_id_raises_after_max_attempts():
    session = _FakeSession([{"ok": True, "result": []}])

    with pytest.raises(ChatIdNotFoundError):
        await resolve_chat_id(session, bot_token="123:abc", nonce="whatever", max_attempts=2, poll_interval=0)

    assert session.calls == 2


async def test_resolve_chat_id_ignores_updates_without_matching_nonce():
    """A message that doesn't mention our nonce must not be mistaken for ours."""
    session = _FakeSession([
        {"ok": True, "result": [{"update_id": 1, "message": {"chat": {"id": 111}, "text": "hello there"}}]},
    ])

    with pytest.raises(ChatIdNotFoundError):
        await resolve_chat_id(session, bot_token="123:abc", nonce="mynonce", max_attempts=1, poll_interval=0)


async def test_resolve_chat_id_picks_correct_user_out_of_two_pending_nonces():
    """Regression test for the cross-assignment bug: two users register close
    together and both message the shared bot. Each registration's
    resolve_chat_id call must return the chat_id matching ITS OWN nonce, not
    whichever update happens to be last in the getUpdates response.
    """
    session = _FakeSession([
        {
            "ok": True,
            "result": [
                {"update_id": 1, "message": {"chat": {"id": 111}, "text": "/start nonce-for-alice"}},
                {"update_id": 2, "message": {"chat": {"id": 222}, "text": "/start nonce-for-bob"}},
            ],
        },
    ])

    alice_chat_id = await resolve_chat_id(
        session, bot_token="123:abc", nonce="nonce-for-alice", max_attempts=1, poll_interval=0
    )
    assert alice_chat_id == 111

    session2 = _FakeSession([
        {
            "ok": True,
            "result": [
                {"update_id": 1, "message": {"chat": {"id": 111}, "text": "/start nonce-for-alice"}},
                {"update_id": 2, "message": {"chat": {"id": 222}, "text": "/start nonce-for-bob"}},
            ],
        },
    ])
    bob_chat_id = await resolve_chat_id(
        session2, bot_token="123:abc", nonce="nonce-for-bob", max_attempts=1, poll_interval=0
    )
    assert bob_chat_id == 222
