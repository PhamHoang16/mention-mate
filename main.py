import os
import asyncio
from dotenv import load_dotenv
from telethon import TelegramClient, events

load_dotenv()

API_ID = int(os.getenv('TG_API_ID'))
API_HASH = os.getenv('TG_API_HASH')
BOT_TOKEN = os.getenv('TG_BOT_TOKEN')
MY_USERNAME = os.getenv('TG_MY_USERNAME')
ALERT_CHAT_ID = int(os.getenv('TG_ALERT_CHAT_ID'))


async def main():
    # Userbot client — lắng nghe mention trên account thật
    user_client = TelegramClient('data/mentions_session', API_ID, API_HASH)
    # Bot client — gửi alert (account khác → Telegram sẽ push noti)
    bot_client = TelegramClient('data/bot_session', API_ID, API_HASH)

    @user_client.on(events.NewMessage(incoming=True))
    async def handle_new_message(event):
        text = event.raw_text or ""

        if f"@{MY_USERNAME}" in text:
            chat = await event.get_chat()
            sender = await event.get_sender()

            sender_name = getattr(sender, 'first_name', 'Unknown')
            chat_title = getattr(chat, 'title', 'Private Chat')

            message_link = f"https://t.me/c/{chat.id}/{event.id}"
            if str(chat.id).startswith('-100'):
                clean_chat_id = str(chat.id)[4:]
                message_link = f"https://t.me/c/{clean_chat_id}/{event.id}"

            alert_msg = (
                f"🔔 **You were mentioned!**\n"
                f"👤 **From:** {sender_name}\n"
                f"🏢 **Group:** {chat_title}\n\n"
                f"> {text}\n\n"
                f"🔗 [Jump to message]({message_link})"
            )

            try:
                # Gửi qua bot — không phải user, nên Telegram sẽ push noti
                await bot_client.send_message(ALERT_CHAT_ID, alert_msg)
                print(f"Đã forward tin nhắn từ {chat_title}")
            except Exception as e:
                print(f"Lỗi khi gửi cảnh báo: {e}")

    print("🚀 Đang khởi động Telegram Mention Alert...")
    await user_client.start()
    await bot_client.start(bot_token=BOT_TOKEN)
    print("✅ Đang chạy: userbot lắng nghe, bot gửi alert...")
    await asyncio.gather(
        user_client.run_until_disconnected(),
        bot_client.run_until_disconnected(),
    )


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n⛔ Bot stopped.")
