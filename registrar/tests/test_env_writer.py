import os
import stat
from unittest.mock import patch

from registrar.env_writer import (
    MENTION_MATE_CONTAINER_GID,
    MENTION_MATE_CONTAINER_UID,
    build_env,
    fix_ownership_for_container_user,
    render_env_file,
    write_user_env_file,
)


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


def test_fix_ownership_for_container_user_chowns_dir_and_every_file(tmp_path):
    """Regression: a real per-user container crashed with sqlite3's "unable
    to open database file" because the registrar (root) writes .env and the
    Telethon session, but the MentionMate image runs as a fixed non-root
    user (uid 1001) that then can't open a root-owned file/dir.
    """
    user_dir = tmp_path / "hoangp47"
    user_dir.mkdir()
    env_file = user_dir / ".env"
    env_file.write_text("TG_BOT_TOKEN=123:abc\n")
    session_file = user_dir / "mentions_session.session"
    session_file.write_text("fake-sqlite-bytes")

    with patch("registrar.env_writer.os.chown") as mock_chown:
        fix_ownership_for_container_user(str(tmp_path), "hoangp47")

    chowned_paths = {call.args[0] for call in mock_chown.call_args_list}
    assert chowned_paths == {user_dir, env_file, session_file}
    for call in mock_chown.call_args_list:
        assert call.args[1] == MENTION_MATE_CONTAINER_UID
        assert call.args[2] == MENTION_MATE_CONTAINER_GID
