# MentionMate Registrar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the new `registrar` service — a Web UI + backend that runs the Telegram OTP login for each team member and automatically spins up their own isolated MentionMate container on the admin's VPS, per `docs/superpowers/specs/2026-07-09-team-rollout-design.md`.

**Architecture:** A small FastAPI app, deployed as its own Docker container (with the host's Docker socket mounted so it can launch sibling containers), backed by six single-purpose modules: env generation, chat-id resolution, JSON-file registration state, a stagger queue, a Docker orchestrator, and a Telethon OTP wrapper. The existing `mention_mate` package (the per-user bot image) is **not modified** by this plan.

**Tech Stack:** Python 3.11, FastAPI + Uvicorn, Telethon 1.33.1 (same as the main app), `docker` (Docker SDK for Python), aiohttp, Jinja2 for the 3 HTML pages, pytest + pytest-asyncio.

## Global Constraints

- Python `>=3.11` (matches the main `mention_mate` package's floor).
- This is a **separate subproject** at `registrar/` with its own `pyproject.toml` — do not add its dependencies (FastAPI, docker SDK, uvicorn) to the root `pyproject.toml`, and do not import from `src/mention_mate/` (the two ship as separate images).
- Per-user containers are launched from the **unmodified** `ghcr.io/phamhoang16/mention-mate:latest` image, using the same env var names as `.env.example` (`TG_API_ID`, `TG_API_HASH`, `TG_MY_USERNAME`, `TG_BOT_TOKEN`, `TG_ALERT_CHAT_ID`) and the same volume convention (host dir bind-mounted to `/app/data`).
- Never log phone numbers, OTP codes, 2FA passwords, `TG_API_HASH`, or `TG_BOT_TOKEN` (per the spec's security section).
- The registrar itself has no public exposure requirement in this plan — it's deployed behind the admin's VPN/internal network (ops concern, documented in Task 10's README, not enforced in code).

---

## Task 1: Registrar project scaffold + env_writer

**Files:**
- Create: `registrar/pyproject.toml`
- Create: `registrar/src/registrar/__init__.py`
- Create: `registrar/src/registrar/env_writer.py`
- Test: `registrar/tests/__init__.py`
- Test: `registrar/tests/test_env_writer.py`

**Interfaces:**
- Produces:
  - `build_env(bot_token: str, api_id: int, api_hash: str, username: str, alert_chat_id: int) -> dict[str, str]`
  - `render_env_file(env: dict[str, str]) -> str`
  - `write_user_env_file(data_root: str, username: str, env: dict[str, str]) -> str` (returns the path written, file created with mode `0o600`)

- [ ] **Step 1: Write the failing test**

Create `registrar/tests/test_env_writer.py`:

```python
import os
import stat

from registrar.env_writer import build_env, render_env_file, write_user_env_file


def test_build_env_returns_expected_keys():
    env = build_env(
        bot_token="123:abc",
        api_id=555111,
        api_hash="deadbeef",
        username="hoangp47",
        alert_chat_id=987654321,
    )
    assert env == {
        "TG_API_ID": "555111",
        "TG_API_HASH": "deadbeef",
        "TG_MY_USERNAME": "hoangp47",
        "TG_BOT_TOKEN": "123:abc",
        "TG_ALERT_CHAT_ID": "987654321",
    }


def test_render_env_file_is_stable_and_ordered():
    env = {
        "TG_API_ID": "555111",
        "TG_API_HASH": "deadbeef",
        "TG_MY_USERNAME": "hoangp47",
        "TG_BOT_TOKEN": "123:abc",
        "TG_ALERT_CHAT_ID": "987654321",
    }
    content = render_env_file(env)
    assert content == (
        "TG_API_ID=555111\n"
        "TG_API_HASH=deadbeef\n"
        "TG_MY_USERNAME=hoangp47\n"
        "TG_BOT_TOKEN=123:abc\n"
        "TG_ALERT_CHAT_ID=987654321\n"
    )


def test_write_user_env_file_creates_file_with_restrictive_permissions(tmp_path):
    env = build_env(
        bot_token="123:abc",
        api_id=555111,
        api_hash="deadbeef",
        username="hoangp47",
        alert_chat_id=987654321,
    )
    path = write_user_env_file(str(tmp_path), "hoangp47", env)

    assert path == str(tmp_path / "hoangp47" / ".env")
    with open(path) as f:
        assert f.read() == render_env_file(env)

    file_mode = stat.S_IMODE(os.stat(path).st_mode)
    assert file_mode == 0o600

    dir_mode = stat.S_IMODE(os.stat(tmp_path / "hoangp47").st_mode)
    assert dir_mode == 0o700
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd registrar && python -m pytest tests/test_env_writer.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'registrar'`

- [ ] **Step 3: Write the scaffold and implementation**

Create `registrar/pyproject.toml`:

```toml
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "mention-mate-registrar"
version = "0.1.0"
description = "Team registration Web UI + orchestrator for MentionMate"
requires-python = ">=3.11"
license = { text = "MIT" }
dependencies = [
    "fastapi==0.115.0",
    "uvicorn[standard]==0.32.0",
    "telethon==1.33.1",
    "aiohttp==3.9.5",
    "docker==7.1.0",
    "jinja2==3.1.4",
]

[project.optional-dependencies]
dev = ["pytest>=8", "pytest-asyncio>=0.24", "httpx>=0.27"]

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
```

Create `registrar/src/registrar/__init__.py` (empty file).

Create `registrar/src/registrar/env_writer.py`:

```python
"""Builds the per-user .env content handed to a MentionMate container.

Keys/order here MUST match .env.example in the repo root — this is what
gets written to disk and passed as the container's environment.
"""
import os
import stat
from pathlib import Path


def build_env(bot_token: str, api_id: int, api_hash: str, username: str, alert_chat_id: int) -> dict[str, str]:
    return {
        "TG_API_ID": str(api_id),
        "TG_API_HASH": api_hash,
        "TG_MY_USERNAME": username,
        "TG_BOT_TOKEN": bot_token,
        "TG_ALERT_CHAT_ID": str(alert_chat_id),
    }


def render_env_file(env: dict[str, str]) -> str:
    return "".join(f"{key}={value}\n" for key, value in env.items())


def write_user_env_file(data_root: str, username: str, env: dict[str, str]) -> str:
    user_dir = Path(data_root) / username
    user_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(user_dir, stat.S_IRWXU)  # 0o700 — session dir holds a live Telethon session
    env_path = user_dir / ".env"
    env_path.write_text(render_env_file(env))
    os.chmod(env_path, stat.S_IRUSR | stat.S_IWUSR)  # 0o600
    return str(env_path)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd registrar && pip install -e ".[dev]" && python -m pytest tests/test_env_writer.py -v`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add registrar/pyproject.toml registrar/src/registrar/__init__.py \
        registrar/src/registrar/env_writer.py registrar/tests/__init__.py \
        registrar/tests/test_env_writer.py
git commit -m "feat(registrar): scaffold project and add env_writer"
```

---

## Task 2: chat_id_resolver

**Files:**
- Create: `registrar/src/registrar/chat_id_resolver.py`
- Test: `registrar/tests/test_chat_id_resolver.py`

**Interfaces:**
- Consumes: nothing from prior tasks.
- Produces:
  - `class ChatIdNotFoundError(Exception)`
  - `async def resolve_chat_id(session, bot_token: str, max_attempts: int = 3, poll_interval: float = 2.0) -> int` — polls the Bot API's `getUpdates`, returns the `chat.id` of the most recent update. `session` must expose an async-context-manager `.get(url)` returning an object with an async `.json()` method (the `aiohttp.ClientSession` shape).

This ports the retry logic already used by `scripts/mention-mate.sh`'s `discover_chat_id` (requires the user to have already sent `/start` to the shared bot before this is called).

- [ ] **Step 1: Write the failing test**

Create `registrar/tests/test_chat_id_resolver.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd registrar && python -m pytest tests/test_chat_id_resolver.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'registrar.chat_id_resolver'`

- [ ] **Step 3: Write the implementation**

Create `registrar/src/registrar/chat_id_resolver.py`:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd registrar && python -m pytest tests/test_chat_id_resolver.py -v`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add registrar/src/registrar/chat_id_resolver.py registrar/tests/test_chat_id_resolver.py
git commit -m "feat(registrar): add chat_id_resolver"
```

---

## Task 3: RegistrationStore

**Files:**
- Create: `registrar/src/registrar/store.py`
- Test: `registrar/tests/test_store.py`

**Interfaces:**
- Consumes: nothing from prior tasks.
- Produces: `class RegistrationStore: def __init__(self, path: str); async def get(self, username: str) -> dict | None; async def set(self, username: str, record: dict) -> None`

- [ ] **Step 1: Write the failing test**

Create `registrar/tests/test_store.py`:

```python
from registrar.store import RegistrationStore


async def test_get_returns_none_when_absent(tmp_path):
    store = RegistrationStore(str(tmp_path / "registrations.json"))
    assert await store.get("hoangp47") is None


async def test_set_then_get_roundtrips(tmp_path):
    store = RegistrationStore(str(tmp_path / "registrations.json"))
    await store.set("hoangp47", {"status": "active", "chat_id": 42})

    record = await store.get("hoangp47")

    assert record == {"status": "active", "chat_id": 42}


async def test_state_persists_across_new_store_instances(tmp_path):
    path = str(tmp_path / "registrations.json")
    store_a = RegistrationStore(path)
    await store_a.set("hoangp47", {"status": "active"})

    store_b = RegistrationStore(path)
    record = await store_b.get("hoangp47")

    assert record == {"status": "active"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd registrar && python -m pytest tests/test_store.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'registrar.store'`

- [ ] **Step 3: Write the implementation**

Create `registrar/src/registrar/store.py`:

```python
"""Tiny JSON-file registration store — fine at the team's scale (10-20 users),
avoids adding a database dependency for what is a small key-value map.
"""
import asyncio
import json
from pathlib import Path


class RegistrationStore:
    def __init__(self, path: str):
        self._path = Path(path)
        self._lock = asyncio.Lock()
        if not self._path.exists():
            self._path.parent.mkdir(parents=True, exist_ok=True)
            self._path.write_text("{}")

    async def get(self, username: str) -> dict | None:
        async with self._lock:
            data = json.loads(self._path.read_text())
            return data.get(username)

    async def set(self, username: str, record: dict) -> None:
        async with self._lock:
            data = json.loads(self._path.read_text())
            data[username] = record
            self._path.write_text(json.dumps(data, indent=2))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd registrar && python -m pytest tests/test_store.py -v`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add registrar/src/registrar/store.py registrar/tests/test_store.py
git commit -m "feat(registrar): add JSON-file RegistrationStore"
```

---

## Task 4: StaggerQueue

**Files:**
- Create: `registrar/src/registrar/queue.py`
- Test: `registrar/tests/test_queue.py`

**Interfaces:**
- Consumes: nothing from prior tasks.
- Produces: `class StaggerQueue: def __init__(self, min_interval_seconds: float, clock=time.monotonic, sleep=asyncio.sleep); async def run(self, job)` where `job` is a zero-arg async callable; `run` awaits `job()` and returns its result, serializing calls so consecutive jobs are at least `min_interval_seconds` apart.

- [ ] **Step 1: Write the failing test**

Create `registrar/tests/test_queue.py`:

```python
from registrar.queue import StaggerQueue


class _FakeClock:
    def __init__(self, start=0.0):
        self.now = start

    def __call__(self):
        return self.now


class _FakeSleep:
    def __init__(self, clock):
        self._clock = clock
        self.calls = []

    async def __call__(self, seconds):
        self.calls.append(seconds)
        self._clock.now += seconds


async def test_first_job_runs_without_waiting():
    clock = _FakeClock()
    sleep = _FakeSleep(clock)
    queue = StaggerQueue(min_interval_seconds=600, clock=clock, sleep=sleep)

    result = await queue.run(lambda: _immediate("first"))

    assert result == "first"
    assert sleep.calls == []


async def test_second_job_waits_out_remaining_interval():
    clock = _FakeClock()
    sleep = _FakeSleep(clock)
    queue = StaggerQueue(min_interval_seconds=600, clock=clock, sleep=sleep)

    await queue.run(lambda: _immediate("first"))
    clock.now += 100  # only 100s elapsed since the first job
    result = await queue.run(lambda: _immediate("second"))

    assert result == "second"
    assert sleep.calls == [500]  # needed to wait out the remaining 500s


async def test_job_run_after_interval_has_elapsed_does_not_wait():
    clock = _FakeClock()
    sleep = _FakeSleep(clock)
    queue = StaggerQueue(min_interval_seconds=600, clock=clock, sleep=sleep)

    await queue.run(lambda: _immediate("first"))
    clock.now += 700  # more than the interval has passed
    result = await queue.run(lambda: _immediate("second"))

    assert result == "second"
    assert sleep.calls == []


async def _immediate(value):
    return value
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd registrar && python -m pytest tests/test_queue.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'registrar.queue'`

- [ ] **Step 3: Write the implementation**

Create `registrar/src/registrar/queue.py`:

```python
"""Serializes registration jobs with a minimum gap between each one, so
several people registering close together don't create a burst of new
Telegram sessions from the same VPS IP.
"""
import asyncio
import time


class StaggerQueue:
    def __init__(self, min_interval_seconds: float, clock=time.monotonic, sleep=asyncio.sleep):
        self._min_interval = min_interval_seconds
        self._clock = clock
        self._sleep = sleep
        self._lock = asyncio.Lock()
        self._last_run_at: float | None = None

    async def run(self, job):
        async with self._lock:
            if self._last_run_at is not None:
                elapsed = self._clock() - self._last_run_at
                wait_for = self._min_interval - elapsed
                if wait_for > 0:
                    await self._sleep(wait_for)
            result = await job()
            self._last_run_at = self._clock()
            return result
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd registrar && python -m pytest tests/test_queue.py -v`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add registrar/src/registrar/queue.py registrar/tests/test_queue.py
git commit -m "feat(registrar): add StaggerQueue for spaced-out registrations"
```

---

## Task 5: Orchestrator (Docker SDK wrapper)

**Files:**
- Create: `registrar/src/registrar/orchestrator.py`
- Test: `registrar/tests/test_orchestrator.py`

**Interfaces:**
- Consumes: env dict shape from Task 1's `build_env` (keys `TG_API_ID`, `TG_API_HASH`, `TG_MY_USERNAME`, `TG_BOT_TOKEN`, `TG_ALERT_CHAT_ID`, all string values).
- Produces: `class Orchestrator: def __init__(self, client, image: str); def container_name(self, username: str) -> str; def start_user_container(self, username: str, env: dict[str, str], data_dir: str) -> str` (returns container id); `def stop_user_container(self, username: str) -> None`. `client` is a `docker.DockerClient`-shaped object (`client.containers.run/get`, and `container.remove`).

- [ ] **Step 1: Write the failing test**

Create `registrar/tests/test_orchestrator.py`:

```python
from unittest.mock import MagicMock

import docker.errors

from registrar.orchestrator import Orchestrator


def test_container_name_is_prefixed_with_username():
    orchestrator = Orchestrator(client=MagicMock(), image="ghcr.io/phamhoang16/mention-mate:latest")
    assert orchestrator.container_name("hoangp47") == "mention-mate-hoangp47"


def test_start_user_container_runs_with_expected_kwargs(tmp_path):
    client = MagicMock()
    client.containers.get.side_effect = docker.errors.NotFound("no such container")
    client.containers.run.return_value = MagicMock(id="abc123")
    orchestrator = Orchestrator(client=client, image="ghcr.io/phamhoang16/mention-mate:latest")
    env = {"TG_API_ID": "555", "TG_MY_USERNAME": "hoangp47"}
    data_dir = str(tmp_path / "hoangp47")

    container_id = orchestrator.start_user_container("hoangp47", env, data_dir)

    assert container_id == "abc123"
    client.containers.run.assert_called_once_with(
        "ghcr.io/phamhoang16/mention-mate:latest",
        name="mention-mate-hoangp47",
        detach=True,
        restart_policy={"Name": "unless-stopped"},
        environment=env,
        volumes={data_dir: {"bind": "/app/data", "mode": "rw"}},
        log_config=docker.types.LogConfig(type="json-file", config={"max-size": "10m", "max-file": "3"}),
    )


def test_start_user_container_removes_existing_container_first(tmp_path):
    client = MagicMock()
    existing = MagicMock()
    client.containers.get.return_value = existing
    client.containers.run.return_value = MagicMock(id="new-id")
    orchestrator = Orchestrator(client=client, image="ghcr.io/phamhoang16/mention-mate:latest")

    orchestrator.start_user_container("hoangp47", {}, str(tmp_path))

    existing.remove.assert_called_once_with(force=True)


def test_stop_user_container_removes_when_present():
    client = MagicMock()
    existing = MagicMock()
    client.containers.get.return_value = existing
    orchestrator = Orchestrator(client=client, image="ghcr.io/phamhoang16/mention-mate:latest")

    orchestrator.stop_user_container("hoangp47")

    client.containers.get.assert_called_once_with("mention-mate-hoangp47")
    existing.remove.assert_called_once_with(force=True)


def test_stop_user_container_is_a_noop_when_absent():
    client = MagicMock()
    client.containers.get.side_effect = docker.errors.NotFound("no such container")
    orchestrator = Orchestrator(client=client, image="ghcr.io/phamhoang16/mention-mate:latest")

    orchestrator.stop_user_container("hoangp47")  # must not raise
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd registrar && python -m pytest tests/test_orchestrator.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'registrar.orchestrator'`

- [ ] **Step 3: Write the implementation**

Create `registrar/src/registrar/orchestrator.py`:

```python
"""Spins up / tears down per-user MentionMate containers via the Docker SDK.

Requires the registrar container to have /var/run/docker.sock mounted
(Docker-outside-of-Docker) — see registrar/README.md for the security note
on why this must stay internal-only.
"""
import docker.errors
import docker.types


class Orchestrator:
    def __init__(self, client, image: str):
        self._client = client
        self._image = image

    def container_name(self, username: str) -> str:
        return f"mention-mate-{username}"

    def start_user_container(self, username: str, env: dict[str, str], data_dir: str) -> str:
        name = self.container_name(username)
        self._remove_if_exists(name)
        container = self._client.containers.run(
            self._image,
            name=name,
            detach=True,
            restart_policy={"Name": "unless-stopped"},
            environment=env,
            volumes={data_dir: {"bind": "/app/data", "mode": "rw"}},
            log_config=docker.types.LogConfig(type="json-file", config={"max-size": "10m", "max-file": "3"}),
        )
        return container.id

    def stop_user_container(self, username: str) -> None:
        self._remove_if_exists(self.container_name(username))

    def _remove_if_exists(self, name: str) -> None:
        try:
            existing = self._client.containers.get(name)
        except docker.errors.NotFound:
            return
        existing.remove(force=True)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd registrar && python -m pytest tests/test_orchestrator.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add registrar/src/registrar/orchestrator.py registrar/tests/test_orchestrator.py
git commit -m "feat(registrar): add Docker orchestrator for per-user containers"
```

---

## Task 6: telegram_login (Telethon OTP wrapper)

**Files:**
- Create: `registrar/src/registrar/telegram_login.py`
- Test: `registrar/tests/test_telegram_login.py`

**Interfaces:**
- Consumes: nothing from prior tasks.
- Produces:
  - `class TwoFactorRequired(Exception)`
  - `async def start_login(api_id: int, api_hash: str, session_path: str, phone: str) -> str` — connects, calls `send_code_request`, disconnects, returns `phone_code_hash`.
  - `async def complete_login(api_id: int, api_hash: str, session_path: str, phone: str, code: str, phone_code_hash: str, password: str | None = None) -> None` — connects, signs in with the code; on `SessionPasswordNeededError` either signs in with `password` if provided or raises `TwoFactorRequired`; always disconnects.

- [ ] **Step 1: Write the failing test**

Create `registrar/tests/test_telegram_login.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd registrar && python -m pytest tests/test_telegram_login.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'registrar.telegram_login'`

- [ ] **Step 3: Write the implementation**

Create `registrar/src/registrar/telegram_login.py`:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd registrar && python -m pytest tests/test_telegram_login.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add registrar/src/registrar/telegram_login.py registrar/tests/test_telegram_login.py
git commit -m "feat(registrar): add Telethon OTP login wrapper"
```

---

## Task 7: FastAPI app — /register/start and /register/verify

**Files:**
- Create: `registrar/src/registrar/config.py`
- Create: `registrar/src/registrar/app.py`
- Test: `registrar/tests/test_app_register_flow.py`

**Interfaces:**
- Consumes: `start_login`, `complete_login`, `TwoFactorRequired` (Task 6); `RegistrationStore` (Task 3).
- Produces: `load_settings() -> Settings` (dataclass with `bot_token`, `data_root`, `stagger_seconds`, `image`); FastAPI `app` object; in-process `PENDING: dict[str, dict]` for state between `/register/start` and `/register/verify`; routes `POST /register/start`, `POST /register/verify`.

- [ ] **Step 1: Write the failing test**

Create `registrar/tests/test_app_register_flow.py`:

```python
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from registrar.app import create_app
from registrar.telegram_login import TwoFactorRequired


def _client(tmp_path):
    app = create_app(
        bot_token="123:abc",
        data_root=str(tmp_path / "data"),
        registrations_path=str(tmp_path / "registrations.json"),
        docker_client=None,  # not exercised in this task's tests
        image="ghcr.io/phamhoang16/mention-mate:latest",
        stagger_seconds=0,
    )
    return TestClient(app)


@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_start_sends_code_and_returns_ok(mock_start_login, tmp_path):
    mock_start_login.return_value = "hash123"
    client = _client(tmp_path)

    response = client.post("/register/start", json={
        "phone": "+84900000000",
        "api_id": 1,
        "api_hash": "h",
        "username": "hoangp47",
    })

    assert response.status_code == 200
    assert response.json() == {"status": "code_sent"}
    mock_start_login.assert_called_once_with(
        api_id=1, api_hash="h", session_path=str(tmp_path / "data" / "hoangp47" / "mentions_session"),
        phone="+84900000000",
    )


@patch("registrar.app.complete_login", new_callable=AsyncMock)
@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_verify_completes_login(mock_start_login, mock_complete_login, tmp_path):
    mock_start_login.return_value = "hash123"
    client = _client(tmp_path)
    client.post("/register/start", json={
        "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
    })

    response = client.post("/register/verify", json={"username": "hoangp47", "code": "12345"})

    assert response.status_code == 200
    assert response.json() == {"status": "logged_in"}
    mock_complete_login.assert_called_once_with(
        api_id=1, api_hash="h", session_path=str(tmp_path / "data" / "hoangp47" / "mentions_session"),
        phone="+84900000000", code="12345", phone_code_hash="hash123", password=None,
    )


@patch("registrar.app.complete_login", new_callable=AsyncMock)
@patch("registrar.app.start_login", new_callable=AsyncMock)
def test_register_verify_reports_two_factor_required(mock_start_login, mock_complete_login, tmp_path):
    mock_start_login.return_value = "hash123"
    mock_complete_login.side_effect = TwoFactorRequired("2FA required")
    client = _client(tmp_path)
    client.post("/register/start", json={
        "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
    })

    response = client.post("/register/verify", json={"username": "hoangp47", "code": "12345"})

    assert response.status_code == 400
    assert response.json()["detail"] == "two_factor_required"


def test_register_verify_without_prior_start_returns_404(tmp_path):
    client = _client(tmp_path)

    response = client.post("/register/verify", json={"username": "nobody", "code": "12345"})

    assert response.status_code == 404
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd registrar && python -m pytest tests/test_app_register_flow.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'registrar.app'`

- [ ] **Step 3: Write the implementation**

Create `registrar/src/registrar/config.py`:

```python
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    bot_token: str
    data_root: str
    registrations_path: str
    stagger_seconds: int
    image: str


def load_settings() -> Settings:
    try:
        bot_token = os.environ["TG_BOT_TOKEN"]
    except KeyError as e:
        raise RuntimeError(f"Missing required environment variable: {e}") from e
    data_root = os.environ.get("REGISTRAR_DATA_ROOT", "/app/registrar-data")
    return Settings(
        bot_token=bot_token,
        data_root=data_root,
        registrations_path=os.environ.get(
            "REGISTRAR_STATE_PATH", os.path.join(data_root, "registrations.json")
        ),
        stagger_seconds=int(os.environ.get("REGISTRAR_STAGGER_SECONDS", "600")),
        image=os.environ.get("REGISTRAR_IMAGE", "ghcr.io/phamhoang16/mention-mate:latest"),
    )
```

Create `registrar/src/registrar/app.py`:

```python
"""FastAPI app tying together the registration flow.

Route summary (finalized in Task 8):
- POST /register/start    — collect phone/api_id/api_hash/username, send OTP
- POST /register/verify   — complete login with the OTP code (+2FA password)
- POST /register/finalize — resolve chat_id, write .env, launch the container
"""
import os

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from registrar.store import RegistrationStore
from registrar.telegram_login import TwoFactorRequired, complete_login, start_login

# In-memory, short-lived state between /register/start and /register/verify —
# deliberately not persisted: if the registrar restarts mid-registration, the
# user just starts over from /register/start.
PENDING: dict[str, dict] = {}


class RegisterStartRequest(BaseModel):
    phone: str
    api_id: int
    api_hash: str
    username: str


class RegisterVerifyRequest(BaseModel):
    username: str
    code: str
    password: str | None = None


def _session_path(data_root: str, username: str) -> str:
    return os.path.join(data_root, username, "mentions_session")


def create_app(
    bot_token: str,
    data_root: str,
    registrations_path: str,
    docker_client,
    image: str,
    stagger_seconds: int,
) -> FastAPI:
    app = FastAPI(title="MentionMate Registrar")
    app.state.bot_token = bot_token
    app.state.data_root = data_root
    app.state.store = RegistrationStore(registrations_path)
    app.state.docker_client = docker_client
    app.state.image = image
    app.state.stagger_seconds = stagger_seconds

    @app.post("/register/start")
    async def register_start(req: RegisterStartRequest):
        phone_code_hash = await start_login(
            api_id=req.api_id,
            api_hash=req.api_hash,
            session_path=_session_path(data_root, req.username),
            phone=req.phone,
        )
        PENDING[req.username] = {
            "phone": req.phone,
            "api_id": req.api_id,
            "api_hash": req.api_hash,
            "phone_code_hash": phone_code_hash,
        }
        return {"status": "code_sent"}

    @app.post("/register/verify")
    async def register_verify(req: RegisterVerifyRequest):
        pending = PENDING.get(req.username)
        if pending is None:
            raise HTTPException(status_code=404, detail="no_pending_registration")

        try:
            await complete_login(
                api_id=pending["api_id"],
                api_hash=pending["api_hash"],
                session_path=_session_path(data_root, req.username),
                phone=pending["phone"],
                code=req.code,
                phone_code_hash=pending["phone_code_hash"],
                password=req.password,
            )
        except TwoFactorRequired:
            raise HTTPException(status_code=400, detail="two_factor_required")

        pending["logged_in"] = True
        return {"status": "logged_in"}

    return app
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd registrar && python -m pytest tests/test_app_register_flow.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add registrar/src/registrar/config.py registrar/src/registrar/app.py \
        registrar/tests/test_app_register_flow.py
git commit -m "feat(registrar): add /register/start and /register/verify endpoints"
```

---

## Task 8: FastAPI app — /register/finalize (wires chat_id, env, queue, orchestrator)

**Files:**
- Modify: `registrar/src/registrar/app.py`
- Test: `registrar/tests/test_app_register_flow.py` (extend)

**Interfaces:**
- Consumes: `resolve_chat_id`, `ChatIdNotFoundError` (Task 2); `build_env`, `write_user_env_file` (Task 1); `StaggerQueue` (Task 4); `Orchestrator` (Task 5); `RegistrationStore.set` (Task 3).
- Produces: route `POST /register/finalize`; `async def send_confirmation(session, bot_token: str, chat_id: int) -> None` (posts the "you're all set" DM via the Bot API — this is the spec's step 7 confirmation message).

- [ ] **Step 1: Write the failing test**

Append to `registrar/tests/test_app_register_flow.py`:

```python
import aiohttp
from unittest.mock import MagicMock, patch

from registrar.chat_id_resolver import ChatIdNotFoundError


def _logged_in_client(tmp_path):
    with patch("registrar.app.start_login", new_callable=AsyncMock) as mock_start:
        mock_start.return_value = "hash123"
        client = _client(tmp_path)
        client.post("/register/start", json={
            "phone": "+84900000000", "api_id": 1, "api_hash": "h", "username": "hoangp47",
        })
    with patch("registrar.app.complete_login", new_callable=AsyncMock):
        client.post("/register/verify", json={"username": "hoangp47", "code": "12345"})
    return client


@patch("registrar.app.send_confirmation", new_callable=AsyncMock)
@patch("registrar.app.Orchestrator")
@patch("registrar.app.resolve_chat_id", new_callable=AsyncMock)
def test_register_finalize_starts_container(mock_resolve_chat_id, mock_orchestrator_cls, mock_send_confirmation, tmp_path):
    mock_resolve_chat_id.return_value = 987654321
    mock_orchestrator = mock_orchestrator_cls.return_value
    mock_orchestrator.start_user_container.return_value = "container-id"
    client = _logged_in_client(tmp_path)

    response = client.post("/register/finalize", json={"username": "hoangp47"})

    assert response.status_code == 200
    assert response.json() == {"status": "active", "container_id": "container-id"}
    mock_orchestrator.start_user_container.assert_called_once()
    call = mock_orchestrator.start_user_container.call_args
    assert call.args[0] == "hoangp47"
    assert call.args[1]["TG_ALERT_CHAT_ID"] == "987654321"
    assert call.args[1]["TG_BOT_TOKEN"] == "123:abc"
    mock_send_confirmation.assert_called_once()
    confirm_call = mock_send_confirmation.call_args
    assert confirm_call.kwargs["bot_token"] == "123:abc"
    assert confirm_call.kwargs["chat_id"] == 987654321


@patch("registrar.app.resolve_chat_id", new_callable=AsyncMock)
def test_register_finalize_returns_409_when_chat_id_not_found(mock_resolve_chat_id, tmp_path):
    mock_resolve_chat_id.side_effect = ChatIdNotFoundError("not found")
    client = _logged_in_client(tmp_path)

    response = client.post("/register/finalize", json={"username": "hoangp47"})

    assert response.status_code == 409
    assert response.json()["detail"] == "chat_id_not_found"


def test_register_finalize_without_completed_login_returns_404(tmp_path):
    client = _client(tmp_path)

    response = client.post("/register/finalize", json={"username": "hoangp47"})

    assert response.status_code == 404
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd registrar && python -m pytest tests/test_app_register_flow.py -v`
Expected: FAIL — `/register/finalize` returns 404 "Not Found" from FastAPI's router (route doesn't exist yet), assertion mismatch on status code / body.

- [ ] **Step 3: Write the implementation**

Modify `registrar/src/registrar/app.py` — add imports and the new route (insert after the existing imports and before `PENDING`, then add the route inside `create_app` after `register_verify`):

```python
import aiohttp

from registrar.chat_id_resolver import ChatIdNotFoundError, resolve_chat_id
from registrar.env_writer import build_env, write_user_env_file
from registrar.orchestrator import Orchestrator
from registrar.queue import StaggerQueue
```

Add inside `create_app`, after `app.state.stagger_seconds = stagger_seconds`:

```python
    app.state.orchestrator = Orchestrator(client=docker_client, image=image)
    app.state.queue = StaggerQueue(min_interval_seconds=stagger_seconds)
```

Add a new request model near the other models:

```python
class RegisterFinalizeRequest(BaseModel):
    username: str
```

Add this function near the top of the module (module-level, alongside `_session_path`) — the spec's step 7 confirmation DM:

```python
async def send_confirmation(session, bot_token: str, chat_id: int) -> None:
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload = {"chat_id": chat_id, "text": "✅ Your MentionMate is now running. You're all set!"}
    async with session.post(url, json=payload) as resp:
        data = await resp.json()
        if not data.get("ok"):
            raise RuntimeError(f"Bot API error sending confirmation: {data}")
```

Add the route inside `create_app`, after `register_verify`:

```python
    @app.post("/register/finalize")
    async def register_finalize(req: RegisterFinalizeRequest):
        pending = PENDING.get(req.username)
        if pending is None or not pending.get("logged_in"):
            raise HTTPException(status_code=404, detail="login_not_completed")

        async with aiohttp.ClientSession() as session:
            try:
                chat_id = await resolve_chat_id(session, bot_token=bot_token)
            except ChatIdNotFoundError:
                raise HTTPException(status_code=409, detail="chat_id_not_found")

        env = build_env(
            bot_token=bot_token,
            api_id=pending["api_id"],
            api_hash=pending["api_hash"],
            username=req.username,
            alert_chat_id=chat_id,
        )
        write_user_env_file(data_root, req.username, env)
        user_data_dir = os.path.join(data_root, req.username)

        async def launch():
            return app.state.orchestrator.start_user_container(req.username, env, user_data_dir)

        container_id = await app.state.queue.run(launch)

        async with aiohttp.ClientSession() as confirm_session:
            await send_confirmation(confirm_session, bot_token=bot_token, chat_id=chat_id)

        await app.state.store.set(req.username, {"status": "active", "chat_id": chat_id})
        del PENDING[req.username]
        return {"status": "active", "container_id": container_id}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd registrar && python -m pytest tests/test_app_register_flow.py -v`
Expected: 7 passed

- [ ] **Step 5: Commit**

```bash
git add registrar/src/registrar/app.py registrar/tests/test_app_register_flow.py
git commit -m "feat(registrar): add /register/finalize wiring chat_id, env, queue, orchestrator"
```

---

## Task 9: Minimal web UI (3 plain HTML pages, no JS framework)

**Files:**
- Create: `registrar/src/registrar/templates/register_start.html`
- Create: `registrar/src/registrar/templates/register_verify.html`
- Create: `registrar/src/registrar/templates/register_finalize.html`
- Modify: `registrar/src/registrar/app.py`
- Test: `registrar/tests/test_app_pages.py`

**Interfaces:**
- Consumes: `create_app` from Task 7/8 (adds GET routes to the same `app`).
- Produces: `GET /register`, `GET /register/verify-page?username=...`, `GET /register/finalize-page?username=...` — server-rendered HTML pages, each with a small inline `<script>` that posts JSON to the matching Task 7/8 endpoint via `fetch`.

- [ ] **Step 1: Write the failing test**

Create `registrar/tests/test_app_pages.py`:

```python
from registrar.app import create_app


def _client(tmp_path):
    from fastapi.testclient import TestClient
    app = create_app(
        bot_token="123:abc",
        data_root=str(tmp_path / "data"),
        registrations_path=str(tmp_path / "registrations.json"),
        docker_client=None,
        image="ghcr.io/phamhoang16/mention-mate:latest",
        stagger_seconds=0,
    )
    return TestClient(app)


def test_register_page_has_the_expected_form_fields(tmp_path):
    response = _client(tmp_path).get("/register")

    assert response.status_code == 200
    body = response.text
    for field in ["phone", "api_id", "api_hash", "username"]:
        assert f'name="{field}"' in body


def test_verify_page_has_code_field(tmp_path):
    response = _client(tmp_path).get("/register/verify-page", params={"username": "hoangp47"})

    assert response.status_code == 200
    assert 'name="code"' in response.text
    assert "hoangp47" in response.text


def test_finalize_page_has_confirm_button(tmp_path):
    response = _client(tmp_path).get("/register/finalize-page", params={"username": "hoangp47"})

    assert response.status_code == 200
    assert "hoangp47" in response.text
    assert "<button" in response.text
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd registrar && python -m pytest tests/test_app_pages.py -v`
Expected: FAIL — `GET /register` returns 404 (route doesn't exist yet).

- [ ] **Step 3: Write the templates and wire them up**

Create `registrar/src/registrar/templates/register_start.html`:

```html
<!doctype html>
<html>
<head><meta charset="utf-8"><title>MentionMate — Register</title></head>
<body>
  <h1>Register for MentionMate</h1>
  <p>Create your own API_ID/API_HASH first at
     <a href="https://my.telegram.org/apps">my.telegram.org/apps</a>, then fill this in.</p>
  <form id="start-form">
    <label>Phone number (with country code): <input name="phone" required></label><br>
    <label>API_ID: <input name="api_id" type="number" required></label><br>
    <label>API_HASH: <input name="api_hash" required></label><br>
    <label>Telegram username (no @): <input name="username" required></label><br>
    <button type="submit">Send code</button>
  </form>
  <script>
    document.getElementById("start-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      const form = new FormData(e.target);
      const body = {
        phone: form.get("phone"),
        api_id: parseInt(form.get("api_id"), 10),
        api_hash: form.get("api_hash"),
        username: form.get("username"),
      };
      const resp = await fetch("/register/start", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify(body),
      });
      if (resp.ok) {
        window.location = `/register/verify-page?username=${encodeURIComponent(body.username)}`;
      } else {
        alert("Could not send code: " + (await resp.text()));
      }
    });
  </script>
</body>
</html>
```

Create `registrar/src/registrar/templates/register_verify.html`:

```html
<!doctype html>
<html>
<head><meta charset="utf-8"><title>MentionMate — Verify</title></head>
<body>
  <h1>Enter the code Telegram sent you</h1>
  <form id="verify-form">
    <input type="hidden" name="username" value="{{ username }}">
    <label>Code: <input name="code" required></label><br>
    <label>2FA password (only if your account has cloud password enabled):
      <input name="password" type="password"></label><br>
    <button type="submit">Confirm</button>
  </form>
  <script>
    document.getElementById("verify-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      const form = new FormData(e.target);
      const body = {
        username: form.get("username"),
        code: form.get("code"),
        password: form.get("password") || null,
      };
      const resp = await fetch("/register/verify", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify(body),
      });
      if (resp.ok) {
        window.location = `/register/finalize-page?username=${encodeURIComponent(body.username)}`;
      } else {
        alert("Could not verify: " + (await resp.text()));
      }
    });
  </script>
</body>
</html>
```

Create `registrar/src/registrar/templates/register_finalize.html`:

```html
<!doctype html>
<html>
<head><meta charset="utf-8"><title>MentionMate — Finalize</title></head>
<body>
  <h1>Almost done</h1>
  <p>Open Telegram, find the shared alert bot, and send it <code>/start</code> — then click Confirm.</p>
  <button id="confirm-btn">Confirm</button>
  <p id="status"></p>
  <script>
    document.getElementById("confirm-btn").addEventListener("click", async () => {
      const resp = await fetch("/register/finalize", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({username: "{{ username }}"}),
      });
      const text = await resp.text();
      document.getElementById("status").textContent = resp.ok
        ? "Your MentionMate is now running!"
        : "Not ready yet: " + text;
    });
  </script>
</body>
</html>
```

Modify `registrar/src/registrar/app.py` — add imports at the top:

```python
from pathlib import Path

from fastapi import Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
```

Add, right after `app = FastAPI(title="MentionMate Registrar")` inside `create_app`:

```python
    templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))
```

Add the three GET routes inside `create_app`, after the `register_finalize` route:

```python
    @app.get("/register", response_class=HTMLResponse)
    async def register_page(request: Request):
        return templates.TemplateResponse(request, "register_start.html", {})

    @app.get("/register/verify-page", response_class=HTMLResponse)
    async def register_verify_page(request: Request, username: str):
        return templates.TemplateResponse(request, "register_verify.html", {"username": username})

    @app.get("/register/finalize-page", response_class=HTMLResponse)
    async def register_finalize_page(request: Request, username: str):
        return templates.TemplateResponse(request, "register_finalize.html", {"username": username})
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd registrar && python -m pytest tests/test_app_pages.py -v`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add registrar/src/registrar/templates registrar/src/registrar/app.py \
        registrar/tests/test_app_pages.py
git commit -m "feat(registrar): add minimal 3-page registration web UI"
```

---

## Task 10: Registrar Dockerfile, compose file, and admin README

**Files:**
- Create: `registrar/Dockerfile`
- Create: `registrar/docker-compose.yml`
- Create: `registrar/README.md`

No automated test — this task packages what Tasks 1-9 already built and tested. Verification is manual (documented in the steps below).

- [ ] **Step 1: Write the Dockerfile**

Create `registrar/Dockerfile`:

```dockerfile
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY pyproject.toml ./
COPY src/ ./src/
RUN pip install --no-cache-dir .

# Also needs the docker CLI's client library only (docker SDK, already a
# dependency) — no docker-in-docker binary required, only socket access.
EXPOSE 8000
CMD ["uvicorn", "registrar.app:app", "--host", "0.0.0.0", "--port", "8000"]
```

Note: `registrar/src/registrar/app.py` exposes `create_app(...)`, not a
module-level `app`. Add a small entrypoint module so `uvicorn
registrar.app:app` in the CMD above resolves — create
`registrar/src/registrar/__main__wiring__.py` is unnecessary; instead add
this to the bottom of `registrar/src/registrar/app.py`:

```python
# Module-level app for `uvicorn registrar.app:app`, wired from env vars.
def _build_app_from_env():
    from docker import DockerClient
    from registrar.config import load_settings

    settings = load_settings()
    return create_app(
        bot_token=settings.bot_token,
        data_root=settings.data_root,
        registrations_path=settings.registrations_path,
        docker_client=DockerClient(base_url="unix://var/run/docker.sock"),
        image=settings.image,
        stagger_seconds=settings.stagger_seconds,
    )


app = _build_app_from_env()
```

- [ ] **Step 2: Write the compose file**

Create `registrar/docker-compose.yml`:

```yaml
# MentionMate Registrar — admin-only, internal network access only.
# See README.md for the security requirements before deploying this.
services:
  registrar:
    build: .
    container_name: mention-mate-registrar
    restart: unless-stopped
    env_file: .env
    ports:
      - "127.0.0.1:8000:8000"  # bind to loopback only; front with your VPN-only reverse proxy
    volumes:
      - ./registrar-data:/app/registrar-data
      - /var/run/docker.sock:/var/run/docker.sock  # Docker-outside-of-Docker: lets the registrar spawn sibling containers
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

- [ ] **Step 3: Write the admin README**

Create `registrar/README.md`:

```markdown
# MentionMate Registrar

Admin-facing service that lets team members self-register for MentionMate:
it runs their Telegram OTP login and launches their own MentionMate
container. See `docs/superpowers/specs/2026-07-09-team-rollout-design.md`
in the repo root for the full design rationale.

## Deploy

1. Create the shared alert bot once via @BotFather, note its token.
2. Copy `.env.example` to `.env` here and fill in `TG_BOT_TOKEN` (and
   optionally `REGISTRAR_STAGGER_SECONDS`, default 600 = 10 minutes).
3. `docker compose up -d --build`.
4. Point your internal-only reverse proxy / VPN at `127.0.0.1:8000` on
   this VPS. **Do not expose this port publicly** — it drives Telegram
   OTP/2FA login for personal accounts.

## Security requirements (do not skip)

- Internal/VPN-only access. The compose file binds to `127.0.0.1` only —
  keep it that way.
- TLS terminated at your internal reverse proxy, even for internal traffic.
- `/var/run/docker.sock` is mounted into this container, which is
  effectively root-equivalent access to the host. Only the admin should
  have shell access to this VPS.
- `registrar-data/<username>/` holds each user's Telethon session — treat
  it as at least as sensitive as an SSH private key.

## Rollout for team members

Send them: `https://<your-internal-host>/register` and the two prerequisite
steps (create their own app at my.telegram.org, then follow the 3-page
wizard). Registrations are automatically spaced out
(`REGISTRAR_STAGGER_SECONDS`) so simultaneous sign-ups don't create a burst
of new sessions from this VPS's IP.
```

- [ ] **Step 4: Manually verify the container builds and boots**

Run:
```bash
cd registrar
cp .env.example .env  # after creating this file per README step 2, with a real TG_BOT_TOKEN
docker compose build
docker compose up -d
curl -s http://127.0.0.1:8000/register | grep -o '<h1>[^<]*</h1>'
```
Expected: prints `<h1>Register for MentionMate</h1>`, confirming the app boots and serves the first registration page end-to-end inside the container.

- [ ] **Step 5: Commit**

```bash
git add registrar/Dockerfile registrar/docker-compose.yml registrar/README.md \
        registrar/src/registrar/app.py
git commit -m "feat(registrar): add Dockerfile, compose file, and admin README"
```

---

## Post-plan follow-up (not part of this plan)

- `registrar/.env.example` (referenced in Task 10's README) should be added
  alongside the first real deployment, listing `TG_BOT_TOKEN`,
  `REGISTRAR_DATA_ROOT`, `REGISTRAR_STAGGER_SECONDS`, `REGISTRAR_IMAGE` —
  intentionally left out of this plan since it's pure documentation, not
  behavior, and is easiest to write once the admin has real values to
  reference.
- Team-facing onboarding instructions (which internal URL to visit, which
  bot to `/start`) go in the internal KB, **not** in this repo — per the
  spec's decision to keep company-specific rollout details out of the
  public `mention-mate` project.
