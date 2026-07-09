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
