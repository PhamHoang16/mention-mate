# Setup Guide — MentionMate

Step-by-step install instructions with screenshot placeholders (to be added after pilot).

> ⏱️ **Estimated time:** 10–15 minutes (technical user) / 20–30 minutes (first-time user).

---

## Requirements

| Item | Requirement |
|---|---|
| **OS** | Linux (Ubuntu 22.04+, Debian 12+, Fedora 38+), macOS 13+, Windows 10/11 |
| **Docker runtime** | Docker Engine 20.10+ / Docker Desktop 4.x / Colima 0.5+ / Podman 4+ |
| **Disk** | ~500 MB free (image + session + logs) |
| **Network** | Outbound access to `api.telegram.org` and `ghcr.io` (personal Wi-Fi, mobile hotspot, or a corporate network that permits it) |
| **Account** | A personal Telegram account (phone-verified) |

> ⚠️ **Corporate networks (e.g. Viettel intranet):** if `api.telegram.org` is blocked, the tool cannot run on that network. Use personal Wi-Fi, a 4G hotspot, or a home machine.

---

## Step 1 — Install a Docker runtime (skip if you already have one)

### Linux

Use **Docker Engine** (free, no Docker Desktop license required):

```bash
# Ubuntu / Debian
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Log out and back in for the group change to take effect.
```

Verify: `docker info` runs without error.

### macOS

Use **Colima** (free, lightweight, no commercial-use restrictions):

```bash
brew install colima docker
colima start
```

Alternatives: **Rancher Desktop** or **Podman Desktop** (both free with a GUI).

> ⚠️ **Avoid Docker Desktop** if your company has more than 250 employees — it requires a paid commercial license.

### Windows

Recommended: **WSL2 + Docker Engine** (free) or **Podman Desktop** (free GUI).

**Option A — WSL2 + Docker Engine**
1. In an elevated PowerShell: `wsl --install`
2. Restart your machine.
3. Inside the Ubuntu WSL shell: `curl -fsSL https://get.docker.com | sudo sh`
4. Run the wizard from the WSL terminal (not PowerShell).

**Option B — Podman Desktop**
1. Install from https://podman.io/docs/installation
2. Start the Podman machine from the GUI.
3. `setup.ps1` will detect it automatically.

> _Screenshot 1 placeholder: Docker Desktop / Colima / Podman running indicator._

---

## Step 2 — Get your Telegram credentials

### 2a. API_ID and API_HASH

1. Open https://my.telegram.org/apps
2. Sign in with your Telegram phone number — you'll receive a code in Telegram.
3. Click **"API development tools"**.
4. Fill the form:
   - App title: anything (e.g. `MentionMate-personal`)
   - Short name: anything (e.g. `mention-tool`)
   - Platform: Desktop
   - Description: optional
5. Click **"Create application"**.
6. Copy your **API_ID** (a number) and **API_HASH** (32 hex characters). Keep them private.

> _Screenshot 2 placeholder: my.telegram.org/apps showing API_ID and API_HASH._

### 2b. Bot Token

1. In Telegram, search for and open a chat with [@BotFather](https://t.me/BotFather).
2. Send `/newbot`.
3. BotFather asks for a display name — pick anything (e.g. "Hoang's Mention Alert").
4. BotFather asks for a username — it must end with `bot` (e.g. `hoangp47_mention_bot`).
5. BotFather replies with a **token** like `1234567890:AAAA-xxxx...`. Copy it immediately and keep it private.

> _Screenshot 3 placeholder: BotFather conversation showing the /newbot flow and token._

### 2c. Your Telegram username

Open Telegram → Settings → look up your username (without `@`). Example: `hoangp47`. If you don't have one yet, set it via Settings → Username.

---

## Step 3 — Download MentionMate

1. Go to https://github.com/PhamHoang16/mention-mate/releases
2. Find the latest release (e.g. `v0.1.0`).
3. Download `mention-mate-v0.1.0.zip` from the "Assets" section.
4. Unzip into any folder (e.g. `~/MentionMate` on Linux/macOS, `C:\MentionMate` on Windows).

> _Screenshot 4 placeholder: GitHub Releases page with zip asset highlighted._

---

## Step 4 — Run the setup wizard

### Linux / macOS

```bash
cd ~/MentionMate
./setup.sh
```

### Windows

Open PowerShell (admin not required):

```powershell
cd C:\MentionMate
.\setup.ps1
```

If PowerShell blocks the script:

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

Or set the policy for the current session:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

> _Screenshot 5 placeholder: wizard running in terminal at the first prompt._

---

## Step 5 — Walk through the wizard

The wizard prompts you step by step. **Read each prompt carefully** before typing.

### Steps 1–3: Automatic checks
The wizard verifies Docker, Compose v2, and any prior configuration. If a check fails, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### Steps 4–7: Enter the four values

- **TG_API_ID:** the integer from step 2a.
- **TG_API_HASH:** the 32 hex characters from step 2a (input is hidden — paste it in).
- **TG_MY_USERNAME:** your username from step 2c (no `@`).
- **TG_BOT_TOKEN:** the token from step 2b (input is hidden).

If the format is wrong, the wizard reports the error and re-prompts without advancing.

### Step 8: Pull the image
The wizard pulls `ghcr.io/phamhoang16/mention-mate:latest` — the first pull takes 1–2 minutes.

### Step 9: Discover chat_id

The wizard asks you to **open Telegram and send `/start` to the bot you just created**.

> ⚠️ Send it to the bot **you** created in step 2b — not any other bot. The wizard prints the bot username so you can find it.

After you send `/start`, press Enter in the terminal. The wizard calls `getUpdates`, finds your chat_id, sends a test message — **"🔧 MentionMate setup test"** — and asks whether you received it.

- If yes → type `y` to confirm.
- If no → the wizard retries up to 3 times.

> _Screenshot 6 placeholder: setup test message received on Telegram._

### Step 10: Write `.env`
The wizard writes `.env` with permission 600 on Linux/macOS or an owner-only ACL on Windows. This file holds your secrets — never share it.

### Step 11: Log in to the Telethon userbot

The wizard runs an interactive container. You'll be asked for:

1. **Phone number** including country code, e.g. `+84912345678`
2. **One-time code** — Telegram sends a 5-digit code to the official "Telegram" chat in your app.
3. **2FA password** (only if you have two-step verification enabled).

If you fail 3 times in a row, the wizard exits. Re-run `./setup.sh` to try again.

> _Screenshot 7 placeholder: Telethon login prompts in terminal._

### Step 12: Start the container
The wizard runs `docker compose up -d`. On success, it prints a summary.

### Step 13: Summary
The wizard prints useful commands and the container is now running.

> _Screenshot 8 placeholder: wizard summary showing running container and commands._

---

## Step 6 — Verify it works

Open a Telegram group you're a member of and ask someone to send a message mentioning `@your_username` (or use a second account). Within seconds, the bot you configured will DM you the alert.

If no alert arrives → see [TROUBLESHOOTING.md](TROUBLESHOOTING.md) §"No alerts received".

---

## Step 7 (optional) — Auto-start on boot

### Linux (systemd)
The container has `restart: unless-stopped`, so it comes back automatically when the Docker daemon starts. To make Docker start on boot:
```bash
sudo systemctl enable docker
```

### macOS (Colima)
```bash
brew services start colima
```

### Windows
Docker Desktop and Podman Desktop both have a *"Start at login"* option in their settings.

---

## Step 8 (optional) — Back up the session file

The session file at `data/mentions_session.session` is equivalent to a credential. Back it up periodically to avoid re-authentication after a hard shutdown:

```bash
# Linux/macOS — copy to ~/Backups/
cp data/mentions_session.session ~/Backups/mention-mate-session-$(date +%Y%m%d).session
```

```powershell
# Windows
Copy-Item data\mentions_session.session "$env:USERPROFILE\Backups\mention-mate-session-$(Get-Date -Format yyyyMMdd).session"
```

The update wizard automatically reminds you to back up if the session is more than 7 days old.

---

## Next steps

- 🐛 Hit a problem? → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- 📝 Need to upgrade? → `./update.sh` or `.\update.ps1`
- 🗑️ Want to uninstall? → `docker compose down && rm -rf data .env` (note: removing the session file means you'll need to re-authenticate Telethon if you reinstall).

---

*This guide tracks MentionMate v0.1.0. Screenshots will be added after pilot testing.*
