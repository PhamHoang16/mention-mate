"""Telethon interactive login — run once during setup.

The wizard invokes this as:
    docker run --rm -it -v ./data:/app/data --env-file .env \\
        ghcr.io/phamhoang16/mention-mate:latest python -m mention_mate.auth

Telethon prompts for phone number, OTP, and 2FA password (if enabled),
then saves the session to /app/data/mentions_session.session (mounted on host).

Running this again when the session already exists will NOT prompt —
Telethon reuses the existing session. The wizard detects this at a
higher layer and prompts for overwrite.
"""
import os
import sys

from telethon import TelegramClient


def main() -> int:
    try:
        api_id = int(os.environ["TG_API_ID"])
        api_hash = os.environ["TG_API_HASH"]
    except KeyError as e:
        print(f"❌ Missing environment variable: {e}", file=sys.stderr)
        return 1
    except ValueError:
        print("❌ TG_API_ID must be an integer.", file=sys.stderr)
        return 1

    session_path = "/app/data/mentions_session"
    client = TelegramClient(session_path, api_id, api_hash)

    print("🔐 Starting Telethon login. Enter your phone number with country code (e.g. +84912345678):")
    client.start()
    print(f"✅ Session saved: {session_path}.session")
    client.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(main())
