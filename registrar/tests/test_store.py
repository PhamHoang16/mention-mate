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
