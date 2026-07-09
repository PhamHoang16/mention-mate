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
