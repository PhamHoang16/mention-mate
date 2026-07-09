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
