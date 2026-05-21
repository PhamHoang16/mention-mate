# MentionMate

> Never miss when your team @mentions you on Telegram.

![Version](https://img.shields.io/badge/version-0.1.0--dev-blue)
![Docker](https://img.shields.io/badge/docker-multi--arch-2496ED)
![License](https://img.shields.io/badge/license-MIT-green)

**MentionMate** is a lightweight daemon that listens to your Telegram groups and sends a **dedicated push notification** every time someone @mentions you — even if the group itself is muted.

Built for DevOps engineers and product managers pulled into dozens of project groups, but useful for anyone who relies on Telegram for work.

> _Demo screenshot / GIF will be added after pilot._

---

## Why MentionMate?

| Problem | How MentionMate helps |
|---|---|
| Added to 10+ project groups; mute everything to focus | Still get notified when someone calls your name |
| Miss mentions in noisy groups | Tool quotes the message and includes a jump link |
| Need to track multiple keywords (project names, team names) | _Multi-keyword support coming in Phase 2_ |
| Don't want yet another mobile app | Runs in the background; alerts arrive through Telegram itself |

---

## How it works

MentionMate is a small **Docker container that runs on your own machine**. Inside it, two Telegram clients work together:

1. A **userbot** signs in with your personal Telegram account and watches your groups for messages that @mention you.
2. A **bot** (the @BotFather kind) takes those matches and DMs them to you — which triggers Telegram's regular push notification, even when the original group is muted.

No cloud server, no database, no daemon outside that one container. The image is published on GitHub Container Registry; `docker compose` pulls it and brings it up locally.

**Why two clients?** A userbot can't message itself in a way that triggers a push (Telegram silently delivers self-messages). A bot, on the other hand, can DM you once you've `/start`ed it. So: userbot reads, bot sends.

---

## What you need

About **10–15 minutes** and:

| Requirement | Where to get it |
|---|---|
| 🐳 **Docker runtime** | Docker Engine, Docker Desktop, Colima, or Podman — any modern setup works |
| 🌐 **Internet access** | Outbound to `api.telegram.org` (always) and `ghcr.io` (one-time image pull) |
| 📱 **Telegram account** | The personal account whose mentions you want to catch |
| 🔑 **API_ID + API_HASH** | https://my.telegram.org/apps → *"Create new application"* |
| 🤖 **Bot token** | Chat [@BotFather](https://t.me/BotFather) → `/newbot` → name it → copy the token |
| 👤 **Your username** | Telegram → Settings (without the `@`) |

> ⚠️ **Corporate networks** that block `api.telegram.org` (e.g. some intranets) won't work. Use personal Wi-Fi, a 4G hotspot, or a home machine.

---

## Install

### 1. Install a Docker runtime (skip if you already have one)

- **Linux** — `curl -fsSL https://get.docker.com | sudo sh` then `sudo usermod -aG docker $USER` and log out/in.
- **macOS** — `brew install colima docker && colima start`. (Avoid Docker Desktop at companies with 250+ employees — paid license required.)
- **Windows** — WSL2 + Docker Engine, or Podman Desktop. Run wizards from the WSL/PowerShell terminal, not VS Code's integrated terminal.

Verify: `docker info` exits cleanly.

### 2. Get your Telegram credentials

**API_ID / API_HASH** — open https://my.telegram.org/apps, sign in, click *"API development tools"*, fill any title/short name (Platform = Desktop), click *"Create application"*, copy the two values.

**Bot token** — DM [@BotFather](https://t.me/BotFather) → `/newbot` → pick a display name → pick a username ending in `bot` → copy the token he returns (`1234567890:AAAA...`).

**Username** — Telegram → Settings → Username (no `@`). Set one if you don't have it yet.

Keep all three private — anyone with them can impersonate your account or bot.

### 3. Get the release

**Browser:** download `mention-mate-v0.x.y.zip` from [Releases](https://github.com/PhamHoang16/mention-mate/releases) and unzip.

**CLI** (headless / SSH):
```bash
TAG=v0.1.0
curl -L -o mention-mate.zip \
    "https://github.com/PhamHoang16/mention-mate/releases/download/$TAG/mention-mate-$TAG.zip"
unzip mention-mate.zip && cd "mention-mate-$TAG"
```

Or `git clone` if you prefer source (wizards live in `scripts/` instead of root):
```bash
git clone https://github.com/PhamHoang16/mention-mate.git
cd mention-mate
```

### 4. Run the wizard

A single script handles both first-time setup and later updates — call it with no argument and it picks the right mode for you, or pass `setup` / `update` explicitly.

```bash
# Linux / macOS
./mention-mate.sh                  # auto: setup the first time, update afterwards
./mention-mate.sh setup            # explicit setup
./mention-mate.sh update           # explicit update
# (or scripts/mention-mate.sh if you cloned the repo)

# Windows PowerShell
.\mention-mate.ps1
.\mention-mate.ps1 setup
.\mention-mate.ps1 update
```

> If PowerShell blocks the script: `powershell -ExecutionPolicy Bypass -File mention-mate.ps1`

The wizard verifies Docker, prompts for the four values above (with validation, hidden input for secrets), pulls the image, asks you to `/start` your bot in Telegram so it can discover the chat ID, sends a test message, walks you through Telethon login (phone + OTP + 2FA if enabled), and starts the container. ~5–15 minutes end-to-end.

### 5. Verify

From any group you're in, have someone @mention you (or use a second account). Within seconds, the bot DMs you the alert.

---

## Common commands

```bash
docker compose logs -f bot          # tail live logs
docker compose down                 # stop
docker compose restart              # restart
./mention-mate.sh update            # upgrade (.\mention-mate.ps1 update on Windows)
```

**Auto-start on boot** — the container is `restart: unless-stopped`, so just ensure the Docker daemon starts on boot: `sudo systemctl enable docker` (Linux), `brew services start colima` (macOS), or the *"Start at login"* option in Docker/Podman Desktop (Windows).

**Back up the session** — `data/mentions_session.session` is your "logged-in" token. Copy it somewhere safe; the update wizard reminds you if it's older than 7 days.

---

## Troubleshooting

### Docker daemon not running (`ERR-DIST-001`)
Start it: `sudo systemctl start docker` (Linux) · `colima start` (macOS) · open Docker/Podman Desktop and wait for the green indicator (macOS/Windows) · `sudo service docker start` (WSL2).

### Image pull failed (`ERR-DIST-002`)
Test `curl -I https://ghcr.io` and `curl -I https://api.telegram.org`. If either fails, you're likely behind a firewall that blocks them — switch to personal Wi-Fi or a 4G hotspot. For a corporate proxy: `export HTTPS_PROXY=http://proxy.example.com:8080` and configure it in Docker settings too.

### Telethon auth failed after 3 attempts (`ERR-DIST-003`)
Most common causes: wrong OTP (Telegram delivers it inside the official "Telegram" chat on your phone, not as SMS), wrong 2FA password, or wrong phone-number format — must be `+CountryCode...` with no spaces. After 3 fails, re-run `./mention-mate.sh setup`. If it still fails, delete `data/mentions_session.session*` and try again.

### `Could not detect chat_id after 3 attempts`
You sent `/start` to the wrong bot, or to the right bot before the wizard was listening. Send `/start` again to the bot username the wizard prints, then press Enter. Manual check:
```bash
curl -s "https://api.telegram.org/botYOUR_TOKEN/getUpdates"
# Look for "chat":{"id":XXX, ...}
```

### Container failed to start (`ERR-DIST-004`) or restart-loops
```bash
docker compose logs --tail 100 bot
```
Look for: `AuthKeyDuplicatedError` (session being used on two machines — delete `data/mentions_session.session` and re-run setup); `ConnectionError` (network — see image-pull section); `KeyError: 'TG_API_ID'` (`.env` not loaded — verify it exists and is readable).

### Container is running but no alerts arrive
1. `docker compose ps` → status `Up`.
2. `docker compose logs bot | grep Running` → should show *"✅ Running: userbot listening..."*.
3. `.env` → `TG_MY_USERNAME` matches your Telegram username **exactly**, no `@`.
4. You are a member of the group where the mention happens — the userbot only sees groups you've joined.
5. The `@username` must be the autocomplete kind (tap the suggestion), not just typed text.
6. From a second account, send `@your_username` in a group and watch `docker compose logs -f bot`.

### Windows: PowerShell blocks the script (`ERR-DIST-005`)
```powershell
powershell -ExecutionPolicy Bypass -File mention-mate.ps1
# Or persistently:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
If Group Policy blocks even `Bypass`, contact IT.

### Windows: wizard hangs during Telethon auth
VS Code's integrated terminal doesn't provide a TTY, which `docker run --rm -it` needs. Use a standalone Windows Terminal or PowerShell window.

### macOS Apple Silicon: image runs slowly
Verify it pulled the arm64 variant:
```bash
docker inspect mention-mate --format '{{.Architecture}}'   # should be arm64
docker pull --platform linux/arm64 ghcr.io/phamhoang16/mention-mate:latest
docker compose up -d --force-recreate
```

### Update didn't pick up the new image (`ERR-DIST-006`)
```bash
docker compose down && docker compose pull && docker compose up -d --force-recreate
```

### Full reset (last resort)
```bash
docker compose down
rm -rf data .env
./mention-mate.sh setup
```
> ⚠️ Removing `data/` destroys the Telethon session — you'll re-authenticate on the next run.

### Verbose wizard
```bash
./mention-mate.sh -v     # prints every Docker command as it runs
```

Still stuck? Open a [GitHub issue](https://github.com/PhamHoang16/mention-mate/issues/new) with your OS + version, `docker version`, the wizard step that failed, and `docker compose logs --tail 100 bot` (redact tokens).

---

## Privacy & security

MentionMate runs **entirely on your own machine** — no cloud, no third-party service, no telemetry. Your messages stay where they already are: with you and Telegram.

- **What the tool sees.** The userbot signs in with your Telegram account, exactly like Telegram Desktop does, and reads messages to spot when someone @mentions you. Nothing is stored, profiled, or sent anywhere else.
- **No data leaves your machine.** The only outbound connections are to Telegram's API (read messages, deliver alert) and to GitHub's container registry (one-time image pull).
- **The session file is your "logged-in" token.** `data/mentions_session.session` keeps you signed in across restarts. Treat it like a password — don't email it, sync it to cloud drives, or share screenshots of it.
- **Easy off-switch.** Telegram → Settings → Devices → revoke the session in one tap.
- **Fully open source.** MIT-licensed. Audit it, fork it, customize it.

---

## Roadmap

| Phase | Goal | Status |
|---|---|---|
| **Phase 1** | Hardening (structured logging, health endpoint, retries, tests) | ⏭️ Planned |
| **Phase 2** | Productization (this release) — distribution, wizard, docs | ✅ Released as v0.1.0 |
| **Phase 3** | Feature expansion (multi-keyword, digest, action buttons, web UI) | ⏭️ Planned |

---

## Contribute / report issues

- 🐛 Bug or feature request: [GitHub Issues](https://github.com/PhamHoang16/mention-mate/issues)
- 📝 Version history: [CHANGELOG.md](CHANGELOG.md)

---

## License

MIT — see [LICENSE](LICENSE).

---

*Made by [@hoangp47](https://github.com/hoangp47) for Viettel internal use. Open-sourced as part of Sáng kiến 2026.*
