# Troubleshooting — MentionMate

Tổng hợp lỗi thường gặp và cách fix. Nếu vẫn không giải quyết được, mở [issue trên GitHub](https://github.com/hoangp47/mentionmate/issues) kèm full log + version.

---

## Mục lục

1. [Wizard / Setup](#wizard--setup)
2. [Network](#network)
3. [Auth (Telethon login)](#auth-telethon-login)
4. [chat_id](#chat_id)
5. [Container](#container)
6. [Update](#update)
7. [Không nhận alert](#không-nhận-alert)
8. [Windows](#windows)
9. [macOS](#macos)
10. [Debugging tổng quát](#debugging-tổng-quát)

---

## Wizard / Setup

### ❌ `ERR-DIST-001: Docker daemon chưa chạy.`

**Lý do:** wizard chạy `docker info` nhưng exit non-zero — Docker chưa được start.

**Fix:**
- **Linux:** `sudo systemctl start docker` (nếu dùng systemd). Verify: `docker info`.
- **macOS Colima:** `colima start`. Verify: `colima status`.
- **macOS Docker Desktop:** Mở app từ Applications. Đợi icon ở menu bar chuyển sang xanh.
- **Windows Docker Desktop:** Mở app từ Start Menu. Đợi 30-60s init.
- **Windows WSL2:** Vào terminal WSL, chạy `sudo service docker start`.
- **Podman:** `podman machine start`.

### ❌ `ERR-DIST-001: Không tìm thấy 'docker'.`

Docker CLI chưa cài hoặc không trong PATH.

**Fix:** Xem [SETUP.md §Bước 1](SETUP.md#bước-1-cài-docker-runtime-nếu-chưa-có).

### ⚠️ `Chỉ có docker-compose v1 (legacy)`

Bạn đang dùng `docker-compose` v1 (gạch nối, Python-based). Wizard sẽ fallback nhưng v1 đã deprecated từ 2023.

**Fix khuyên dùng:** Upgrade Docker Engine/Desktop lên version có compose v2 bundled (Docker 20.10+).

### Wizard hỏi `Ghi đè cấu hình cũ? (y/N)` — chọn gì?

- Chọn **N** nếu bạn đã setup trước và muốn giữ nguyên.
- Chọn **Y** nếu bạn muốn nhập lại từ đầu (vd token cũ đã revoke). **Lưu ý:** session file vẫn được giữ — chỉ `.env` bị ghi đè. Nếu muốn xoá hết thì xoá thủ công `data/mentions_session.session` trước khi chạy wizard.

---

## Network

### ❌ `ERR-DIST-002: Pull image fail.`

Wizard không pull được từ `ghcr.io/hoangp47/mentionmate`.

**Chẩn đoán:**
```bash
# Test connectivity
curl -I https://ghcr.io
curl -I https://api.telegram.org
```

**Nguyên nhân thường gặp:**

1. **Mạng công ty chặn ghcr.io / GitHub:**
   - Test: `curl -I https://ghcr.io` → 4xx/5xx hoặc timeout
   - Fix: dùng wifi cá nhân, 4G hotspot, hoặc xin IT mở firewall.

2. **DNS không resolve:**
   - Test: `nslookup ghcr.io`
   - Fix: đổi DNS sang 8.8.8.8 hoặc 1.1.1.1 tạm thời.

3. **Proxy nội bộ:**
   - Set env: `export HTTPS_PROXY=http://proxy.viettel.com.vn:8080`
   - Set proxy cho Docker: chỉnh `~/.docker/config.json` hoặc Docker Desktop settings.

4. **GitHub rate limit (anonymous pull):**
   - Hiếm gặp với ghcr.io. Nếu vẫn xảy ra, login GitHub: `docker login ghcr.io -u <username>`

### Wizard treo ở `Đang gọi getUpdates ...`

Telegram API timeout (mặc định 10s trong wizard).

**Fix:**
- Verify mạng tới `api.telegram.org`: `curl -I https://api.telegram.org`
- Nếu mạng OK nhưng API trả slow → thử lại sau vài phút.
- Nếu Viettel intranet chặn Telegram → tool **không chạy được trên mạng đó**. Dùng 4G hoặc mạng cá nhân.

---

## Auth (Telethon login)

### ❌ `ERR-DIST-003: Telethon auth fail sau 3 lần.`

Telethon từ chối login userbot.

**Nguyên nhân:**

1. **Nhập sai OTP** — Telegram gửi mã sai vị trí (vào Telegram app khác). Kiểm tra app Telegram trên điện thoại bạn → check chat "Telegram" (account chính thức).
2. **2FA password sai** — đây là password riêng bạn đặt ở Telegram Settings → Privacy & Security → Two-Step Verification.
3. **Telegram tạm khoá account** — quá nhiều login fail. Đợi 1-24h rồi thử lại.
4. **SĐT format sai** — phải kèm mã quốc gia: `+84912345678` (KHÔNG dấu cách, KHÔNG ngoặc).

**Fix:**
- Chạy lại `./setup.sh` (wizard sẽ detect session đã có và skip nếu auth trước đó success).
- Nếu vẫn fail: xoá `data/mentions_session.session*` rồi chạy lại.

### Telethon prompt "Please enter your password (8 chars or more):"

Account của bạn có 2FA. Nhập password bạn đã set ở Telegram Settings → Two-Step Verification.

Nếu **quên password 2FA**: vào Telegram app → Settings → Two-Step Verification → "Forgot password" → reset qua email (nếu đã set email recovery) hoặc disable 2FA tạm thời.

### `AuthKeyDuplicatedError`

Telethon session đang được dùng trên nhiều máy đồng thời.

**Fix:** Xoá session file cũ, chạy lại setup:
```bash
rm data/mentions_session.session
./setup.sh
```

> ⚠️ **Quy tắc:** 1 session = 1 máy. Không copy session file giữa máy.

---

## chat_id

### ❌ `Không phát hiện được chat_id sau 3 lần thử.`

Wizard gọi `getUpdates` của bot nhưng không tìm thấy message `/start` nào.

**Nguyên nhân:**

1. **Bạn gửi `/start` cho SAI bot** — wizard hiển thị username bot đúng. Verify đã gửi cho bot đó.
2. **Bot token sai** — wizard sẽ sai khi gọi getMe. Kiểm tra lại token từ BotFather.
3. **Update đã bị consume** — Telegram getUpdates chỉ trả các update CHƯA được consume. Nếu wizard gọi 2 lần thì lần 2 không thấy nữa. Fix: gửi `/start` lại trước mỗi attempt.
4. **Bot bị Telegram tạm dừng** — hiếm. Tạo bot mới qua BotFather.

**Debug thủ công:**
```bash
# Replace TOKEN với bot token thực
curl -s "https://api.telegram.org/botTOKEN/getMe"
curl -s "https://api.telegram.org/botTOKEN/getUpdates"
```
Tìm `"chat":{"id":XXX, ...}` — số đó là chat_id.

### Wizard gửi test message nhưng tôi không nhận

- Verify wizard in **"chat_id: <số>"** đúng. Số dương = DM, số âm = group.
- Verify mở **đúng bot** trên Telegram (đôi khi 2 bot tên giống nhau).
- Thử gửi `/start` lại cho bot, đảm bảo conversation open.

---

## Container

### ❌ `ERR-DIST-004: Container không khởi động được.`

Wizard chạy `docker compose up -d` nhưng container fail.

**Debug:**
```bash
docker compose logs --tail 100 bot
```

**Nguyên nhân thường gặp:**

1. **Image không pull được** → xem [Network](#network).
2. **`.env` thiếu hoặc sai format** → mở `.env` check 5 dòng env vars.
3. **Session file permission sai** → `chmod 600 data/mentions_session.session`.
4. **Port conflict** → MentionMate không expose port; không thể vướng port conflict. Nếu log báo port → có thể là image lỗi, retry pull.

### Container start nhưng `restarting (1)` liên tục

Tool crash ngay sau start. Xem log:
```bash
docker compose logs bot
```

Tìm dòng có "Error" hoặc "Exception". Lỗi phổ biến:
- `AuthKeyDuplicatedError` → xem [Auth](#auth-telethon-login)
- `ConnectionError` / `OSError: Network is unreachable` → xem [Network](#network)
- `KeyError: 'TG_API_ID'` → `.env` chưa load. Verify `env_file: .env` trong docker-compose.yml.

### Container health = `unhealthy`

```bash
docker inspect mentionmate --format '{{.State.Health.Status}}'
```

`pgrep` không tìm thấy `python main.py`. Container đang restart hoặc đã crash. Xem log.

---

## Update

### ❌ `ERR-DIST-006: Container không pick up image mới.`

Sau `update.sh`, container vẫn dùng image cũ.

**Fix:**
```bash
docker compose down
docker compose pull
docker compose up -d --force-recreate
```

### Update mất session file

`update.sh` **không** xoá session. Nếu session bị mất sau update:
1. Verify volume mount: `docker compose config | grep volumes`
2. Check thư mục `./data` còn không.
3. Khôi phục từ backup `data/mentions_session.backup.*` nếu có.

---

## Không nhận alert

Container running OK, nhưng không nhận alert khi có người mention.

**Checklist:**

1. **Container đang chạy:** `docker compose ps` → status `Up`.
2. **Userbot đã connect:** `docker compose logs bot | grep "Đang chạy"` → phải thấy "✅ Đang chạy: userbot lắng nghe..."
3. **`@username` đúng:** kiểm tra `.env` → `TG_MY_USERNAME=` phải khớp username Telegram của bạn (không có @).
4. **Group có bot:** userbot phải là member của group đó. Tool KHÔNG nhận được alert từ group bạn không tham gia.
5. **Mention thật sự là @mention:** Telegram `@username` thật (autocomplete khi gõ @) khác với gõ tay `@`. Test bằng cách paste exact `@username` vào tin nhắn.
6. **Chat_id đúng:** `.env` → `TG_ALERT_CHAT_ID=` phải là chat DM giữa bạn và bot. Nếu wizard set sai, chạy lại setup.
7. **Test thử:** từ 1 account khác, gửi `@username_bạn` trong 1 group → check log: `docker compose logs -f bot`.

---

## Windows

### ❌ `ERR-DIST-005: PowerShell đang chặn script chưa sign.`

ExecutionPolicy = Restricted.

**Fix tạm:**
```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

**Fix bền:**
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# Hoặc cho 1 session:
Set-ExecutionPolicy -Scope Process Bypass
```

> ⚠️ Một số tổ chức (vd Viettel) có Group Policy chặn cả `Bypass`. Liên hệ IT.

### Wizard treo ở "Telethon auth"

`docker run --rm -it` cần TTY. PowerShell trong VSCode integrated terminal **không có TTY** → treo.

**Fix:** Chạy `setup.ps1` trong PowerShell terminal độc lập (Windows Terminal, hoặc cmd.exe → powershell).

### `docker: 'compose' is not a docker command.`

Bạn đang dùng docker-compose v1 standalone. Wizard sẽ fallback. Khuyên upgrade Docker Desktop.

---

## macOS

### `docker info` báo error sau khi `colima start`

Đợi 5-10s cho Colima init. Verify: `colima status` → "Running".

### M1/M2/M3 Mac — image chạy chậm

Khả năng image đang chạy linux/amd64 qua Rosetta thay vì arm64 native.

**Verify:**
```bash
docker inspect mentionmate --format '{{.Architecture}}'
```

Phải là `arm64`. Nếu `amd64` → pull lại:
```bash
docker pull --platform linux/arm64 ghcr.io/hoangp47/mentionmate:latest
docker compose up -d --force-recreate
```

---

## Debugging tổng quát

### Bật verbose mode trong wizard

```bash
./setup.sh -v
```

In mọi docker command đang chạy → giúp identify command nào fail.

### Xem full log container

```bash
docker compose logs --tail 500 bot > debug.log
```

### Check container resources

```bash
docker stats mentionmate
```

Bình thường: RAM ~50-120MB, CPU < 5%.

### Reset toàn bộ

```bash
docker compose down
rm -rf data .env
./setup.sh   # cài lại từ đầu
```

> ⚠️ **Cảnh báo:** xoá `data/` = mất session, phải re-auth Telethon (cần SĐT + OTP + 2FA lại).

---

## Báo lỗi mới

Nếu lỗi của bạn không trong danh sách trên, mở [GitHub issue](https://github.com/hoangp47/mentionmate/issues/new) với:

1. **OS + version** (vd Ubuntu 22.04, Windows 11 22H2, macOS 13.5)
2. **Docker version**: `docker version`
3. **MentionMate version**: file `CHANGELOG.md` hoặc image tag
4. **Bước nào trong wizard fail**
5. **Full output** của wizard (paste vào issue, redact token/credential)
6. **Container log** (`docker compose logs --tail 100 bot`)

---

*Bổ sung lỗi mới khi pilot phát hiện. Update theo PR.*
