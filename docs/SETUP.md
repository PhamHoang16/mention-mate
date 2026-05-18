# Setup Guide — MentionMate

Hướng dẫn cài đặt step-by-step với placeholder cho screenshot (sẽ bổ sung sau pilot).

> ⏱️ **Thời gian dự kiến:** 10-15 phút (tech) / 20-30 phút (lần đầu).

---

## Yêu cầu

| Mục | Yêu cầu |
|---|---|
| **OS** | Linux (Ubuntu 22.04+, Debian 12+, Fedora 38+), macOS 13+, Windows 10/11 |
| **Docker runtime** | Docker Engine 20.10+ / Docker Desktop 4.x / Colima 0.5+ / Podman 4+ |
| **Disk** | ~500MB free (image + session + log) |
| **Network** | Truy cập được `api.telegram.org` và `ghcr.io` (mạng cá nhân, 4G, hoặc internet công ty cho phép) |
| **Tài khoản** | 1 account Telegram cá nhân (đã xác minh SĐT) |

> ⚠️ **Mạng công ty Viettel:** Nếu intranet chặn `api.telegram.org` → tool không chạy được. Phải dùng wifi cá nhân, 4G hotspot, hoặc máy ở nhà.

---

## Bước 1: Cài Docker runtime (nếu chưa có)

### Linux

Khuyên dùng **Docker Engine** (free, không cần Docker Desktop license):

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Logout/login để effect group
```

Verify: `docker info` không báo lỗi.

### macOS

Khuyên dùng **Colima** (free, lightweight, free for commercial use):

```bash
brew install colima docker
colima start
```

Hoặc **Rancher Desktop** / **Podman Desktop** (free GUI alternatives).

> ⚠️ **Tránh Docker Desktop** nếu công ty bạn có >250 nhân viên (vướng license).

### Windows

Khuyên dùng **WSL2 + Docker Engine** (free) HOẶC **Podman Desktop** (free GUI):

**Option A: WSL2 + Docker Engine**
1. Cài WSL2: PowerShell admin → `wsl --install`
2. Restart máy
3. Vào Ubuntu trong WSL: `curl -fsSL https://get.docker.com | sudo sh`
4. Wizard chạy trong terminal WSL (KHÔNG phải PowerShell).

**Option B: Podman Desktop**
1. Tải https://podman.io/docs/installation
2. Cài + start machine
3. `setup.ps1` sẽ tự detect.

> _Screenshot 1 placeholder: Docker Desktop / Colima / Podman running indicator._

---

## Bước 2: Lấy Telegram credentials

### 2a. API_ID + API_HASH

1. Mở https://my.telegram.org/apps
2. Đăng nhập bằng SĐT Telegram của bạn — sẽ nhận code qua Telegram
3. Bấm **"API development tools"**
4. Điền form:
   - App title: bất kỳ (vd "MentionMate-personal")
   - Short name: bất kỳ (vd "mention-tool")
   - Platform: Desktop
   - Description: optional
5. Bấm **"Create application"**
6. Copy **API_ID** (số) và **API_HASH** (32 ký tự hex) — giữ kín, không share

> _Screenshot 2 placeholder: my.telegram.org/apps showing API_ID + API_HASH._

### 2b. Bot Token

1. Mở Telegram, search và chat với [@BotFather](https://t.me/BotFather)
2. Gõ `/newbot`
3. BotFather hỏi tên bot — đặt tên hiển thị (vd "Mention Alert của Hoang")
4. BotFather hỏi username — đặt username kết thúc bằng `bot` (vd `hoangp47_mention_bot`)
5. BotFather trả về **token** dạng `1234567890:AAAA-xxxx...` — copy ngay, giữ kín

> _Screenshot 3 placeholder: BotFather conversation showing /newbot flow + token._

### 2c. Username Telegram của bạn

Mở Telegram → Settings → tìm username (không có @). Vd: `hoangp47`. Nếu chưa có thì đặt mới qua Settings → Username.

---

## Bước 3: Tải MentionMate

1. Vào https://github.com/hoangp47/mentionmate/releases
2. Tìm release mới nhất (vd `v0.1.0`)
3. Tải file `mentionmate-v0.1.0.zip` từ phần "Assets"
4. Giải nén vào 1 thư mục bất kỳ (vd `~/MentionMate` trên Linux, `C:\MentionMate` trên Windows)

> _Screenshot 4 placeholder: GitHub Releases page with zip asset highlighted._

---

## Bước 4: Chạy setup wizard

### Linux / macOS

```bash
cd ~/MentionMate
./setup.sh
```

### Windows

Mở PowerShell (admin không bắt buộc):

```powershell
cd C:\MentionMate
.\setup.ps1
```

Nếu PowerShell báo lỗi script bị chặn:

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

Hoặc set policy cho session hiện tại:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

> _Screenshot 5 placeholder: Wizard running in terminal showing first prompt._

---

## Bước 5: Đi qua wizard

Wizard sẽ guide qua các bước. **Đọc kỹ từng prompt** trước khi gõ.

### Step 1-3: Auto checks
Wizard kiểm tra Docker, compose v2, và cấu hình cũ. Nếu có lỗi → xem [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### Step 4-7: Nhập 4 thông tin

- **TG_API_ID**: số nguyên từ bước 2a
- **TG_API_HASH**: 32 ký tự hex từ bước 2a (sẽ không hiển thị khi gõ — paste vào)
- **TG_MY_USERNAME**: username từ bước 2c (KHÔNG có @)
- **TG_BOT_TOKEN**: token từ bước 2b (không hiển thị)

Nếu nhập sai format, wizard sẽ báo lỗi và prompt lại — không advance.

### Step 8: Pull image
Wizard tự pull `ghcr.io/hoangp47/mentionmate:latest` — lần đầu mất 1-2 phút.

### Step 9: Discover chat_id

Wizard yêu cầu bạn **mở Telegram và gửi `/start` cho bot vừa tạo**.

> ⚠️ Phải gửi cho ĐÚNG bot bạn vừa tạo qua BotFather, không phải bot khác. Wizard hiển thị username bot để bạn tìm đúng.

Sau khi bạn gửi, nhấn Enter trong terminal. Wizard sẽ gọi `getUpdates`, tìm chat_id, gửi test message **"🔧 MentionMate setup test"**, và hỏi bạn có nhận được không.

- Nếu nhận được → trả `y` để confirm.
- Nếu không → wizard sẽ thử lại tối đa 3 lần.

> _Screenshot 6 placeholder: Setup test message received on Telegram._

### Step 10: Ghi .env
Wizard ghi `.env` với permission 600 (Linux/macOS) hoặc ACL owner-only (Windows). File này chứa secret — đừng share.

### Step 11: Đăng nhập Telethon userbot

Wizard chạy 1 container interactive. Bạn cần nhập:

1. **SĐT** kèm mã quốc gia, vd `+84912345678`
2. **OTP** — Telegram gửi mã 5 chữ số đến app Telegram trên điện thoại bạn
3. **Password 2FA** (nếu account có bật 2FA)

Nếu nhập sai 3 lần liên tiếp, wizard sẽ exit. Thử lại bằng cách chạy lại `./setup.sh`.

> _Screenshot 7 placeholder: Telethon login prompts in terminal._

### Step 12: Start container
Wizard chạy `docker compose up -d`. Nếu thành công, in summary.

### Step 13: Summary
Wizard in các lệnh hữu ích. Container giờ đang chạy.

> _Screenshot 8 placeholder: Wizard summary showing container running + commands._

---

## Bước 6: Verify hoạt động

Mở 1 group Telegram mà bạn đang là member, nhờ ai đó gửi tin nhắn có `@username_của_bạn` (hoặc tự tag mình từ account khác). Trong vài giây, bot vừa cài sẽ DM bạn tin nhắn alert.

Nếu không nhận được → xem [TROUBLESHOOTING.md](TROUBLESHOOTING.md) §"Không nhận alert".

---

## Bước 7 (optional): Auto-start khi boot máy

### Linux (systemd)
Container có `restart: unless-stopped` nên tự lên lại khi Docker daemon start. Để Docker tự start khi boot:
```bash
sudo systemctl enable docker
```

### macOS (Colima)
```bash
brew services start colima
```

### Windows
Docker Desktop / Podman Desktop có option *"Start at login"* trong settings.

---

## Bước 8 (optional): Backup session file

Session file ở `data/mentions_session.session` tương đương credential. Backup định kỳ tránh mất khi tắt máy đột ngột:

```bash
# Linux/macOS — copy vào ~/Backups/
cp data/mentions_session.session ~/Backups/mentionmate-session-$(date +%Y%m%d).session
```

```powershell
# Windows
Copy-Item data\mentions_session.session "$env:USERPROFILE\Backups\mentionmate-session-$(Get-Date -Format yyyyMMdd).session"
```

Update wizard sẽ tự nhắc backup nếu session > 7 ngày chưa backup.

---

## Bước tiếp theo

- 🐛 Có lỗi? → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- 📝 Muốn upgrade? → `./update.sh` hoặc `.\update.ps1`
- 🗑️ Muốn gỡ? → `docker compose down && rm -rf data .env` (chú ý: xoá session file cũng = mất quyền truy cập, cần Telethon login lại nếu cài lại)

---

*Hướng dẫn này cập nhật theo MentionMate v0.1.0. Screenshot sẽ được bổ sung sau pilot.*
