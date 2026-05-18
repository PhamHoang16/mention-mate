#!/usr/bin/env bash
# MentionMate — Setup wizard cho Linux/macOS
# Docs: https://github.com/hoangp47/mentionmate
#
# Chạy: ./setup.sh
# Verbose mode: ./setup.sh -v

set -euo pipefail

# ----- Constants -----
readonly IMAGE="ghcr.io/hoangp47/mentionmate:latest"
readonly ENV_FILE=".env"
readonly DATA_DIR="./data"
readonly SESSION_FILE="${DATA_DIR}/mentions_session.session"
readonly COMPOSE_FILE="docker-compose.yml"

# ----- Colors -----
if [[ -t 1 ]]; then
    readonly C_RED=$'\e[31m'
    readonly C_GREEN=$'\e[32m'
    readonly C_YELLOW=$'\e[33m'
    readonly C_BLUE=$'\e[34m'
    readonly C_BOLD=$'\e[1m'
    readonly C_RESET=$'\e[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_RESET=''
fi

# ----- Verbose flag -----
VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
        -h|--help)
            cat <<EOF
MentionMate Setup Wizard

Cách dùng:
  ./setup.sh           Chạy wizard interactive
  ./setup.sh -v        Chạy verbose (in mọi docker command)
  ./setup.sh -h        Hiển thị help

Documentation: https://github.com/hoangp47/mentionmate/blob/master/docs/SETUP.md
EOF
            exit 0
            ;;
    esac
done

log_info()  { printf '%sℹ%s  %s\n' "$C_BLUE" "$C_RESET" "$1"; }
log_ok()    { printf '%s✅%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
log_warn()  { printf '%s⚠️%s  %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
log_err()   { printf '%s❌%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
log_step()  { printf '\n%s━━━ %s ━━━%s\n' "$C_BOLD" "$1" "$C_RESET"; }
log_verb()  { (( VERBOSE )) && printf '%s$%s %s\n' "$C_YELLOW" "$C_RESET" "$*" || true; }

run_cmd() {
    log_verb "$*"
    "$@"
}

abort() {
    log_err "$1"
    [[ -n "${2:-}" ]] && printf '\n%s\n' "$2"
    exit 1
}

# ----- Step 1: Check Docker (FR-011, BR-DIST-01-01) -----
check_docker() {
    log_step "1/12 Kiểm tra Docker"
    if ! command -v docker &>/dev/null; then
        abort "ERR-DIST-001: Không tìm thấy 'docker'." \
            "Vui lòng cài Docker Engine / Colima / Podman trước:
  Linux:   https://docs.docker.com/engine/install/
  macOS:   brew install colima docker (recommended, free) hoặc Docker Desktop
  Hoặc Podman: https://podman.io/docs/installation"
    fi

    if ! docker info &>/dev/null; then
        abort "ERR-DIST-001: Docker daemon chưa chạy." \
            "Khởi động Docker rồi thử lại:
  Linux:   sudo systemctl start docker (nếu dùng systemd)
  macOS:   colima start  (hoặc mở Docker Desktop)"
    fi
    log_ok "Docker daemon đang chạy."
}

# ----- Step 2: Check compose v2 (FR-012) -----
COMPOSE_CMD="docker compose"
check_compose() {
    log_step "2/12 Kiểm tra docker compose"
    if docker compose version &>/dev/null; then
        log_ok "docker compose v2 available."
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        log_warn "Chỉ có docker-compose v1 (legacy). Wizard sẽ fallback nhưng khuyên upgrade."
        COMPOSE_CMD="docker-compose"
    else
        abort "Không tìm thấy docker compose hoặc docker-compose." \
            "Hầu hết Docker Desktop/Engine modern đã bundle. Reinstall Docker."
    fi
}

# ----- Step 3: Detect existing install (BR-DIST-00-03 idempotency) -----
check_existing() {
    log_step "3/12 Kiểm tra cấu hình cũ"
    local existing=0
    [[ -f "$ENV_FILE" ]] && { log_warn ".env đã tồn tại."; existing=1; }
    [[ -f "$SESSION_FILE" ]] && { log_warn "session file đã tồn tại: $SESSION_FILE"; existing=1; }

    if (( existing )); then
        printf '\nGhi đè cấu hình cũ? (y/N) [N]: '
        read -r answer
        case "${answer,,}" in
            y|yes) log_warn "Sẽ overwrite. (session sẽ KHÔNG bị xoá — chỉ .env và prompt lại Telethon nếu cần.)" ;;
            *)    abort "Đã hủy. Cấu hình cũ giữ nguyên." ;;
        esac
    else
        log_ok "Chưa có cấu hình cũ — proceed."
    fi
}

# ----- Step 4-7: Prompt 4 env vars (FR-013, FR-014, BR-DIST-01-02) -----
prompt_with_validation() {
    local var_name="$1"
    local prompt="$2"
    local regex="$3"
    local err_msg="$4"
    local is_secret="$5"  # 0/1
    local value=""

    while true; do
        printf '\n%s\n' "$prompt"
        if (( is_secret )); then
            read -rs value
            printf '\n'
        else
            read -r value
        fi

        if [[ -z "$value" ]]; then
            log_err "Không được để trống."
            continue
        fi
        if [[ ! "$value" =~ $regex ]]; then
            log_err "$err_msg"
            continue
        fi
        printf -v "$var_name" '%s' "$value"
        break
    done
}

prompt_inputs() {
    log_step "4/12 Nhập cấu hình Telegram"

    prompt_with_validation TG_API_ID \
        "🔑 Nhập TG_API_ID (số nguyên, lấy từ https://my.telegram.org/apps):" \
        '^[0-9]+$' \
        "TG_API_ID phải là số nguyên dương." 0

    prompt_with_validation TG_API_HASH \
        "🔑 Nhập TG_API_HASH (32 ký tự hex, KHÔNG echo):" \
        '^[a-f0-9]{32}$' \
        "TG_API_HASH phải là 32 ký tự hex (a-f, 0-9)." 1

    prompt_with_validation TG_MY_USERNAME \
        "👤 Nhập username Telegram của bạn (KHÔNG có @, vd: hoangp47):" \
        '^[A-Za-z][A-Za-z0-9_]{4,31}$' \
        "Username 5-32 ký tự, bắt đầu bằng chữ, chỉ chứa chữ/số/_." 0

    prompt_with_validation TG_BOT_TOKEN \
        "🤖 Nhập TG_BOT_TOKEN từ @BotFather (KHÔNG echo, dạng <số>:<chuỗi>):" \
        '^[0-9]+:[A-Za-z0-9_-]{30,40}$' \
        "Bot token sai format. Dạng: 1234567890:AAAA...." 1
}

# ----- Step 8: Pull image (FR-007) -----
pull_image() {
    log_step "5/12 Pull Docker image"
    log_info "Đang pull $IMAGE ... (lần đầu có thể 1-2 phút)"
    if ! run_cmd docker pull "$IMAGE"; then
        abort "ERR-DIST-002: Pull image fail." \
            "Có thể do: (1) mạng không truy cập được ghcr.io, (2) firewall chặn.
Xem TROUBLESHOOTING.md §Network. Test: curl -I https://ghcr.io"
    fi
    log_ok "Image đã pull thành công."
}

# ----- Step 9: Discover chat_id + send test (FR-015, FR-016, BR-DIST-05-01) -----
discover_chat_id() {
    log_step "6/12 Phát hiện chat_id để gửi alert (sub-flow UC-DIST-05)"
    local bot_username=""
    # Lấy bot username từ getMe để hướng dẫn user
    bot_username=$(curl -fsS --max-time 10 \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/getMe" 2>/dev/null \
        | grep -oE '"username":"[^"]+"' | head -1 | cut -d'"' -f4 || echo "")

    if [[ -n "$bot_username" ]]; then
        printf '\n%s1. Mở Telegram, tìm @%s (hoặc link https://t.me/%s)\n' \
            "$C_BOLD" "$bot_username" "$bot_username"
        printf '2. Bấm START hoặc gửi /start cho bot\n'
        printf '3. Quay lại đây, nhấn Enter\n%s' "$C_RESET"
    else
        log_warn "Không lấy được username bot (token có thể sai). Cứ thử /start với bot bạn vừa tạo."
        printf '\nGửi /start cho bot trên Telegram, rồi nhấn Enter...\n'
    fi
    read -r _

    local response chat_id sender_name
    local attempt=1 max_attempts=3
    while (( attempt <= max_attempts )); do
        log_info "Đang gọi getUpdates ... (lần thử $attempt/$max_attempts)"
        response=$(curl -fsS --max-time 10 \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/getUpdates" || echo "")

        if [[ -z "$response" ]]; then
            log_warn "Không gọi được API. Thử lại?"
        else
            # Tìm chat.id của message có text bắt đầu /start
            chat_id=$(printf '%s' "$response" | python3 -c '
import sys, json
try:
    data = json.loads(sys.stdin.read())
    for u in data.get("result", []):
        msg = u.get("message") or u.get("edited_message") or {}
        text = (msg.get("text") or "").strip().lower()
        if text.startswith("/start"):
            print(msg.get("chat", {}).get("id", ""))
            sys.exit(0)
except Exception:
    pass
' 2>/dev/null || echo "")

            if [[ -n "$chat_id" && "$chat_id" =~ ^-?[0-9]+$ ]]; then
                log_ok "Tìm thấy chat_id: $chat_id"

                # Gửi test message (BR-DIST-05-01 round-trip verify)
                log_info "Đang gửi test message..."
                local send_result
                send_result=$(curl -fsS --max-time 10 -X POST \
                    "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${chat_id}" \
                    -d "text=🔧 MentionMate setup test — nếu bạn thấy tin nhắn này, cấu hình đang đúng." || echo "")

                if [[ "$send_result" == *'"ok":true'* ]]; then
                    printf '\n%sBạn có nhận được tin nhắn test trên Telegram không?%s (y/N): ' \
                        "$C_BOLD" "$C_RESET"
                    read -r confirm
                    if [[ "${confirm,,}" =~ ^y(es)?$ ]]; then
                        TG_ALERT_CHAT_ID="$chat_id"
                        return 0
                    else
                        log_warn "User không nhận được test — có thể chat_id sai. Thử lại."
                    fi
                else
                    log_warn "Gửi test fail: $send_result"
                fi
            else
                log_warn "Không thấy /start trong update gần đây. Bạn đã gửi /start cho ĐÚNG bot vừa tạo chưa?"
            fi
        fi

        attempt=$((attempt + 1))
        if (( attempt <= max_attempts )); then
            printf '\nThử lại? (Y/n): '
            read -r retry
            [[ "${retry,,}" =~ ^n(o)?$ ]] && break
            printf 'Gửi /start cho bot lần nữa, rồi nhấn Enter...\n'
            read -r _
        fi
    done

    abort "Không phát hiện được chat_id sau $max_attempts lần thử." \
        "Xem TROUBLESHOOTING.md §chat_id để debug thủ công."
}

# ----- Step 10: Write .env mode 600 (FR-018, BR-DIST-01-03) -----
write_env() {
    log_step "7/12 Ghi cấu hình vào .env"
    # Ghi qua temp file rồi rename = atomic write (NFR-REL-02)
    local tmp="${ENV_FILE}.tmp"
    cat > "$tmp" <<EOF
# Generated by MentionMate setup wizard at $(date -u +%Y-%m-%dT%H:%M:%SZ)
TG_API_ID=${TG_API_ID}
TG_API_HASH=${TG_API_HASH}
TG_MY_USERNAME=${TG_MY_USERNAME}
TG_BOT_TOKEN=${TG_BOT_TOKEN}
TG_ALERT_CHAT_ID=${TG_ALERT_CHAT_ID}
EOF
    chmod 600 "$tmp"
    mv "$tmp" "$ENV_FILE"
    log_ok "Đã ghi $ENV_FILE (permission 600)."
}

# ----- Step 11: Telethon auth interactive (FR-017) -----
telethon_auth() {
    log_step "8/12 Đăng nhập Telethon userbot (cần SĐT + OTP + 2FA nếu có)"
    mkdir -p "$DATA_DIR"

    if [[ -f "$SESSION_FILE" ]]; then
        log_info "Session file đã tồn tại — skip auth interactive."
        return 0
    fi

    log_info "Sẽ chạy 1 container interactive — nhập SĐT (vd +84912345678) khi được hỏi."
    log_info "Nếu account có 2FA, sẽ hỏi password sau OTP."
    printf '\n'

    local attempt=1 max_attempts=3
    while (( attempt <= max_attempts )); do
        if run_cmd docker run --rm -it \
            -v "$(pwd)/${DATA_DIR}:/app/data" \
            --env-file "$ENV_FILE" \
            "$IMAGE" \
            python /app/scripts/auth.py; then
            log_ok "Telethon session đã tạo: $SESSION_FILE"
            chmod 600 "$SESSION_FILE" 2>/dev/null || true
            return 0
        fi
        log_warn "Auth fail. Thử lại? ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        (( attempt <= max_attempts )) && sleep 2
    done

    abort "ERR-DIST-003: Telethon auth fail sau $max_attempts lần." \
        "Có thể do sai OTP, sai 2FA, hoặc Telegram tạm khoá account. Xem TROUBLESHOOTING.md §Auth."
}

# ----- Step 12: Start container (FR-019) -----
start_container() {
    log_step "9/12 Khởi động container MentionMate"
    if ! run_cmd $COMPOSE_CMD up -d; then
        log_err "ERR-DIST-004: Container không start."
        printf '\nLogs:\n'
        $COMPOSE_CMD logs --tail 50
        abort "Xem TROUBLESHOOTING.md §Container."
    fi

    sleep 3
    if ! $COMPOSE_CMD ps --status running | grep -q mentionmate; then
        log_err "Container đã start nhưng không ở trạng thái running. Logs:"
        $COMPOSE_CMD logs --tail 50
        abort "Xem TROUBLESHOOTING.md §Container."
    fi
    log_ok "Container 'mentionmate' đang chạy."
}

# ----- Step 13: Summary (FR-020) -----
print_summary() {
    log_step "10/12 Hoàn tất! 🎉"
    cat <<EOF

${C_GREEN}${C_BOLD}MentionMate đã được cài đặt thành công.${C_RESET}

📝 Lệnh hữu ích:
  Xem log:        ${C_BOLD}${COMPOSE_CMD} logs -f bot${C_RESET}
  Dừng:           ${C_BOLD}${COMPOSE_CMD} down${C_RESET}
  Khởi động lại:  ${C_BOLD}${COMPOSE_CMD} restart${C_RESET}
  Cập nhật:       ${C_BOLD}./update.sh${C_RESET}

📖 Documentation:  https://github.com/hoangp47/mentionmate
🐛 Báo lỗi:        https://github.com/hoangp47/mentionmate/issues

Bạn sẽ nhận alert trên Telegram khi có ai đó @${TG_MY_USERNAME:-username} trong group có userbot tham gia.
EOF
}

# ----- Main flow -----
main() {
    printf '%s\n' "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf '   MentionMate Setup Wizard (Linux/macOS)\n'
    printf '   github.com/hoangp47/mentionmate\n'
    printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$C_RESET"

    check_docker
    check_compose
    check_existing
    prompt_inputs
    pull_image
    discover_chat_id
    write_env
    telethon_auth
    start_container
    print_summary
}

main "$@"
