from registrar.app import PENDING, create_app


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


def test_finalize_page_shows_the_pending_nonce_for_this_username(tmp_path):
    """Fix 1: the finalize page must tell the user the exact nonce to send
    (`/start <nonce>`), threaded from PENDING[username]["nonce"], so
    resolve_chat_id can correlate the right chat_id for this registration
    instead of grabbing whichever update is most recent on the shared bot.
    """
    PENDING["hoangp47"] = {"nonce": "test-nonce-xyz"}
    try:
        response = _client(tmp_path).get("/register/finalize-page", params={"username": "hoangp47"})
    finally:
        PENDING.clear()

    assert response.status_code == 200
    assert "test-nonce-xyz" in response.text


def test_finalize_page_escapes_username_for_json(tmp_path):
    """Verify that usernames with backslashes are properly JSON-escaped in the inline script."""
    # Username with backslash that would break JS string literal if not properly escaped
    test_username = 'user\\with\\backslash'
    response = _client(tmp_path).get("/register/finalize-page", params={"username": test_username})

    assert response.status_code == 200
    body = response.text

    # The username should be present in the response (in JSON-escaped form)
    assert "user" in body

    # Verify the script block contains the properly escaped username
    # When {{ username | tojson }} is used, it produces a JSON string literal with proper escaping
    # For 'user\\with\\backslash', tojson produces "user\\with\\backslash" (double-escaped in HTML)
    # The key check: the script should contain JSON.stringify({username: "user\\\\with\\\\backslash"})
    # and should NOT be corrupted (i.e., script should parse correctly)

    # Extract and verify the JSON.stringify part contains valid escaping
    import json
    import re

    # Find the JSON.stringify call in the script
    match = re.search(r'JSON\.stringify\(\{username:\s*([^}]+)\}\)', body)
    assert match is not None, "Could not find JSON.stringify call in response"

    # The matched group should be a valid JSON string representing the username
    json_value = match.group(1).strip()

    # Parse the JSON value to verify it's valid JSON
    decoded = json.loads(json_value)
    assert decoded == test_username, f"Expected {test_username}, got {decoded}"
