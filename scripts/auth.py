"""Telethon interactive login — chỉ chạy 1 lần khi setup.

Wizard gọi:
    docker run --rm -it -v ./data:/app/data --env-file .env \\
        ghcr.io/hoangp47/mentionmate:latest python /app/scripts/auth.py

Telethon sẽ prompt SĐT → OTP → 2FA password (nếu có), rồi lưu session
vào /app/data/mentions_session.session (mount ra host).

Chạy lại lần nữa nếu file session đã tồn tại sẽ KHÔNG prompt — Telethon
re-use session cũ. Wizard detect và prompt overwrite ở layer trên.
"""
import os
import sys

from telethon import TelegramClient


def main() -> int:
    try:
        api_id = int(os.environ["TG_API_ID"])
        api_hash = os.environ["TG_API_HASH"]
    except KeyError as e:
        print(f"❌ Thiếu env var: {e}", file=sys.stderr)
        return 1
    except ValueError:
        print("❌ TG_API_ID phải là số nguyên.", file=sys.stderr)
        return 1

    session_path = "/app/data/mentions_session"
    client = TelegramClient(session_path, api_id, api_hash)

    print("🔐 Bắt đầu đăng nhập Telethon. Nhập SĐT (kèm mã quốc gia, vd +84912345678):")
    client.start()
    print(f"✅ Session đã lưu: {session_path}.session")
    client.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(main())
