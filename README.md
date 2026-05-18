# MentionMate

> Never miss when your team @mentions you on Telegram.

![Version](https://img.shields.io/badge/version-0.1.0--dev-blue)
![Docker](https://img.shields.io/badge/docker-multi--arch-2496ED)
![License](https://img.shields.io/badge/license-MIT-green)

**MentionMate** is a lightweight daemon that runs on your machine, listens to your Telegram groups, and sends a **dedicated push notification** every time someone @mentions you — even if the group itself is muted.

Built for DevOps engineers and product managers who get pulled into dozens of project groups, but useful for anyone who relies on Telegram for work.

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

## Quick install

**Prerequisites:**
- A running Docker runtime (Docker Engine / Desktop / Colima / Podman)
- Internet access to `api.telegram.org` and `ghcr.io`
- A personal Telegram account
- 5–15 minutes

### 1. Prepare Telegram credentials

Before running the wizard, gather three things:

1. **API_ID and API_HASH:** go to https://my.telegram.org/apps → sign in with your phone number → click *"API development tools"* → *"Create new application"*. Copy both values.
2. **Bot Token:** chat with [@BotFather](https://t.me/BotFather) → send `/newbot` → choose a name and username → BotFather returns a token like `1234567890:AAAA...`.
3. **Your username:** your Telegram username (without the `@`).

### 2. Download the release and run the wizard

Download `mention-mate-v0.x.y.zip` from the [Releases page](https://github.com/hoangp47/mention-mate/releases), unzip it, open a terminal in the extracted folder, and run:

**Linux / macOS:**
```bash
./setup.sh
```

**Windows (PowerShell):**
```powershell
.\setup.ps1
```

> If PowerShell blocks the script: `powershell -ExecutionPolicy Bypass -File setup.ps1`

The wizard automatically:
1. Verifies Docker is running
2. Prompts for the 4 Telegram values (with real-time validation)
3. Pulls the multi-arch image from ghcr.io
4. Discovers your alert `chat_id` by asking you to `/start` the bot
5. Sends a test message to confirm the right chat
6. Walks you through Telethon userbot login (phone + OTP + 2FA if enabled)
7. Starts the container and prints a summary

Total time: **~10–15 minutes** for technical users, **~20–30 minutes** the first time if you're new to the Telegram API.

### 3. Verify

After the wizard completes, ask someone (or a second account) to `@your_username` in any group you're a member of. Within seconds, the bot you just configured will DM you the alert.

---

## Common commands

```bash
# Tail live logs
docker compose logs -f bot

# Stop
docker compose down

# Restart
docker compose restart

# Upgrade to the latest version
./update.sh     # or .\update.ps1 on Windows
```

---

## Documentation

- 📖 **[SETUP.md](docs/SETUP.md)** — Step-by-step install guide with screenshots
- 🔧 **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — Common issues and fixes
- 📝 **[CHANGELOG.md](CHANGELOG.md)** — Version history
- 🏗️ **[Architecture](.vsaf/docs/srs/SRS-tele-FR-DIST-distribution-v1.0.md)** — Technical design

---

## Security notice

⚠️ **MentionMate uses your personal Telegram account** through a Telethon userbot to read group messages. That means:

- The tool has access to **all** of your Telegram messages, including private chats.
- It only inspects messages to detect mentions; it **does not store** message content outside your machine.
- The session file (`data/mentions_session.session`) is **equivalent to a credential** — never share it or back it up to cloud services.
- When you leave your job or switch machines: **revoke** the session via Telegram → Settings → Devices.
- You are responsible for complying with Telegram's ToS and your organization's data-handling policies.

If your employer has strict data-handling policies, check with your information-security team before installing.

---

## Architecture at a glance

```
Telegram group ──► Telethon userbot (reads messages)
                        │
                        │ detects @mention
                        ▼
                  Telegram Bot HTTP API (sends alert)
                        │
                        ▼
                  Push notification → you
```

**Why two clients?** A userbot cannot send a message to itself in a way that triggers a push notification (Telegram silently delivers self-messages). A bot, on the other hand, can DM a user (once the user has `/start`ed the bot). So: userbot reads, bot sends.

---

## Roadmap

| Phase | Goal | Status |
|---|---|---|
| **Phase 0** | Security hotfix (revoke leaked token, purge git history) | 🔴 Required before public release |
| **Phase 1** | Hardening (structured logging, health endpoint, retries, tests) | ⏭️ Planned |
| **Phase 2** | Productization (this release) — distribution, wizard, docs | 🟡 In progress |
| **Phase 3** | Feature expansion (multi-keyword, digest, action buttons, web UI) | ⏭️ Planned |

Full roadmap: see the [internal roadmap document](.vsaf/docs/planning-artifacts/prd-distribution.md).

---

## Contribute / report issues

- 🐛 Bug or feature request: [GitHub Issues](https://github.com/hoangp47/mention-mate/issues)
- 💬 Discussion: TBD

---

## License

MIT — see [LICENSE](LICENSE).

---

*Made by [@hoangp47](https://github.com/hoangp47) for Viettel internal use. Open-sourced as part of Sáng kiến 2026.*
