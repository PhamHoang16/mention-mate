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
