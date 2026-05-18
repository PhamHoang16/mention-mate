import os
import html
import asyncio
import aiohttp
from dotenv import load_dotenv
from telethon import TelegramClient, events

load_dotenv()

API_ID = int(os.getenv('TG_API_ID'))
API_HASH = os.getenv('TG_API_HASH')
BOT_TOKEN = os.getenv('TG_BOT_TOKEN')
MY_USERNAME = os.getenv('TG_MY_USERNAME')
ALERT_CHAT_ID = int(os.getenv('TG_ALERT_CHAT_ID'))

# bot_id là phần trước dấu ':' trong token — userbot dùng nó để loại tin nhắn
# do chính bot gửi (tránh vòng lặp khi alert được DM lại cho user)
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
    # Thử HTML trước (đã escape user content); nếu Telegram vẫn từ chối parse
    # thì fallback plain text. Mục tiêu: KHÔNG BAO GIỜ để alert bị trượt.
    try:
        await _post_message(session, html_msg, parse_mode="HTML")
        return
    except Exception as e:
        print(f"⚠️  HTML send failed ({e}); fallback plain text")
    try:
        await _post_message(session, plain_msg, parse_mode=None)
        return
    except Exception as e:
        # Cả 2 đều fail — log nguyên văn để user còn recover được thủ công
        print(f"❌ ALERT LOST. Original text: {original_text!r}. Error: {e}")
        raise


async def main():
    user_client = TelegramClient('data/mentions_session', API_ID, API_HASH)
    http_session = aiohttp.ClientSession()

    @user_client.on(events.NewMessage(incoming=True))
    async def handle_new_message(event):
        # Bỏ qua tin nhắn do CHÍNH BOT gửi (alert quote lại @username sẽ tạo vòng lặp).
        # Trong DM với bot, sender_id và chat_id từ phía user-client đều là bot_id —
        # không phải user_id của mình (ALERT_CHAT_ID).
        if event.sender_id == BOT_ID:
            return

        # raw_text rỗng với media-only; dùng message.text để cũng bắt được caption
        text = event.raw_text or getattr(event.message, 'message', '') or ""

        # Case-insensitive: Telegram username vốn không phân biệt hoa thường,
        # nhưng người gõ vẫn có thể viết @Hoangp47 / @HOANGP47
        if MENTION_TOKEN not in text.lower():
            return

        chat = await event.get_chat()
        sender = await event.get_sender()

        sender_name = getattr(sender, 'first_name', None) or 'Unknown'
        chat_title = getattr(chat, 'title', None) or 'Private Chat'

        message_link = f"https://t.me/c/{chat.id}/{event.id}"
        if str(chat.id).startswith('-100'):
            clean_chat_id = str(chat.id)[4:]
            message_link = f"https://t.me/c/{clean_chat_id}/{event.id}"

        # HTML mode: chỉ cần escape <, >, & trong nội dung user-generated.
        # An toàn hơn Markdown rất nhiều — Markdown crash với mọi ký tự đặc biệt
        # chưa khớp cặp (*, _, [, `) và làm trượt alert.
        sender_html = html.escape(sender_name)
        chat_html = html.escape(chat_title)
        text_html = html.escape(text)
        link_html = html.escape(message_link, quote=True)

        html_msg = (
            f"🔔 <b>You were mentioned!</b>\n"
            f"👤 <b>From:</b> {sender_html}\n"
            f"🏢 <b>Group:</b> {chat_html}\n\n"
            f"<blockquote>{text_html}</blockquote>\n\n"
            f'🔗 <a href="{link_html}">Jump to message</a>'
        )
        plain_msg = (
            f"🔔 You were mentioned!\n"
            f"👤 From: {sender_name}\n"
            f"🏢 Group: {chat_title}\n\n"
            f"{text}\n\n"
            f"🔗 {message_link}"
        )

        try:
            await send_alert(http_session, html_msg, plain_msg, text)
            print(f"Đã forward tin nhắn từ {chat_title}")
        except Exception:
            pass  # đã được log đầy đủ trong send_alert

    print("🚀 Đang khởi động Telegram Mention Alert...")
    await user_client.start()
    print("✅ Đang chạy: userbot lắng nghe, bot HTTP API gửi alert...")
    try:
        await user_client.run_until_disconnected()
    finally:
        await http_session.close()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n⛔ Bot stopped.")
