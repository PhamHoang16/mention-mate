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


# Fixed by the mention-mate image's Dockerfile: `adduser -D -u 1001 tgbot`.
MENTION_MATE_CONTAINER_UID = 1001
MENTION_MATE_CONTAINER_GID = 1001


def fix_ownership_for_container_user(data_root: str, username: str) -> None:
    """The registrar (running as root) writes .env and the Telethon session
    into this directory, but the per-user MentionMate container that later
    mounts the same directory runs as a fixed non-root user (uid 1001).
    Without handing ownership over, that container can't open the session:
    sqlite3.OperationalError: unable to open database file.
    """
    user_dir = Path(data_root) / username
    os.chown(user_dir, MENTION_MATE_CONTAINER_UID, MENTION_MATE_CONTAINER_GID)
    for entry in user_dir.iterdir():
        os.chown(entry, MENTION_MATE_CONTAINER_UID, MENTION_MATE_CONTAINER_GID)
