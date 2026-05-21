#!/usr/bin/env bash
# MentionMate — Unified wizard for Linux/macOS
# Docs: https://github.com/PhamHoang16/mention-mate
#
# Usage:
#   ./mention-mate.sh                Auto-detect: setup if not configured, update otherwise
#   ./mention-mate.sh setup          Run the interactive setup wizard
#   ./mention-mate.sh update         Pull the latest image and recreate the container
#   ./mention-mate.sh -h | --help    Show this help
#   ./mention-mate.sh -v | --verbose Verbose mode (print every docker command)

set -euo pipefail

# ----- Locate project root -----
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
        echo "❌ Could not locate docker-compose.yml. Run from the MentionMate directory." >&2
        exit 1
    fi
}
__locate_project_root

# ----- Constants -----
readonly IMAGE="ghcr.io/phamhoang16/mention-mate:latest"
readonly IMAGE_REPO="ghcr.io/phamhoang16/mention-mate"
readonly ENV_FILE=".env"
readonly DATA_DIR="./data"
readonly SESSION_FILE="${DATA_DIR}/mentions_session.session"

# ----- Colors -----
if [[ -t 1 ]]; then
    readonly C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
    readonly C_BLUE=$'\e[34m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_RESET=''
fi

# ----- CLI parsing -----
VERBOSE=0
SUBCOMMAND=""
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
        -h|--help)
            sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        setup|update) SUBCOMMAND="$arg" ;;
        *) echo "❌ Unknown argument: $arg (try -h)" >&2; exit 1 ;;
    esac
done

# ----- Logging -----
log_info()  { printf '%sℹ%s  %s\n' "$C_BLUE" "$C_RESET" "$1"; }
log_ok()    { printf '%s✅%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
log_warn()  { printf '%s⚠️%s  %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
log_err()   { printf '%s❌%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }
log_step()  { printf '\n%s━━━ %s ━━━%s\n' "$C_BOLD" "$1" "$C_RESET"; }
log_verb()  { (( VERBOSE )) && printf '%s$%s %s\n' "$C_YELLOW" "$C_RESET" "$*" || true; }

run_cmd() { log_verb "$*"; "$@"; }

abort() {
    log_err "$1"
    [[ -n "${2:-}" ]] && printf '\n%s\n' "$2"
    exit 1
}

# ----- Docker / compose detection -----
COMPOSE_CMD="docker compose"

check_docker() {
    if ! command -v docker &>/dev/null; then
        abort "ERR-DIST-001: 'docker' command not found." \
            "Install Docker Engine / Colima / Podman first. See README.md → Install."
    fi
    if ! docker info &>/dev/null; then
        abort "ERR-DIST-001: Docker daemon is not running." \
            "Start it: 'sudo systemctl start docker' (Linux) or 'colima start' (macOS)."
    fi
}

detect_compose() {
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        log_warn "Only docker-compose v1 (legacy) available. Upgrade Docker for v2."
        COMPOSE_CMD="docker-compose"
    else
        abort "Neither 'docker compose' nor 'docker-compose' found." "Reinstall Docker."
    fi
}

# ================================================================
# SETUP
# ================================================================

check_existing() {
    log_step "Checking for existing configuration"
    local existing=0
    [[ -f "$ENV_FILE" ]] && { log_warn ".env already exists."; existing=1; }
    [[ -f "$SESSION_FILE" ]] && { log_warn "Session file already exists: $SESSION_FILE"; existing=1; }

    if (( existing )); then
        printf '\nOverwrite existing config? (y/N) [N]: '
        read -r answer
        case "${answer,,}" in
            y|yes) log_warn "Will overwrite .env. (Session file is preserved.)" ;;
            *)    abort "Cancelled. Existing configuration kept." ;;
        esac
    else
        log_ok "No prior configuration found — proceeding."
    fi
}

prompt_with_validation() {
    local var_name="$1" prompt="$2" regex="$3" err_msg="$4" is_secret="$5"
    local value=""
    while true; do
        printf '\n%s\n' "$prompt"
        if (( is_secret )); then read -rs value; printf '\n'; else read -r value; fi

        if [[ -z "$value" ]]; then log_err "Value cannot be empty."; continue; fi
        if [[ ! "$value" =~ $regex ]]; then log_err "$err_msg"; continue; fi
        printf -v "$var_name" '%s' "$value"
        break
    done
}

prompt_inputs() {
    log_step "Telegram credentials"
    prompt_with_validation TG_API_ID \
        "🔑 Enter TG_API_ID (integer, from https://my.telegram.org/apps):" \
        '^[0-9]+$' "TG_API_ID must be a positive integer." 0
    prompt_with_validation TG_API_HASH \
        "🔑 Enter TG_API_HASH (32 hex characters, input hidden):" \
        '^[a-f0-9]{32}$' "TG_API_HASH must be exactly 32 hex characters." 1
    prompt_with_validation TG_MY_USERNAME \
        "👤 Enter your Telegram username (without @, e.g. hoangp47):" \
        '^[A-Za-z][A-Za-z0-9_]{4,31}$' \
        "Username must be 5-32 chars, start with a letter, contain only letters/digits/underscore." 0
    prompt_with_validation TG_BOT_TOKEN \
        "🤖 Enter TG_BOT_TOKEN from @BotFather (input hidden, format <id>:<secret>):" \
        '^[0-9]+:[A-Za-z0-9_-]{30,40}$' \
        "Invalid bot token format. Expected: 1234567890:AAAA...." 1
}

pull_image() {
    log_step "Pulling Docker image"
    log_info "Pulling $IMAGE ... (first pull may take 1-2 minutes)"
    if ! run_cmd docker pull "$IMAGE"; then
        abort "ERR-DIST-002: Image pull failed." \
            "Check network: curl -I https://ghcr.io. See README.md → Troubleshooting."
    fi
    log_ok "Image pulled successfully."
}

discover_chat_id() {
    log_step "Discovering chat_id"
    local bot_username
    bot_username=$(curl -fsS --max-time 10 \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/getMe" 2>/dev/null \
        | grep -oE '"username":"[^"]+"' | head -1 | cut -d'"' -f4 || echo "")

    if [[ -n "$bot_username" ]]; then
        printf '\n%s1. Open Telegram, find @%s (or https://t.me/%s)\n' "$C_BOLD" "$bot_username" "$bot_username"
        printf '2. Tap START or send /start to the bot\n'
        printf '3. Come back here and press Enter\n%s' "$C_RESET"
    else
        log_warn "Could not fetch bot username (token may be wrong)."
        printf '\nSend /start to the bot in Telegram, then press Enter...\n'
    fi
    read -r _

    local response chat_id attempt=1 max_attempts=3
    while (( attempt <= max_attempts )); do
        log_info "Calling getUpdates ... (attempt $attempt/$max_attempts)"
        response=$(curl -fsS --max-time 10 \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/getUpdates" || echo "")

        if [[ -n "$response" ]]; then
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
                log_ok "Found chat_id: $chat_id"
                log_info "Sending test message..."
                local send_result
                send_result=$(curl -fsS --max-time 10 -X POST \
                    "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${chat_id}" \
                    -d "text=🔧 MentionMate setup test — if you can read this, your configuration is correct." || echo "")

                if [[ "$send_result" == *'"ok":true'* ]]; then
                    printf '\n%sDid you receive the test message?%s (y/N): ' "$C_BOLD" "$C_RESET"
                    read -r confirm
                    if [[ "${confirm,,}" =~ ^y(es)?$ ]]; then
                        TG_ALERT_CHAT_ID="$chat_id"
                        return 0
                    fi
                    log_warn "Test not received — chat_id may be wrong."
                else
                    log_warn "Send failed: $send_result"
                fi
            else
                log_warn "No /start message in recent updates. Did you /start the CORRECT bot?"
            fi
        else
            log_warn "API call failed."
        fi

        attempt=$((attempt + 1))
        if (( attempt <= max_attempts )); then
            printf '\nRetry? (Y/n): '
            read -r retry
            [[ "${retry,,}" =~ ^n(o)?$ ]] && break
            printf 'Send /start to the bot again, then press Enter...\n'
            read -r _
        fi
    done

    abort "Could not detect chat_id after $max_attempts attempts." \
        "See README.md → Troubleshooting → chat_id."
}

write_env() {
    log_step "Writing configuration to .env"
    local tmp="${ENV_FILE}.tmp"
    cat > "$tmp" <<EOF
# Generated by MentionMate wizard at $(date -u +%Y-%m-%dT%H:%M:%SZ)
TG_API_ID=${TG_API_ID}
TG_API_HASH=${TG_API_HASH}
TG_MY_USERNAME=${TG_MY_USERNAME}
TG_BOT_TOKEN=${TG_BOT_TOKEN}
TG_ALERT_CHAT_ID=${TG_ALERT_CHAT_ID}
EOF
    chmod 600 "$tmp"
    mv "$tmp" "$ENV_FILE"
    log_ok "Wrote $ENV_FILE (permissions 600)."
}

telethon_auth() {
    log_step "Telethon userbot login"
    mkdir -p "$DATA_DIR"
    chmod 777 "$DATA_DIR" 2>/dev/null || true

    if [[ -f "$SESSION_FILE" ]]; then
        log_info "Session file already exists — skipping interactive auth."
        return 0
    fi

    log_info "An interactive container will run — enter phone (e.g. +84912345678) at the prompt."
    log_info "If 2FA is enabled, you'll be asked for the password after the OTP."
    printf '\n'

    local attempt=1 max_attempts=3
    while (( attempt <= max_attempts )); do
        if run_cmd docker run --rm -it \
            -v "$(pwd)/${DATA_DIR}:/app/data" \
            --env-file "$ENV_FILE" \
            "$IMAGE" \
            python -m mention_mate.auth; then
            log_ok "Telethon session created: $SESSION_FILE"
            chmod 600 "$SESSION_FILE" 2>/dev/null || true
            return 0
        fi
        log_warn "Auth failed. Retry? ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        (( attempt <= max_attempts )) && sleep 2
    done

    abort "ERR-DIST-003: Telethon auth failed after $max_attempts attempts." \
        "See README.md → Troubleshooting → Telethon auth."
}

start_container() {
    log_step "Starting MentionMate container"
    if ! run_cmd $COMPOSE_CMD up -d; then
        log_err "ERR-DIST-004: Container did not start."
        $COMPOSE_CMD logs --tail 50
        abort "See README.md → Troubleshooting → Container."
    fi
    sleep 3
    if ! $COMPOSE_CMD ps --status running | grep -q mention-mate; then
        log_err "Container started but is not running. Logs:"
        $COMPOSE_CMD logs --tail 50
        abort "See README.md → Troubleshooting → Container."
    fi
    log_ok "Container 'mention-mate' is running."
}

print_setup_summary() {
    log_step "Done! 🎉"
    cat <<EOF

${C_GREEN}${C_BOLD}MentionMate has been installed successfully.${C_RESET}

📝 Useful commands:
  Tail logs:      ${C_BOLD}${COMPOSE_CMD} logs -f bot${C_RESET}
  Stop:           ${C_BOLD}${COMPOSE_CMD} down${C_RESET}
  Restart:        ${C_BOLD}${COMPOSE_CMD} restart${C_RESET}
  Update:         ${C_BOLD}./mention-mate.sh update${C_RESET}

📖 Documentation:  https://github.com/PhamHoang16/mention-mate
🐛 Report issues:  https://github.com/PhamHoang16/mention-mate/issues

You will receive an alert on Telegram whenever someone @${TG_MY_USERNAME:-username} mentions you in any group the userbot is a member of.
EOF
}

run_setup() {
    printf '%s\n' "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf '   MentionMate Setup Wizard (Linux/macOS)\n'
    printf '   github.com/PhamHoang16/mention-mate\n'
    printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$C_RESET"

    check_docker
    detect_compose
    check_existing
    prompt_inputs
    pull_image
    discover_chat_id
    write_env
    telethon_auth
    start_container
    print_setup_summary
}

# ================================================================
# UPDATE
# ================================================================

run_update() {
    printf '%s━━━ MentionMate Update ━━━%s\n\n' "$C_BOLD" "$C_RESET"
    check_docker
    detect_compose

    local current_digest
    current_digest=$(docker inspect mention-mate --format '{{.Image}}' 2>/dev/null || echo "")
    if [[ -n "$current_digest" ]]; then
        local current_tag
        current_tag=$(docker images --no-trunc --format '{{.Repository}}:{{.Tag}}@{{.ID}}' \
            | grep "^${IMAGE_REPO}:" | grep "${current_digest}" | head -1 | awk -F'@' '{print $1}' || echo "unknown")
        printf '📍 Current version: %s%s%s\n' "$C_BOLD" "$current_tag" "$C_RESET"
    else
        log_warn "No running container detected (may never have been started)."
    fi

    if [[ -f "$SESSION_FILE" ]] && find "$SESSION_FILE" -mtime +7 -print -quit 2>/dev/null | grep -q .; then
        log_warn "Session file mtime > 7 days — backup recommended."
        printf 'Back up session now? (Y/n) [Y]: '
        read -r ans
        if [[ ! "${ans,,}" =~ ^n(o)?$ ]]; then
            local backup="${SESSION_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
            cp "$SESSION_FILE" "$backup"
            log_ok "Backup: $backup"
        fi
    fi

    printf '\n⬇️  Pulling new image...\n'
    if ! run_cmd $COMPOSE_CMD pull; then
        abort "ERR-DIST-002: Pull failed. Check network access to ghcr.io."
    fi

    local new_digest
    new_digest=$($COMPOSE_CMD images --format json bot 2>/dev/null \
        | grep -oE '"ID":"[^"]+"' | head -1 | cut -d'"' -f4 || echo "")
    if [[ -n "$current_digest" && -n "$new_digest" && "$current_digest" == *"$new_digest"* ]]; then
        log_ok "Already on the latest version — no update needed."
        return 0
    fi

    printf '\n🔄 Recreating container with new image...\n'
    if ! run_cmd $COMPOSE_CMD up -d; then
        abort "ERR-DIST-006: Container failed to restart." \
            "See README.md → Troubleshooting → Update."
    fi
    sleep 3

    local new_tag
    new_tag=$(docker inspect mention-mate --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")
    log_ok "Update complete. Image: $new_tag"
    printf '\n📝 Tail logs: %s%s logs -f bot%s\n' "$C_BOLD" "$COMPOSE_CMD" "$C_RESET"
}

# ================================================================
# Dispatch
# ================================================================

if [[ -z "$SUBCOMMAND" ]]; then
    if [[ -f "$ENV_FILE" && -f "$SESSION_FILE" ]]; then
        log_info "Existing installation detected — running 'update'. (Use './mention-mate.sh setup' to reconfigure.)"
        SUBCOMMAND="update"
    else
        SUBCOMMAND="setup"
    fi
fi

case "$SUBCOMMAND" in
    setup)  run_setup ;;
    update) run_update ;;
    *)      abort "Unknown subcommand: $SUBCOMMAND" ;;
esac
