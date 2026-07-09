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
