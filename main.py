import os
import asyncio
from dotenv import load_dotenv
from telethon import TelegramClient, events

# Load biến từ file .env (nếu có). Khi chạy trên Docker/K8s, biến env đã được inject sẵn
# nên load_dotenv() sẽ không override — hoàn toàn an toàn cho cả 2 môi trường
load_dotenv()

# Đọc cấu hình từ Environment Variables để bảo mật và dễ quản lý qua CI/CD
API_ID = int(os.getenv('TG_API_ID'))
API_HASH = os.getenv('TG_API_HASH')
MY_USERNAME = os.getenv('TG_MY_USERNAME')   # VD: 'hoangpham_devops' (không có chữ @)
ALERT_CHAT_ID = int(os.getenv('TG_ALERT_CHAT_ID'))  # VD: -100123456789 hoặc user_id


async def main():
    # Khởi tạo client BÊN TRONG async để tránh lỗi event loop trên Python 3.10+
    # File session sẽ được lưu tại thư mục hiện tại
    client = TelegramClient('mentions_session', API_ID, API_HASH)

    @client.on(events.NewMessage(incoming=True))
    async def handle_new_message(event):
        # Lấy nội dung tin nhắn
        text = event.raw_text or ""

        # Kiểm tra xem có ai tag username của mình không
        if f"@{MY_USERNAME}" in text:
            chat = await event.get_chat()
            sender = await event.get_sender()

            # Lấy tên người gửi và tên nhóm
            sender_name = getattr(sender, 'first_name', 'Unknown')
            chat_title = getattr(chat, 'title', 'Private Chat')

            # Tạo link trực tiếp đến tin nhắn (chỉ hoạt động với Supergroup/Channel)
            message_link = f"https://t.me/c/{chat.id}/{event.id}"
            if str(chat.id).startswith('-100'):
                # Telethon format: id của supergroup có prefix -100, khi tạo link t.me thì bỏ -100 đi
                clean_chat_id = str(chat.id)[4:]
                message_link = f"https://t.me/c/{clean_chat_id}/{event.id}"

            # Format alert message — blockquote for message content
            alert_msg = (
                f"🔔 **You were mentioned!**\n"
                f"👤 **From:** {sender_name}\n"
                f"🏢 **Group:** {chat_title}\n\n"
                f"> {text}\n\n"
                f"🔗 [Jump to message]({message_link})"
            )

            # Gửi vào nhóm Alert
            try:
                await client.send_message(ALERT_CHAT_ID, alert_msg)
                print(f"Đã forward tin nhắn từ {chat_title}")
            except Exception as e:
                print(f"Lỗi khi gửi cảnh báo: {e}")

    print("🚀 Đang khởi động Telegram Userbot...")
    # Lần chạy đầu tiên sẽ yêu cầu nhập số điện thoại và mã OTP qua console
    await client.start()
    print("✅ Bot đang chạy và lắng nghe mentions...")
    await client.run_until_disconnected()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n⛔ Bot stopped.")