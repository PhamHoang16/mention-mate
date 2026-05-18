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

## How it works

MentionMate is a small **Docker container that runs on your own machine**. Inside it, two Telegram clients work together:

1. A **userbot** signs in with your personal Telegram account and watches your groups for messages that @mention you.
2. A **bot** (the @BotFather kind) takes those matches and DMs them to you — which triggers Telegram's regular push notification, even when the original group is muted.

That's the whole machinery. No cloud server, no database, no daemon outside that one container. The image is published on GitHub Container Registry; `docker compose` pulls it and brings it up locally.

**Why two clients?** A userbot can't message itself in a way that triggers a push (Telegram silently delivers self-messages). A bot, on the other hand, can DM you once you've `/start`ed it. So: userbot reads, bot sends.

---

## What you need

About **10–15 minutes** and the following:

| Requirement | Where to get it | Effort |
|---|---|---|
| 🐳 **Docker runtime** | Docker Engine, Docker Desktop, Colima, or Podman — any modern setup works | ~10 min if not installed |
| 🌐 **Internet access** | Outbound to `api.telegram.org` (always) and `ghcr.io` (one-time image pull) | — |
| 📱 **Telegram account** | The personal account whose mentions you want to catch | already have |
| 🔑 **API credentials** | https://my.telegram.org/apps → *"Create new application"* → copy `API_ID` + `API_HASH` | ~2 min |
| 🤖 **Bot token** | Chat [@BotFather](https://t.me/BotFather) → `/newbot` → name it → copy the token | ~1 min |
| 👤 **Your username** | Telegram → Settings (without the `@`) | — |

The wizard prompts for each value one at a time — no need to memorize anything, just have them ready to paste.

For a click-by-click walkthrough with screenshots, see [docs/SETUP.md](docs/SETUP.md).

---

## Install

### 1. Download the release
Grab `mention-mate-v0.x.y.zip` from the [Releases page](https://github.com/PhamHoang16/mention-mate/releases) and unzip it anywhere.

### 2. Run the wizard
Open a terminal in the extracted folder.

**Linux / macOS:**
```bash
./setup.sh
```

**Windows (PowerShell):**
```powershell
.\setup.ps1
```

> If PowerShell blocks the script: `powershell -ExecutionPolicy Bypass -File setup.ps1`

The wizard verifies Docker, prompts for the inputs above (with real-time validation), pulls the image, discovers your alert chat, sends a test message, walks you through Telethon login (phone + OTP + 2FA), and starts the container. Around **5–15 minutes** end-to-end.

### 3. Verify it works
From any group you're in, have someone @mention you (or use a second account). Within seconds, the bot DMs you the alert.

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

---

## Privacy & security

MentionMate runs **entirely on your own machine** — no cloud, no third-party service, no telemetry. Your messages stay where they already are: with you and Telegram.

A few things worth knowing, in plain English:

- **What the tool sees.** The userbot signs in with your Telegram account, exactly like Telegram Desktop does, and reads messages so it can spot when someone @mentions you. That's it — nothing is stored, profiled, or sent anywhere else.
- **No data leaves your machine.** The only outbound connections are to Telegram's own API (to read messages and deliver the alert) and to GitHub's container registry (one-time, to download the image). No analytics, no telemetry, no opaque cloud.
- **The session file is your "logged-in" token.** `data/mentions_session.session` keeps you signed in across restarts. Treat it like a password: don't email it, don't sync it to cloud drives, don't share screenshots of it.
- **Easy off-switch.** When you switch laptops, change jobs, or just want to stop: open Telegram → Settings → Devices and revoke the session in one tap. Same as logging out of Telegram Web.
- **Fully open source.** Every line of code is in this repo, MIT-licensed. Audit it, fork it, customize it.

If your employer has formal data-handling policies around messaging tools, it's worth a quick check with them — but for most people this is no different from running Telegram Desktop with an extra notification helper on top.

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
- 💬 Discussion: TBD

---

## License

MIT — see [LICENSE](LICENSE).

---

*Made by [@hoangp47](https://github.com/hoangp47) for Viettel internal use. Open-sourced as part of Sáng kiến 2026.*
