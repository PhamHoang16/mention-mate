# MentionMate

> Never miss when your team @mentions you on Telegram.

![Version](https://img.shields.io/badge/version-0.1.0--dev-blue)
![Docker](https://img.shields.io/badge/docker-multi--arch-2496ED)
![License](https://img.shields.io/badge/license-MIT-green)

**MentionMate** là 1 daemon nhỏ chạy trên máy bạn, lắng nghe các group Telegram mà bạn tham gia, và gửi **push notification riêng** mỗi khi có ai đó @mention bạn — kể cả khi notification của group đã bị mute.

Sinh ra cho dân DevOps/PM hay bị add vào nhiều group dự án và dễ miss công việc, nhưng phù hợp cho bất kỳ ai dùng Telegram nhiều cho công việc.

> _Ảnh demo / GIF sẽ được bổ sung sau pilot._

---

## Tại sao cần MentionMate?

| Vấn đề thực tế | MentionMate giải quyết thế nào |
|---|---|
| Bị add vào 10+ group Telegram dự án, mute hết để tập trung làm việc | Vẫn nghe được khi có người gọi tên mình |
| Miss mention vì group quá nhiều tin nhắn | Tool quote lại đúng message kèm link nhảy thẳng tới |
| Nhiều keyword cần theo dõi (tên dự án, tên team) | _Phase 2 sẽ thêm multi-keyword_ |
| Không muốn cài app thứ 3 trên điện thoại | Tool chạy nền, alert qua chính Telegram |

---

## Cài đặt nhanh

**Prerequisites:**
- Docker runtime (Docker Engine / Desktop / Colima / Podman) đang chạy
- Internet truy cập được `api.telegram.org` và `ghcr.io`
- 1 account Telegram cá nhân
- 5-15 phút thời gian

### 1. Tạo Telegram credentials

Trước khi chạy wizard, chuẩn bị 3 thứ:

1. **API_ID + API_HASH:** vào https://my.telegram.org/apps → đăng nhập SĐT → bấm *"API development tools"* → *"Create new application"*. Copy 2 giá trị này.
2. **Bot Token:** chat với [@BotFather](https://t.me/BotFather) → gõ `/newbot` → đặt tên + username → BotFather trả về token dạng `1234567890:AAAA...`.
3. **Username của bạn:** username Telegram (không có @).

### 2. Tải release + chạy wizard

Tải file `mentionmate-v0.x.y.zip` từ [Releases page](https://github.com/hoangp47/mentionmate/releases), giải nén, mở terminal trong thư mục, chạy:

**Linux / macOS:**
```bash
./setup.sh
```

**Windows (PowerShell):**
```powershell
.\setup.ps1
```

> Nếu PowerShell chặn: `powershell -ExecutionPolicy Bypass -File setup.ps1`

Wizard sẽ tự động:
1. Kiểm tra Docker đang chạy
2. Hỏi 4 thông tin Telegram (có validation real-time)
3. Pull image multi-arch từ ghcr.io
4. Tự phát hiện `chat_id` đích bằng cách yêu cầu bạn `/start` cho bot
5. Gửi test message để xác nhận đúng chat
6. Yêu cầu đăng nhập userbot Telegram (SĐT + OTP + 2FA nếu có)
7. Khởi động container và in summary

Tổng thời gian: **~10-15 phút** (tech) / **~20-30 phút** (lần đầu chưa quen Telegram API).

### 3. Verify

Sau khi wizard xong, từ 1 account khác hoặc bạn nhờ đồng nghiệp gửi tin nhắn `@username_của_bạn` trong 1 group bạn đang tham gia → bạn sẽ nhận alert qua bot vừa cài.

---

## Lệnh thường dùng

```bash
# Xem log live
docker compose logs -f bot

# Dừng tạm
docker compose down

# Khởi động lại
docker compose restart

# Cập nhật lên phiên bản mới
./update.sh     # hoặc .\update.ps1 trên Windows
```

---

## Documentation

- 📖 **[SETUP.md](docs/SETUP.md)** — Hướng dẫn cài đặt từng bước có screenshot
- 🔧 **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — Lỗi thường gặp và cách fix
- 📝 **[CHANGELOG.md](CHANGELOG.md)** — Version history
- 🏗️ **[Architecture](.vsaf/docs/srs/SRS-tele-FR-DIST-distribution-v1.0.md)** — Technical design

---

## Cảnh báo bảo mật

⚠️ **MentionMate sử dụng tài khoản Telegram CÁ NHÂN của bạn** thông qua Telethon userbot để đọc message group. Điều này có nghĩa là:

- Tool có quyền truy cập **TẤT CẢ** tin nhắn của bạn trên Telegram, bao gồm cả tin nhắn riêng tư.
- Tool chỉ phân tích message để tìm mention, **không lưu** nội dung tin nhắn ra ngoài máy bạn.
- File session (`data/mentions_session.session`) **tương đương credential** — không chia sẻ, không backup ra cloud.
- Khi nghỉ việc hoặc đổi máy: **revoke** session qua Telegram → Settings → Devices.
- Bạn tự chịu trách nhiệm về việc tuân thủ TOS Telegram + chính sách bảo mật thông tin của tổ chức.

Nếu bạn làm việc cho công ty có chính sách nghiêm về việc xử lý dữ liệu, hãy kiểm tra với phòng an toàn thông tin trước khi cài.

---

## Kiến trúc tóm tắt

```
Telegram group ──► Telethon userbot (đọc messages)
                        │
                        │ phát hiện @mention
                        ▼
                  Telegram Bot HTTP API (gửi alert)
                        │
                        ▼
                  Push notification → bạn
```

**Tại sao hybrid 2 client?** Userbot không thể gửi tin nhắn cho chính mình mà trigger push notification (Telegram silent self-message). Bot Telegram thì có thể gửi tin nhắn cho user (sau khi user đã `/start` với bot). → Userbot đọc + Bot gửi.

---

## Roadmap

| Phase | Mục tiêu | Trạng thái |
|---|---|---|
| **Phase 0** | Security hotfix (revoke leaked token, purge git history) | 🔴 Required before public release |
| **Phase 1** | Hardening (logging, health endpoint, retry, tests) | ⏭️ Planned |
| **Phase 2** | Productization (this release) — distribution + wizard + docs | 🟡 In progress |
| **Phase 3** | Feature expansion (multi-keyword, digest, action buttons, web UI) | ⏭️ Planned |

Full roadmap: see [internal roadmap document](.vsaf/docs/planning-artifacts/prd-distribution.md).

---

## Đóng góp / Báo lỗi

- 🐛 Bug / feature request: [GitHub Issues](https://github.com/hoangp47/mentionmate/issues)
- 💬 Discussion: TBD

---

## License

MIT — see [LICENSE](LICENSE).

---

*Made by [@hoangp47](https://github.com/hoangp47) for Viettel internal use. Open-sourced as part of Sáng kiến 2026.*
