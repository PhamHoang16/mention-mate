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
