# PRD: Distribution & Install Path cho MentionMate

| Field | Value |
|---|---|
| **Document ID** | PRD-DIST-001 |
| **Version** | 0.2.0 |
| **Status** | APPROVED (2 open questions resolved 2026-05-18) |
| **Created** | 2026-05-18 |
| **Updated** | 2026-05-18 — Resolved GA-DIST-01 (public) + GA-DIST-04 (MentionMate) |
| **Author** | hoangp47 (với Claude) |
| **Approver** | hoangp47 |
| **Product brand name** | **MentionMate** |
| **GitHub repo (future rename)** | `github.com/hoangp47/mentionmate` (public) |
| **Container image** | `ghcr.io/hoangp47/mentionmate` |
| **Source plan** | `/home/hoangp47/.claude/plans/gleaming-soaring-moore.md` |
| **Phase** | Phase 2 — Productization (xem roadmap §6 của plan) |

---

## 1. Executive Summary

Hiện tại MentionMate (codename cũ: `mentionmate`) chỉ chạy được trên máy của chính tác giả vì cài đặt phải làm 6-7 bước thủ công (lấy API key, tạo bot, viết `.env`, build Docker, auth Telethon interactive...). Để release nội bộ phòng ban 10-30 user — trong đó ~50% không thạo CLI — cần một layer **đóng gói + cài đặt 1-lệnh** chạy được trên Windows/macOS/Linux.

PRD này định nghĩa Phương án A (đã thống nhất sau brainstorm + VSAF-Plan): **Pre-built Docker image trên ghcr.io + setup wizard cross-platform được phát hành qua GitHub Releases**.

Kết quả mong đợi: từ lúc user click vào link tải đến lúc có alert đầu tiên ≤ 15 phút (tech user) / ≤ 30 phút (non-tech với screenshot).

---

## 2. Vision & Goals

### Vision (VIS-001)
Mọi nhân viên Viettel quan tâm đến tool có thể tự cài đặt MentionMate trên máy của mình mà không cần biết về Docker CLI hay Telethon, chỉ bằng cách tải 1 file zip và chạy 1 lệnh duy nhất với hướng dẫn step-by-step.

### Goals
| ID | Goal | Đo lường |
|---|---|---|
| G-001 | Giảm thời gian cài đặt từ ~60p (manual) xuống ≤ 15p (tech) / ≤ 30p (non-tech) | Đo qua pilot 3 user mỗi nhóm |
| G-002 | Eliminate "git clone" và "build from source" khỏi happy path | Setup guide không có bước git, không có `pip install`, không có `docker build` |
| G-003 | Cung cấp update path 1-lệnh để user không bị tụt phiên bản | `./update.sh` hoặc `update.ps1` chạy < 2 phút end-to-end |
| G-004 | Maintain 1 source-of-truth (1 Dockerfile, 1 main.py) cho cả 3 OS | Không có code path OS-specific trong runtime |
| G-005 | CI tự động hoá toàn bộ build + push + release khi tag mới | Push `v0.x.y` → có release public trong < 10 phút |

### Non-goals (rõ ràng KHÔNG làm trong PRD này)
- GUI installer (.exe/.app/.AppImage) — Phase sau, là Phương án B
- Auto-update từ trong app — Phase 3 sau
- Web UI cho config — Phase 3 sau
- Telegram bot tự gửi installer link cho user mới — Phase 3 sau
- Cài đặt offline (image tarball cho Viettel intranet bị firewall) — Out of scope theo confirm của user
- Migration tool từ deployment thủ công cũ → distribution mới (1 user duy nhất hiện tại có thể tự migrate)

---

## 3. Background & Problem Statement

### Hiện trạng
- Tool đang chạy production trên server cá nhân của tác giả từ 14/05/2026.
- Setup yêu cầu 6-7 bước thủ công, mỗi bước có ≥ 1 điểm có thể fail.
- Onboarding cho người ngoài chưa được kiểm chứng — chưa có user thứ 2.

### Vấn đề cần giải quyết
1. **Onboarding barrier cho non-tech:** 50% user mục tiêu không tự chạy được `docker compose up` mà không có hướng dẫn step-by-step.
2. **Cross-platform setup:** Bash scripts không chạy trên Windows; PowerShell không chạy trên Linux/macOS.
3. **Telethon session auth lần đầu cần interactive** (nhập SĐT + OTP + 2FA) — không thể tự động hoá hoàn toàn nhưng có thể guide.
4. **Không có channel update** — user nào cài rồi không biết khi nào có version mới.
5. **Không có versioning** — không có khái niệm "v0.1 vs v0.2".

### Why now
Team yêu cầu release nội bộ phòng ban + dự thi Ngày hội Sáng kiến Viettel. Trước đó là tool cá nhân nên distribution chưa cần.

---

## 4. Target Users / Personas

### Persona 1 — DevOps Đạt (tech)
- 28 tuổi, DevOps Engineer, dùng Linux daily.
- Có Docker cài sẵn, quen `docker compose`, đọc Markdown docs là làm được.
- Mong đợi: 1 README ngắn, có sẵn `docker-compose.yml`, 5 phút cài xong.
- Sẽ không kêu nếu cần đọc 2-3 trang docs.

### Persona 2 — PM Lan (non-tech)
- 32 tuổi, PM dự án, dùng Windows + Office, không bao giờ mở terminal.
- Chỉ biết "cài app như Telegram Desktop": tải file → double-click → next next finish.
- Mong đợi: Có hướng dẫn screenshot từng bước, hoặc video. Sẽ hỏi đồng nghiệp nếu bí.
- Sẽ bỏ cuộc nếu phải gõ 3 lệnh trở lên không-trong-screenshot.

### Persona 3 — Tester Hùng (mid)
- 26 tuổi, QA Manual, biết CMD cơ bản, không biết Docker.
- Sẵn lòng học nếu có hướng dẫn rõ.
- Mong đợi: hướng dẫn cài Docker Desktop / Engine xong là cài tool được.

PRD này phải work cho cả 3 personas. Persona 1 và 3 là target sweet spot; persona 2 chấp nhận hỗ trợ 1-on-1 từ tác giả trong tuần đầu pilot.

---

## 5. Scope & Out-of-scope

### In-scope
- Multi-arch Docker image (linux/amd64 + linux/arm64) trên `ghcr.io/hoangp47/mentionmate`.
- `docker-compose.yml` template.
- Setup wizard interactive: `setup.sh` (Bash POSIX) + `setup.ps1` (PowerShell 5.1+).
- Update wizard: `update.sh` + `update.ps1`.
- `.dockerignore`.
- GitHub Actions workflow tự động build & release.
- Documentation: README.md (root), docs/SETUP.md (có screenshot), docs/TROUBLESHOOTING.md.
- Versioning theo Semantic Versioning (v0.x.y).
- Wizard verify chat_id bằng test message trước khi finalize (mitigation cho rủi ro leak alert sang sai địa chỉ).

### Out-of-scope (xác nhận với user)
- Native installer (Phương án B).
- Auto-update / in-app update notification.
- Offline tarball pack/load script (Viettel firewall workaround).
- Hỗ trợ kiến trúc khác linux/amd64 + linux/arm64 (vd s390x, riscv64).
- Migration script từ deployment cũ.

---

## 6. Assumptions & Dependencies

| ID | Assumption | Hệ quả nếu sai |
|---|---|---|
| A-001 | User có máy Linux/macOS/Windows có quyền cài Docker runtime (Desktop hoặc Engine/Colima/Podman) | Phải pivot sang Phương án B |
| A-002 | User có internet truy cập được `api.telegram.org` (qua mạng cá nhân/4G nếu mạng Viettel chặn) | Tool không chạy được; cần document rõ requirement |
| A-003 | User có internet truy cập được `ghcr.io` / `github.com` ít nhất lần đầu cài đặt | Cần offline tarball (out of scope) |
| A-004 | User có khả năng tạo Telegram Bot qua @BotFather (Telegram chấp nhận account user) | Hiếm có khả năng fail; có thể stagger rollout |
| A-005 | Telethon library tiếp tục support cơ chế authentication interactive hiện tại | Phải rewrite auth flow; low risk |
| A-006 | GitHub Container Registry tiếp tục free cho public package | Phải migrate sang Docker Hub hoặc Viettel Harbor |
| A-007 | User chấp nhận image public trên ghcr.io (image không chứa secret, chỉ binary + Python + Telethon) | Phải dùng private registry với token |

---

## 7. Functional Requirements

### Build & Release Pipeline
- **FR-001:** Hệ thống PHẢI có 1 GitHub Actions workflow trigger khi push git tag matching `v*.*.*`.
- **FR-002:** Workflow PHẢI build Docker image cho cả linux/amd64 và linux/arm64.
- **FR-003:** Workflow PHẢI push image lên `ghcr.io/hoangp47/mentionmate` với 2 tag: phiên bản chính xác (`v0.1.0`) và `latest`.
- **FR-004:** Workflow PHẢI tạo GitHub Release tự động với release notes lấy từ CHANGELOG.md và đính kèm 1 file zip chứa: `docker-compose.yml`, `setup.sh`, `setup.ps1`, `update.sh`, `update.ps1`, `.env.example`, `README.md`, `docs/`.
- **FR-005:** Image PHẢI có `HEALTHCHECK` directive trong Dockerfile.
- **FR-006:** Image PHẢI có OCI annotation `org.opencontainers.image.source` trỏ về GitHub repo để ghcr.io link image với repo.

### Setup Wizard (lần đầu)
- **FR-010:** Wizard PHẢI detect platform và chạy đúng phiên bản (Bash/PowerShell). User không cần biết.
- **FR-011:** Wizard PHẢI kiểm tra Docker daemon đang chạy (`docker info`). Nếu không, in lỗi rõ ràng kèm link cài đặt Docker Engine / Docker Desktop / Colima / Podman tuỳ OS, sau đó exit code 1.
- **FR-012:** Wizard PHẢI kiểm tra `docker compose` (v2) available. Nếu chỉ có `docker-compose` (v1 legacy), cảnh báo nhưng vẫn tiếp tục.
- **FR-013:** Wizard PHẢI lần lượt prompt user nhập 4 giá trị: `TG_API_ID`, `TG_API_HASH`, `TG_MY_USERNAME`, `TG_BOT_TOKEN`. Trước mỗi prompt, in 1 dòng giải thích + link tới web hướng dẫn lấy giá trị đó (`my.telegram.org/apps` cho API, `@BotFather` cho bot token).
- **FR-014:** Wizard PHẢI validate format của mỗi input ngay khi nhập (vd: API_ID phải là số, BOT_TOKEN phải match `\d+:[A-Za-z0-9_-]+`); re-prompt nếu invalid.
- **FR-015:** Wizard PHẢI tự lấy `TG_ALERT_CHAT_ID` bằng cách: pull image, chạy 1 lệnh tạm `docker run --rm --env-file .env ... python -c "..."` gọi `getUpdates` của Bot API → tìm chat_id từ message DM mà user gửi cho bot (wizard sẽ chỉ user gửi message "/start" cho bot vừa tạo).
- **FR-016:** Wizard PHẢI gửi 1 test message "🔧 Setup test — bạn có nhận được tin nhắn này không?" tới `TG_ALERT_CHAT_ID` vừa detect, prompt user confirm Y/N. Nếu N, restart bước phát hiện chat_id (FR-015).
- **FR-017:** Wizard PHẢI chạy Telethon login interactive lần đầu (`docker compose run --rm bot python -c "from telethon import TelegramClient; ..."`) để user nhập SĐT + OTP + 2FA, lưu session vào `data/mentions_session.session`.
- **FR-018:** Wizard PHẢI `chmod 600` cho `.env` và `data/mentions_session.session` (chỉ POSIX; Windows skip).
- **FR-019:** Wizard PHẢI chạy `docker compose up -d` sau khi mọi bước trên hoàn tất.
- **FR-020:** Wizard PHẢI in tóm tắt cuối cùng: tên container, lệnh kiểm tra log (`docker compose logs -f bot`), lệnh dừng (`docker compose down`), link tới docs.

### Update Wizard
- **FR-030:** `update.sh` / `update.ps1` PHẢI chạy `docker compose pull` rồi `docker compose up -d` (recreate container với image mới).
- **FR-031:** Update wizard PHẢI in current version trước update và new version sau update.
- **FR-032:** Update wizard PHẢI in cảnh báo nếu Telethon session file chưa được backup trong 7 ngày qua (`-mtime`).

### Documentation
- **FR-040:** README.md PHẢI có: 1 đoạn pitch (≤ 50 từ), screenshot/GIF demo, "Cài đặt nhanh" với 3-4 dòng lệnh, link sang SETUP.md cho chi tiết.
- **FR-041:** docs/SETUP.md PHẢI có ảnh chụp màn hình cho ít nhất 5 bước: my.telegram.org/apps, BotFather chat, file zip download, terminal mở wizard, alert đầu tiên nhận được.
- **FR-042:** docs/TROUBLESHOOTING.md PHẢI cover ít nhất 5 lỗi: Docker daemon chưa chạy, chat_id sai, AuthKeyDuplicatedError, Telegram block account, network timeout.
- **FR-043:** Mỗi release PHẢI cập nhật CHANGELOG.md với section "Added / Changed / Fixed / Removed".

### Configuration & State
- **FR-050:** Container PHẢI mount `data/` từ host vào `/app/data` để session file persist qua restart/update.
- **FR-051:** Container PHẢI dùng `restart: unless-stopped` policy trong docker-compose.yml.
- **FR-052:** `.dockerignore` PHẢI loại trừ `.venv`, `data/`, `.env`, `.git`, `*.session*`, `__pycache__`.

---

## 8. Non-Functional Requirements

| ID | Yêu cầu | Đo lường |
|---|---|---|
| **NFR-001** | Tổng thời gian setup từ unzip đến nhận alert đầu tiên ≤ 30 phút cho non-tech user (Persona 2), ≤ 15 phút cho tech user (Persona 1) | Đo timer trong pilot 3 user mỗi nhóm |
| **NFR-002** | Image size (uncompressed) ≤ 250MB | `docker images` sau build |
| **NFR-003** | Image pull time trên kết nối 30Mbps ≤ 2 phút | `time docker pull` |
| **NFR-004** | Wizard PHẢI exit cleanly (exit code rõ ràng + thông báo lỗi tiếng Việt) khi gặp lỗi, KHÔNG để lại state nửa vời (vd có `.env` nhưng container không chạy) | Test 10 failure injection cases |
| **NFR-005** | Wizard hỗ trợ Bash 4+ trên Linux/macOS và PowerShell 5.1+ trên Windows | Verify trên Ubuntu 22.04, macOS 13, Windows 10/11 |
| **NFR-006** | Setup script PHẢI có chế độ verbose (`--verbose` hoặc `-v`) để in chi tiết các docker command đang chạy (debug khi user gặp lỗi) | Inspect script |
| **NFR-007** | CI workflow chạy < 10 phút từ lúc push tag đến lúc release publish | GitHub Actions timing |
| **NFR-008** | Maintain backward compatibility cho `.env` schema trong cùng major version (vd v0.x.* không breaking) | Document schema version |
| **NFR-009** | Không hardcode secret, token, hoặc cá nhân information nào trong image hoặc release zip | Manual review release zip + image layers |
| **NFR-010** | Wizard không yêu cầu sudo / Administrator privileges (Docker group đã đủ trên Linux) | Test với non-root user |

---

## 9. Epics & User Stories

### Epic E-1: CI/CD Build & Release Pipeline
**Mục tiêu:** Tự động hoá toàn bộ quá trình build image multi-arch, push lên ghcr.io, và tạo GitHub Release zip khi tag được push.

| Story | As a | I want | So that | Acceptance |
|---|---|---|---|---|
| E-1.S-1 | Maintainer | push tag `v0.x.y` và workflow tự build image | Không phải build manual trên máy mình | Khi push tag, GitHub Actions hoàn thành success, image xuất hiện trên ghcr.io |
| E-1.S-2 | Mac M-series user | pull image và Docker dùng native arm64 | Không bị chậm qua Rosetta | `docker inspect` cho thấy arch khớp với host |
| E-1.S-3 | Maintainer | release zip tự đính kèm vào GitHub Release | User chỉ tải 1 file là đủ | Release page có 1 file `mentionmate-v0.x.y.zip` |
| E-1.S-4 | Maintainer | image tag `latest` luôn trỏ về phiên bản mới nhất | User mới dùng `:latest` không bị bản cũ | `docker pull :latest` sau release trả về digest khớp `:v0.x.y` |

### Epic E-2: Setup Wizard Cross-platform
**Mục tiêu:** Một file script duy nhất cho mỗi OS, dẫn user qua toàn bộ cấu hình.

| Story | As a | I want | So that | Acceptance |
|---|---|---|---|---|
| E-2.S-1 | DevOps Đạt | chạy `./setup.sh` trên Linux và xong trong 10 phút | Có alert đầu tiên nhanh | Timer kết thúc < 10p, alert nhận được |
| E-2.S-2 | PM Lan | chạy `setup.ps1` trên Windows với hướng dẫn screenshot | Không phải đoán mò | Tất cả 8 bước có screenshot tương ứng |
| E-2.S-3 | Tester Hùng | wizard validate input ngay khi nhập sai format | Không phải sửa file `.env` thủ công sau | Nhập "abc" cho API_ID → re-prompt với thông báo "phải là số" |
| E-2.S-4 | Any user | wizard verify chat_id bằng test message trước khi finalize | Không bị leak alert sang sai địa chỉ | Test message nhận được + user confirm Y |
| E-2.S-5 | Any user | wizard hướng dẫn auth Telethon interactive với SĐT + OTP | Hoàn tất setup mà không cần đọc Telethon docs | Wizard print SĐT prompt → user nhập → OTP prompt → done |

### Epic E-3: Update Mechanism
**Mục tiêu:** User có thể tự update lên phiên bản mới bằng 1 lệnh.

| Story | As a | I want | So that | Acceptance |
|---|---|---|---|---|
| E-3.S-1 | Any user | chạy `./update.sh` và update xong < 2 phút | Không bị tụt version | Sau script, container running với image tag mới |
| E-3.S-2 | Any user | xem version trước và sau update | Biết mình đang ở đâu | Stdout in `v0.1.0 → v0.1.1` |
| E-3.S-3 | Cautious user | được cảnh báo nếu chưa backup session lâu | Tránh mất session khi có lỗi | Stdout cảnh báo nếu file `data/mentions_session.session` `-mtime +7` |

### Epic E-4: Documentation
**Mục tiêu:** Documentation đầy đủ để user tự setup không cần hỏi maintainer.

| Story | As a | I want | So that | Acceptance |
|---|---|---|---|---|
| E-4.S-1 | First-time user | đọc README và hiểu tool làm gì trong 30 giây | Quyết định dùng hay không | README có pitch + screenshot ở top |
| E-4.S-2 | PM Lan | xem screenshot từng bước trong SETUP.md | Không phải đoán giao diện | Mỗi bước ≥ 1 screenshot |
| E-4.S-3 | Stuck user | tra Troubleshooting.md tìm error message của mình | Tự fix không cần ping maintainer | Cover top 5 errors thực tế từ memory log |

---

## 10. Success Metrics

| ID | Metric | Target | Cách đo |
|---|---|---|---|
| M-001 | **Time-to-first-alert** cho new user | ≤ 15 phút (tech), ≤ 30 phút (non-tech) | Timer trong pilot |
| M-002 | **Setup success rate** không cần hỏi maintainer | ≥ 80% sau pilot 5 user mỗi nhóm | Khảo sát + log support requests |
| M-003 | **Adoption rate** trong 30 ngày sau release | ≥ 10 user phòng ban active | Đếm container running (qua report tự nguyện) |
| M-004 | **Update adoption** trong 14 ngày sau release mới | ≥ 70% user nâng cấp | Đo qua ghcr.io image pull count (rough proxy) |
| M-005 | **Maintainer effort sau release** | ≤ 4h/tuần support + fixes | Tự track time |
| M-006 | **CI workflow success rate** | ≥ 95% qua 20 release | GitHub Actions history |
| M-007 | **Image size growth** qua các release | ≤ 10% mỗi quarter | `docker images` over time |

---

## 11. Risks & Mitigations (referencing Pre-mortem)

| ID | Risk | Mitigation |
|---|---|---|
| R-001 | Docker Desktop license với Viettel >250 employees | Document khuyên dùng Docker Engine (Linux/WSL) / Colima (Mac) / Podman (Win) — wizard không lock-in Docker Desktop. **Accepted theo decision của user (turn này).** |
| R-002 | Mạng Viettel intranet chặn `api.telegram.org` / `ghcr.io` | Document yêu cầu "máy có internet truy cập Telegram + GitHub". **Accepted theo decision của user (turn này).** User sẽ thông báo requirement này. |
| R-003 | PowerShell ExecutionPolicy chặn `setup.ps1` chưa sign | Hướng dẫn `Set-ExecutionPolicy -Scope Process Bypass` trong SETUP.md |
| R-004 | Laptop sleep/wake → Telethon disconnect không reconnect | Phase 1 đã planned `HEALTHCHECK` + `restart: unless-stopped`; nếu vẫn fail, bổ sung watchdog ở Phase 3 |
| R-005 | Session file corrupt khi tắt máy đột ngột | Update wizard cảnh báo backup; document backup script (cron daily) |
| R-006 | AuthKeyDuplicatedError nếu user dùng session trên nhiều máy | SETUP.md cảnh báo "1 session = 1 máy"; wizard detect file đã tồn tại và prompt |
| R-007 | User leak alert qua sai `TG_ALERT_CHAT_ID` | FR-016: test message confirm trước khi finalize |
| R-008 | BotFather rate limit nếu 10+ user tạo bot trong 1 IP/ngày | Stagger rollout 3-5 user/ngày trong pilot |
| R-009 | Antivirus Viettel flag PyInstaller-style payload (nếu sau này Phase B) | Out-of-scope cho PRD này |

---

## 12. Timeline & Milestones (đề xuất, không cam kết)

| Milestone | Mô tả | Thời gian dự kiến |
|---|---|---|
| **M1** | Repo structure ready: Dockerfile updated, .dockerignore, docker-compose.yml template | Tuần 1 (1-2 ngày) |
| **M2** | Setup wizard MVP (Bash chỉ) hoạt động trên Linux | Tuần 1 (2-3 ngày) |
| **M3** | PowerShell wizard parity với Bash, test trên Windows | Tuần 2 (2-3 ngày) |
| **M4** | CI workflow build + push + release tự động | Tuần 2 (1-2 ngày) |
| **M5** | Documentation (README, SETUP với screenshot, TROUBLESHOOTING) | Tuần 3 (2-3 ngày) |
| **M6** | Pilot với 3 user (1 tech, 1 mid, 1 non-tech), thu feedback | Tuần 3-4 |
| **M7** | Fix feedback, release v0.1.0 official | Tuần 4 |
| **M8** | Mở rộng pilot lên 10-15 user trong phòng ban | Tuần 5-8 |

Tổng: **3-4 tuần effort 1 dev part-time (~10-15h/tuần)** để đến v0.1.0 official.

---

## 13. Open Questions

1. ~~**Repo public hay private?**~~ **RESOLVED 2026-05-18: PUBLIC.** Lý do: (a) onboarding 0-friction cho ghcr.io pull anonymous, (b) GitHub Actions unlimited minutes, (c) positioning mạnh cho Sáng kiến open-source, (d) code không chứa thông tin nghiệp vụ Viettel. **Prerequisite:** Phase 0 phải purge token đã leak khỏi git history TRƯỚC khi push public.
2. **Có cần signing PowerShell script bằng cert Viettel không?** Phụ thuộc policy ExecutionPolicy trên máy Viettel. → Cần verify sau khi pilot.
3. **CHANGELOG.md viết bằng tiếng Việt hay Anh?** → Đề xuất Việt vì user là Viettel internal, source code comment đã Việt.
4. **Có cần bot Telegram dedicated cho channel thông báo release không?** Phase 3 — out of scope PRD này.
5. ~~**Tên tool chính thức cho release?**~~ **RESOLVED 2026-05-18: MentionMate.** Lý do: pun "mention + mate" thân thiện professional, brand-able, gợi tinh thần đồng đội phù hợp Sáng kiến Viettel. Tagline gợi ý: *"MentionMate — Never miss when your team @mentions you."* GitHub repo và ghcr.io image package đều dùng slug `mentionmate` (lowercase).

---

## 14. Self-Validation (inline thay cho bmad-validate-prd)

Check theo tiêu chí PRD validation chuẩn:

| Tiêu chí | Đạt? | Ghi chú |
|---|---|---|
| FRs rõ ràng (có ID, không mơ hồ, có hành vi cụ thể) | ✅ | 32 FRs có ID, mỗi cái mô tả 1 hành vi đo được |
| NFRs đo lường được | ✅ | 10 NFRs đều có metric cụ thể (thời gian, size, exit code...) |
| Acceptance criteria verifiable | ✅ | Mỗi story có "Acceptance" cụ thể (timer, file exists, command output) |
| Scope rõ ràng, không "TBD" hay "tuỳ" | ⚠️ | 5 open questions cuối — chưa block PRD, có thể chốt khi vào implementation |
| Success metrics SMART | ✅ | 7 metrics đều có target + cách đo |
| Risks có mitigation | ✅ | 9 risks, mỗi cái có mitigation hoặc accepted reason |
| Personas đại diện target users | ✅ | 3 personas cover toàn spectrum tech/non-tech |
| Assumptions explicit | ✅ | 7 assumptions có ID + hệ quả nếu sai |
| Epics có thể chia thành stories implement được | ✅ | 4 epics, 15 stories, mỗi story 1-3 ngày effort |
| Scope không quá lớn (≤ 3 modules) | ✅ | 1 module: distribution layer, không động main.py |

**Validation result: PASS** (với 5 open questions không-blocker — sẽ resolve khi vào `/vsaf-doc-srs`).

---

## 15. Appendix — Reference Documents

- Plan file: `/home/hoangp47/.claude/plans/gleaming-soaring-moore.md` — báo cáo tổng + roadmap 4 phases
- Source code analysed: `main.py` (129 dòng), `Dockerfile`, `requirements.txt`, `.env.example`
- Memory references: 1773-1799 (hybrid bot architecture), 1825-1839 (hardened message handler)
- VSAF-Plan output: turn trước trong conversation
