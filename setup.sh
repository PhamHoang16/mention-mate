#!/usr/bin/env bash
# MentionMate — Setup wizard for Linux/macOS
# Docs: https://github.com/hoangp47/mentionmate
#
# Usage: ./setup.sh
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

Usage:
  ./setup.sh           Run the interactive wizard
  ./setup.sh -v        Run verbose (print every docker command)
  ./setup.sh -h        Show this help

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
    log_step "1/12 Checking Docker"
    if ! command -v docker &>/dev/null; then
        abort "ERR-DIST-001: 'docker' command not found." \
            "Please install Docker Engine / Colima / Podman first:
  Linux:   https://docs.docker.com/engine/install/
  macOS:   brew install colima docker (recommended, free) or Docker Desktop
  Or Podman: https://podman.io/docs/installation"
    fi

    if ! docker info &>/dev/null; then
        abort "ERR-DIST-001: Docker daemon is not running." \
            "Start Docker and retry:
  Linux:   sudo systemctl start docker  (if using systemd)
  macOS:   colima start  (or open Docker Desktop)"
    fi
    log_ok "Docker daemon is running."
}

# ----- Step 2: Check compose v2 (FR-012) -----
COMPOSE_CMD="docker compose"
check_compose() {
    log_step "2/12 Checking docker compose"
    if docker compose version &>/dev/null; then
        log_ok "docker compose v2 available."
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        log_warn "Only docker-compose v1 (legacy) is available. The wizard will fall back, but upgrading is recommended."
        COMPOSE_CMD="docker-compose"
    else
        abort "Neither 'docker compose' nor 'docker-compose' found." \
            "Most modern Docker Desktop/Engine versions bundle Compose. Reinstall Docker."
    fi
}

# ----- Step 3: Detect existing install (BR-DIST-00-03 idempotency) -----
check_existing() {
    log_step "3/12 Checking for existing configuration"
    local existing=0
    [[ -f "$ENV_FILE" ]] && { log_warn ".env already exists."; existing=1; }
    [[ -f "$SESSION_FILE" ]] && { log_warn "Session file already exists: $SESSION_FILE"; existing=1; }

    if (( existing )); then
        printf '\nOverwrite existing config? (y/N) [N]: '
        read -r answer
        case "${answer,,}" in
            y|yes) log_warn "Will overwrite .env. (Session file is preserved — Telethon will be re-prompted only if needed.)" ;;
            *)    abort "Cancelled. Existing configuration kept." ;;
        esac
    else
        log_ok "No prior configuration found — proceeding."
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
            log_err "Value cannot be empty."
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
    log_step "4/12 Telegram credentials"

    prompt_with_validation TG_API_ID \
        "🔑 Enter TG_API_ID (integer, from https://my.telegram.org/apps):" \
        '^[0-9]+$' \
        "TG_API_ID must be a positive integer." 0

    prompt_with_validation TG_API_HASH \
        "🔑 Enter TG_API_HASH (32 hex characters, input hidden):" \
        '^[a-f0-9]{32}$' \
        "TG_API_HASH must be exactly 32 hex characters (a-f, 0-9)." 1

    prompt_with_validation TG_MY_USERNAME \
        "👤 Enter your Telegram username (without @, e.g. hoangp47):" \
        '^[A-Za-z][A-Za-z0-9_]{4,31}$' \
        "Username must be 5-32 chars, start with a letter, contain only letters/digits/underscore." 0

    prompt_with_validation TG_BOT_TOKEN \
        "🤖 Enter TG_BOT_TOKEN from @BotFather (input hidden, format <id>:<secret>):" \
        '^[0-9]+:[A-Za-z0-9_-]{30,40}$' \
        "Invalid bot token format. Expected: 1234567890:AAAA...." 1
}

# ----- Step 8: Pull image (FR-007) -----
pull_image() {
    log_step "5/12 Pulling Docker image"
    log_info "Pulling $IMAGE ... (first pull may take 1-2 minutes)"
    if ! run_cmd docker pull "$IMAGE"; then
        abort "ERR-DIST-002: Image pull failed." \
            "Possible causes: (1) network can't reach ghcr.io, (2) firewall is blocking it.
See TROUBLESHOOTING.md §Network. Test: curl -I https://ghcr.io"
    fi
    log_ok "Image pulled successfully."
}

# ----- Step 9: Discover chat_id + send test (FR-015, FR-016, BR-DIST-05-01) -----
discover_chat_id() {
    log_step "6/12 Discovering chat_id (sub-flow UC-DIST-05)"
    local bot_username=""
    # Fetch bot username from getMe to help user find the right bot
    bot_username=$(curl -fsS --max-time 10 \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/getMe" 2>/dev/null \
        | grep -oE '"username":"[^"]+"' | head -1 | cut -d'"' -f4 || echo "")

    if [[ -n "$bot_username" ]]; then
        printf '\n%s1. Open Telegram, find @%s (or link https://t.me/%s)\n' \
            "$C_BOLD" "$bot_username" "$bot_username"
        printf '2. Tap START or send /start to the bot\n'
        printf '3. Come back here and press Enter\n%s' "$C_RESET"
    else
        log_warn "Could not fetch bot username (token may be wrong). Try /start with the bot you just created."
        printf '\nSend /start to the bot in Telegram, then press Enter...\n'
    fi
    read -r _

    local response chat_id
    local attempt=1 max_attempts=3
    while (( attempt <= max_attempts )); do
        log_info "Calling getUpdates ... (attempt $attempt/$max_attempts)"
        response=$(curl -fsS --max-time 10 \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/getUpdates" || echo "")

        if [[ -z "$response" ]]; then
            log_warn "API call failed. Retry?"
        else
            # Find chat.id from a message whose text starts with /start
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

                # Round-trip verify (BR-DIST-05-01)
                log_info "Sending test message..."
                local send_result
                send_result=$(curl -fsS --max-time 10 -X POST \
                    "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${chat_id}" \
                    -d "text=🔧 MentionMate setup test — if you can read this, your configuration is correct." || echo "")

                if [[ "$send_result" == *'"ok":true'* ]]; then
                    printf '\n%sDid you receive the test message on Telegram?%s (y/N): ' \
                        "$C_BOLD" "$C_RESET"
                    read -r confirm
                    if [[ "${confirm,,}" =~ ^y(es)?$ ]]; then
                        TG_ALERT_CHAT_ID="$chat_id"
                        return 0
                    else
                        log_warn "User didn't receive the test — chat_id may be wrong. Retrying."
                    fi
                else
                    log_warn "Send failed: $send_result"
                fi
            else
                log_warn "No /start message in recent updates. Did you /start the CORRECT bot you just created?"
            fi
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
        "See TROUBLESHOOTING.md §chat_id for manual debugging."
}

# ----- Step 10: Write .env mode 600 (FR-018, BR-DIST-01-03) -----
write_env() {
    log_step "7/12 Writing configuration to .env"
    # Write via temp file then rename = atomic write (NFR-REL-02)
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
    log_ok "Wrote $ENV_FILE (permissions 600)."
}

# ----- Step 11: Telethon auth interactive (FR-017) -----
telethon_auth() {
    log_step "8/12 Telethon userbot login (phone + OTP + 2FA if enabled)"
    mkdir -p "$DATA_DIR"

    if [[ -f "$SESSION_FILE" ]]; then
        log_info "Session file already exists — skipping interactive auth."
        return 0
    fi

    log_info "An interactive container will run — enter your phone number (e.g. +84912345678) when prompted."
    log_info "If your account has 2FA, you'll be asked for the password after the OTP."
    printf '\n'

    local attempt=1 max_attempts=3
    while (( attempt <= max_attempts )); do
        if run_cmd docker run --rm -it \
            -v "$(pwd)/${DATA_DIR}:/app/data" \
            --env-file "$ENV_FILE" \
            "$IMAGE" \
            python /app/scripts/auth.py; then
            log_ok "Telethon session created: $SESSION_FILE"
            chmod 600 "$SESSION_FILE" 2>/dev/null || true
            return 0
        fi
        log_warn "Auth failed. Retry? ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        (( attempt <= max_attempts )) && sleep 2
    done

    abort "ERR-DIST-003: Telethon auth failed after $max_attempts attempts." \
        "Possible causes: wrong OTP, wrong 2FA, or Telegram temporarily locked your account. See TROUBLESHOOTING.md §Auth."
}

# ----- Step 12: Start container (FR-019) -----
start_container() {
    log_step "9/12 Starting MentionMate container"
    if ! run_cmd $COMPOSE_CMD up -d; then
        log_err "ERR-DIST-004: Container did not start."
        printf '\nLogs:\n'
        $COMPOSE_CMD logs --tail 50
        abort "See TROUBLESHOOTING.md §Container."
    fi

    sleep 3
    if ! $COMPOSE_CMD ps --status running | grep -q mentionmate; then
        log_err "Container started but is not in 'running' state. Logs:"
        $COMPOSE_CMD logs --tail 50
        abort "See TROUBLESHOOTING.md §Container."
    fi
    log_ok "Container 'mentionmate' is running."
}

# ----- Step 13: Summary (FR-020) -----
print_summary() {
    log_step "10/12 Done! 🎉"
    cat <<EOF

${C_GREEN}${C_BOLD}MentionMate has been installed successfully.${C_RESET}

📝 Useful commands:
  Tail logs:      ${C_BOLD}${COMPOSE_CMD} logs -f bot${C_RESET}
  Stop:           ${C_BOLD}${COMPOSE_CMD} down${C_RESET}
  Restart:        ${C_BOLD}${COMPOSE_CMD} restart${C_RESET}
  Update:         ${C_BOLD}./update.sh${C_RESET}

📖 Documentation:  https://github.com/hoangp47/mentionmate
🐛 Report issues:  https://github.com/hoangp47/mentionmate/issues

You will receive an alert on Telegram whenever someone @${TG_MY_USERNAME:-username} mentions you in any group the userbot is a member of.
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
