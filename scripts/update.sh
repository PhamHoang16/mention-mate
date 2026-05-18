#!/usr/bin/env bash
# MentionMate — Update wizard for Linux/macOS
# Docs: https://github.com/PhamHoang16/mention-mate
#
# Usage: ./update.sh

set -euo pipefail

# ----- Locate project root (same logic as setup.sh) -----
__locate_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "docker-compose.yml" ]]; then
        return 0
    elif [[ -f "$script_dir/docker-compose.yml" ]]; then
        cd "$script_dir"
    elif [[ -f "$script_dir/../docker-compose.yml" ]]; then
        cd "$script_dir/.."
    else
        echo "❌ Could not locate docker-compose.yml. Run update from the MentionMate directory." >&2
        exit 1
    fi
}
__locate_project_root

readonly IMAGE="ghcr.io/phamhoang16/mention-mate"
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
    err "Neither 'docker compose' nor 'docker-compose' found."
    exit 1
fi

printf '%s━━━ MentionMate Update ━━━%s\n\n' "$C_BOLD" "$C_RESET"

# Step 1: Show current version (FR-031)
current_digest=$(docker inspect mention-mate --format '{{.Image}}' 2>/dev/null || echo "")
if [[ -n "$current_digest" ]]; then
    current_tag=$(docker images --no-trunc --format '{{.Repository}}:{{.Tag}}@{{.ID}}' \
        | grep "^${IMAGE}:" | grep "${current_digest}" | head -1 | awk -F'@' '{print $1}' || echo "unknown")
    printf '📍 Current version: %s%s%s\n' "$C_BOLD" "$current_tag" "$C_RESET"
else
    warn "No running container detected (may never have been started)."
fi

# Step 2: Session backup warning (FR-032)
if [[ -f "$SESSION_FILE" ]]; then
    # mtime > 7 days ago?
    if find "$SESSION_FILE" -mtime +7 -print -quit 2>/dev/null | grep -q .; then
        warn "Session file mtime > 7 days — backup recommended before updating."
        printf 'Back up session now? (Y/n) [Y]: '
        read -r ans
        if [[ ! "${ans,,}" =~ ^n(o)?$ ]]; then
            backup="${SESSION_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
            cp "$SESSION_FILE" "$backup"
            ok "Backup: $backup"
        fi
    fi
fi

# Step 3: Pull new image (FR-030)
printf '\n⬇️  Pulling new image...\n'
if ! $COMPOSE_CMD pull; then
    err "ERR-DIST-002: Pull failed. Check network access to ghcr.io."
    exit 1
fi

# Step 4: Compare digests (ALT1)
new_digest=$($COMPOSE_CMD images --format json bot 2>/dev/null | grep -oE '"ID":"[^"]+"' | head -1 | cut -d'"' -f4 || echo "")
if [[ -n "$current_digest" && -n "$new_digest" && "$current_digest" == *"$new_digest"* ]]; then
    ok "Already on the latest version — no update needed."
    exit 0
fi

# Step 5: Recreate container (FR-030)
printf '\n🔄 Recreating container with new image...\n'
if ! $COMPOSE_CMD up -d; then
    err "ERR-DIST-006: Container failed to restart."
    err "Rollback: $COMPOSE_CMD up -d with the previous tag. See TROUBLESHOOTING.md §Update."
    exit 1
fi

sleep 3

# Step 6: Verify (FR-031)
new_tag=$(docker inspect mention-mate --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")
ok "Update complete. Image: $new_tag"
printf '\n📝 Tail logs: %s%s logs -f bot%s\n' "$C_BOLD" "$COMPOSE_CMD" "$C_RESET"
