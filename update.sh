#!/usr/bin/env bash
# MentionMate — Update wizard cho Linux/macOS
# Docs: https://github.com/hoangp47/mentionmate
#
# Chạy: ./update.sh

set -euo pipefail

readonly IMAGE="ghcr.io/hoangp47/mentionmate"
readonly SESSION_FILE="./data/mentions_session.session"

if [[ -t 1 ]]; then
    C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_BOLD=$'\e[1m'; C_RESET=$'\e[0m'
else
    C_GREEN=''; C_YELLOW=''; C_RED=''; C_BOLD=''; C_RESET=''
fi

ok()   { printf '%s✅%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf '%s⚠️%s  %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
err()  { printf '%s❌%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }

# Detect compose command
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    err "Không tìm thấy docker compose / docker-compose."
    exit 1
fi

# Verify trong thư mục đúng
if [[ ! -f docker-compose.yml ]]; then
    err "Không tìm thấy docker-compose.yml. Chạy script này trong thư mục MentionMate."
    exit 1
fi

printf '%s━━━ MentionMate Update ━━━%s\n\n' "$C_BOLD" "$C_RESET"

# Step 1: Hiển thị phiên bản hiện tại (FR-031)
current_digest=$(docker inspect mentionmate --format '{{.Image}}' 2>/dev/null || echo "")
if [[ -n "$current_digest" ]]; then
    current_tag=$(docker images --no-trunc --format '{{.Repository}}:{{.Tag}}@{{.ID}}' \
        | grep "^${IMAGE}:" | grep "${current_digest}" | head -1 | awk -F'@' '{print $1}' || echo "unknown")
    printf '📍 Phiên bản hiện tại: %s%s%s\n' "$C_BOLD" "$current_tag" "$C_RESET"
else
    warn "Không phát hiện container hiện tại (có thể chưa từng up)."
fi

# Step 2: Cảnh báo session backup (FR-032)
if [[ -f "$SESSION_FILE" ]]; then
    # mtime > 7 ngày qua?
    if find "$SESSION_FILE" -mtime +7 -print -quit 2>/dev/null | grep -q .; then
        warn "Session file mtime > 7 ngày — recommend backup trước khi update."
        printf 'Backup session ngay? (Y/n) [Y]: '
        read -r ans
        if [[ ! "${ans,,}" =~ ^n(o)?$ ]]; then
            backup="${SESSION_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
            cp "$SESSION_FILE" "$backup"
            ok "Backup: $backup"
        fi
    fi
fi

# Step 3: Pull mới (FR-030)
printf '\n⬇️  Đang pull image mới...\n'
if ! $COMPOSE_CMD pull; then
    err "ERR-DIST-002: Pull fail. Kiểm tra mạng truy cập ghcr.io."
    exit 1
fi

# Step 4: So sánh digest (ALT1)
new_digest=$($COMPOSE_CMD images --format json bot 2>/dev/null | grep -oE '"ID":"[^"]+"' | head -1 | cut -d'"' -f4 || echo "")
if [[ -n "$current_digest" && -n "$new_digest" && "$current_digest" == *"$new_digest"* ]]; then
    ok "Đã ở phiên bản mới nhất — không cần update."
    exit 0
fi

# Step 5: Recreate container (FR-030)
printf '\n🔄 Recreating container với image mới...\n'
if ! $COMPOSE_CMD up -d; then
    err "ERR-DIST-006: Container không khởi động lại được."
    err "Rollback: $COMPOSE_CMD up -d với tag cũ. Xem TROUBLESHOOTING.md §Update."
    exit 1
fi

sleep 3

# Step 6: Verify (FR-031)
new_tag=$(docker inspect mentionmate --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")
ok "Update xong. Image: $new_tag"
printf '\n📝 Xem log: %s%s logs -f bot%s\n' "$C_BOLD" "$COMPOSE_CMD" "$C_RESET"
