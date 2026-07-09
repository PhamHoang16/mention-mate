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


async def test_resolve_chat_id_returns_id_from_latest_update():
    session = _FakeSession([
        {"ok": True, "result": [{"update_id": 1, "message": {"chat": {"id": 987654321}}}]},
    ])

    chat_id = await resolve_chat_id(session, bot_token="123:abc", max_attempts=3, poll_interval=0)

    assert chat_id == 987654321
    assert session.calls == 1


async def test_resolve_chat_id_retries_until_update_appears():
    session = _FakeSession([
        {"ok": True, "result": []},
        {"ok": True, "result": []},
        {"ok": True, "result": [{"update_id": 2, "message": {"chat": {"id": 42}}}]},
    ])

    chat_id = await resolve_chat_id(session, bot_token="123:abc", max_attempts=3, poll_interval=0)

    assert chat_id == 42
    assert session.calls == 3


async def test_resolve_chat_id_raises_after_max_attempts():
    session = _FakeSession([{"ok": True, "result": []}])

    with pytest.raises(ChatIdNotFoundError):
        await resolve_chat_id(session, bot_token="123:abc", max_attempts=2, poll_interval=0)

    assert session.calls == 2
