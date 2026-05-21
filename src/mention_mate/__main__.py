import os
import html
import asyncio
import aiohttp
from dotenv import load_dotenv
from telethon import TelegramClient, events
from telethon.tl.types import Channel

load_dotenv()

API_ID = int(os.getenv('TG_API_ID'))
API_HASH = os.getenv('TG_API_HASH')
BOT_TOKEN = os.getenv('TG_BOT_TOKEN')
MY_USERNAME = os.getenv('TG_MY_USERNAME')
ALERT_CHAT_ID = int(os.getenv('TG_ALERT_CHAT_ID'))

# bot_id is the part before ':' in the token — the userbot uses it to
# filter out messages sent by the bot itself (avoids the loop where the
# alert message quoting @username gets DM'd back to the user).
BOT_ID = int(BOT_TOKEN.split(':')[0])
MENTION_TOKEN = f"@{MY_USERNAME}".lower()

BOT_API_URL = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"


async def _post_message(session, text, parse_mode=None):
    payload = {
        "chat_id": ALERT_CHAT_ID,
        "text": text,
        "disable_web_page_preview": True,
    }
    if parse_mode:
        payload["parse_mode"] = parse_mode
    async with session.post(BOT_API_URL, json=payload) as resp:
        data = await resp.json()
        if not data.get("ok"):
            raise RuntimeError(f"Bot API error: {data}")


async def send_alert(session, html_msg, plain_msg, original_text):
    # Try HTML first (user content already escaped); if Telegram still
    # refuses to parse it, fall back to plain text. Goal: NEVER let an
    # alert slip through silently.
    try:
        await _post_message(session, html_msg, parse_mode="HTML")
        return
    except Exception as e:
        print(f"⚠️  HTML send failed ({e}); falling back to plain text")
    try:
        await _post_message(session, plain_msg, parse_mode=None)
        return
    except Exception as e:
        # Both failed — log the raw text so the user can still recover manually.
        print(f"❌ ALERT LOST. Original text: {original_text!r}. Error: {e}")
        raise


async def main():
    user_client = TelegramClient('data/mentions_session', API_ID, API_HASH)
    http_session = aiohttp.ClientSession()

    @user_client.on(events.NewMessage(incoming=True))
    async def handle_new_message(event):
        # Skip messages sent by the bot itself (the alert quotes @username
        # and would trigger an infinite loop).
        # In a DM with the bot, from the user-client's point of view both
        # sender_id and chat_id are the bot_id — not the user's own id (ALERT_CHAT_ID).
        if event.sender_id == BOT_ID:
            return

        # raw_text is empty for media-only messages; fall back to message.text
        # so captions are also matched.
        text = event.raw_text or getattr(event.message, 'message', '') or ""

        # Case-insensitive: Telegram usernames themselves are case-insensitive,
        # but the sender may still type @Hoangp47 / @HOANGP47.
        if MENTION_TOKEN not in text.lower():
            return

        chat = await event.get_chat()
        sender = await event.get_sender()

        sender_name = getattr(sender, 'first_name', None) or 'Unknown'
        chat_title = getattr(chat, 'title', None) or 'Private Chat'

        # t.me/c/<id>/<msg_id> only resolves for Channel (supergroups,
        # megagroups, broadcast channels). Basic groups (Chat) and DMs (User)
        # have no message-permalink format — Telegram silently lands on an
        # unrelated channel and shows "no permission". Emit a fallback hint
        # in those cases instead of a broken link.
        if isinstance(chat, Channel):
            username = getattr(chat, 'username', None)
            if username:
                message_link = f"https://t.me/{username}/{event.id}"
            else:
                message_link = f"https://t.me/c/{chat.id}/{event.id}"
        else:
            message_link = None

        # HTML mode: only <, >, & in user-generated content need to be escaped.
        # Much safer than Markdown — Markdown crashes on any unmatched special
        # character (*, _, [, `) and silently drops the alert.
        sender_html = html.escape(sender_name)
        chat_html = html.escape(chat_title)
        text_html = html.escape(text)

        if message_link:
            link_html = html.escape(message_link, quote=True)
            link_block_html = f'🔗 <a href="{link_html}">Open in Telegram →</a>'
            link_block_plain = f"🔗 {message_link}"
        else:
            link_block_html = (
                f"💡 <i>Basic group — open Telegram and check "
                f"<b>{chat_html}</b> to find this message.</i>"
            )
            link_block_plain = (
                f"💡 Basic group — open Telegram and check "
                f"{chat_title} to find this message."
            )

        html_msg = (
            f"👋 <b>New mention</b>\n"
            f"<b>{sender_html}</b> mentioned you in <i>{chat_html}</i>\n"
            f"━━━━━━━━━━━━━━━\n\n"
            f"<blockquote expandable>{text_html}</blockquote>\n\n"
            f"━━━━━━━━━━━━━━━\n"
            f"{link_block_html}"
        )
        plain_msg = (
            f"👋 New mention\n"
            f"━━━━━━━━━━━━━━━\n"
            f"{sender_name} mentioned you in {chat_title}\n\n"
            f"{text}\n\n"
            f"{link_block_plain}"
        )

        try:
            await send_alert(http_session, html_msg, plain_msg, text)
            suffix = "" if message_link else " (basic group — no permalink)"
            print(f"Forwarded a message from {chat_title}{suffix}")
        except Exception:
            pass  # already fully logged inside send_alert

    print("🚀 Starting MentionMate...")
    await user_client.start()
    print("✅ Running: userbot listening, bot HTTP API sending alerts...")
    try:
        await user_client.run_until_disconnected()
    finally:
        await http_session.close()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n⛔ Bot stopped.")
