# Troubleshooting — MentionMate

Common problems and fixes. If your issue isn't listed, open a [GitHub issue](https://github.com/hoangp47/mention-mate/issues) with full logs and the version you're running.

---

## Table of contents

1. [Wizard / Setup](#wizard--setup)
2. [Network](#network)
3. [Auth (Telethon login)](#auth-telethon-login)
4. [chat_id](#chat_id)
5. [Container](#container)
6. [Update](#update)
7. [No alerts received](#no-alerts-received)
8. [Windows](#windows)
9. [macOS](#macos)
10. [General debugging](#general-debugging)

---

## Wizard / Setup

### ❌ `ERR-DIST-001: Docker daemon not running.`

**Cause:** the wizard ran `docker info` and it returned non-zero — Docker hasn't been started.

**Fix:**
- **Linux:** `sudo systemctl start docker` (systemd-based distros). Verify with `docker info`.
- **macOS Colima:** `colima start`. Verify with `colima status`.
- **macOS Docker Desktop:** open the app from Applications. Wait for the menu-bar icon to turn green.
- **Windows Docker Desktop:** open the app from the Start menu. Wait 30–60 s for it to initialize.
- **Windows WSL2:** in the WSL terminal, `sudo service docker start`.
- **Podman:** `podman machine start`.

### ❌ `ERR-DIST-001: Docker CLI not found.`

Docker CLI isn't installed or isn't on `PATH`.

**Fix:** see [SETUP.md §Step 1](SETUP.md#step-1--install-a-docker-runtime-skip-if-you-already-have-one).

### ⚠️ `Only docker-compose v1 (legacy) is available`

You're running `docker-compose` v1 (hyphenated, Python-based). The wizard will fall back, but v1 was deprecated in 2023.

**Recommended fix:** upgrade Docker Engine/Desktop to a version that bundles Compose v2 (Docker 20.10+).

### Wizard asks `Overwrite existing config? (y/N)` — what should I choose?

- Choose **N** if you've already set things up and want to keep your configuration.
- Choose **Y** if you want to re-enter everything (e.g. you revoked the old token). **Note:** only `.env` is overwritten; the session file is preserved. If you want a clean slate, manually delete `data/mentions_session.session` before running the wizard.

---

## Network

### ❌ `ERR-DIST-002: Image pull failed.`

The wizard could not pull from `ghcr.io/hoangp47/mention-mate`.

**Diagnose:**
```bash
# Test connectivity
curl -I https://ghcr.io
curl -I https://api.telegram.org
```

**Common causes:**

1. **Corporate network blocks ghcr.io / GitHub:**
   - Test: `curl -I https://ghcr.io` returns 4xx/5xx or times out.
   - Fix: use personal Wi-Fi, a 4G hotspot, or ask IT to open the firewall.

2. **DNS resolution failure:**
   - Test: `nslookup ghcr.io`
   - Fix: temporarily switch to 8.8.8.8 or 1.1.1.1.

3. **Corporate proxy:**
   - Set env: `export HTTPS_PROXY=http://proxy.viettel.com.vn:8080`
   - Configure proxy for Docker: edit `~/.docker/config.json` or Docker Desktop settings.

4. **GitHub rate limit (anonymous pull):**
   - Rare with ghcr.io. If it happens, log in: `docker login ghcr.io -u <username>`.

### Wizard hangs at `Calling getUpdates ...`

Telegram API timed out (default is 10 s in the wizard).

**Fix:**
- Verify connectivity to `api.telegram.org`: `curl -I https://api.telegram.org`.
- If the network is fine but the API is slow, retry after a few minutes.
- If the Viettel intranet blocks Telegram, the tool **cannot run on that network**. Use 4G or a personal network.

---

## Auth (Telethon login)

### ❌ `ERR-DIST-003: Telethon auth failed after 3 attempts.`

Telethon refused to log in the userbot.

**Causes:**

1. **Wrong OTP** — Telegram delivers the code to a different app/device. Check the "Telegram" official chat on your phone.
2. **Wrong 2FA password** — this is the password you set in Telegram Settings → Privacy & Security → Two-Step Verification.
3. **Account temporarily locked** — too many failed logins. Wait 1–24 h and retry.
4. **Wrong phone-number format** — must include the country code: `+84912345678` (no spaces, no parentheses).

**Fix:**
- Re-run `./setup.sh` (the wizard detects an existing session and skips auth if it previously succeeded).
- If it still fails: delete `data/mentions_session.session*` and re-run.

### Telethon prompts "Please enter your password (8 chars or more):"

Your account has 2FA enabled. Enter the password you configured in Telegram Settings → Two-Step Verification.

If you've **forgotten the 2FA password**: open the Telegram app → Settings → Two-Step Verification → "Forgot password" → reset via email (if you set up recovery email) or disable 2FA temporarily.

### `AuthKeyDuplicatedError`

The Telethon session is being used on multiple machines simultaneously.

**Fix:** remove the old session file and re-run setup:
```bash
rm data/mentions_session.session
./setup.sh
```

> ⚠️ **Rule of thumb:** one session per machine. Don't copy the session file between hosts.

---

## chat_id

### ❌ `Could not detect chat_id after 3 attempts.`

The wizard called the bot's `getUpdates` endpoint but found no `/start` message.

**Causes:**

1. **You sent `/start` to the wrong bot** — the wizard prints the correct bot username. Verify you messaged that one.
2. **Wrong bot token** — the wizard's `getMe` call would also fail. Double-check the token from BotFather.
3. **Update was already consumed** — `getUpdates` only returns unread updates. Re-calling the wizard skips already-read ones. Fix: send `/start` again before each attempt.
4. **Bot was suspended by Telegram** — rare. Create a new bot via BotFather.

**Manual debug:**
```bash
# Replace TOKEN with your real bot token
curl -s "https://api.telegram.org/botTOKEN/getMe"
curl -s "https://api.telegram.org/botTOKEN/getUpdates"
```
Look for `"chat":{"id":XXX, ...}` — that number is your chat_id.

### Wizard sent the test message but I didn't receive it

- Confirm the wizard printed the correct **chat_id** (positive = DM, negative = group).
- Confirm you're looking at **the right bot** in Telegram (similar names can be confusing).
- Try `/start` again to make sure the conversation is open.

---

## Container

### ❌ `ERR-DIST-004: Container failed to start.`

`docker compose up -d` ran but the container is unhealthy.

**Debug:**
```bash
docker compose logs --tail 100 bot
```

**Common causes:**

1. **Image could not be pulled** → see [Network](#network).
2. **`.env` is missing or malformed** → open `.env` and verify all 5 env vars.
3. **Wrong session-file permissions** → `chmod 600 data/mentions_session.session`.
4. **Port conflict** → MentionMate doesn't expose ports, so this shouldn't happen. If the log mentions a port issue, the image may be corrupt; re-pull.

### Container starts but enters `restarting (1)` loop

The tool crashes immediately after startup. Inspect the log:
```bash
docker compose logs bot
```

Look for lines containing "Error" or "Exception". Common errors:
- `AuthKeyDuplicatedError` → see [Auth](#auth-telethon-login).
- `ConnectionError` / `OSError: Network is unreachable` → see [Network](#network).
- `KeyError: 'TG_API_ID'` → `.env` wasn't loaded. Verify `env_file: .env` in `docker-compose.yml`.

### Container health = `unhealthy`

```bash
docker inspect mention-mate --format '{{.State.Health.Status}}'
```

`pgrep` cannot find the `python -m mention_mate` process. The container is either restarting or has crashed. Check the logs.

---

## Update

### ❌ `ERR-DIST-006: Container did not pick up the new image.`

After running `update.sh`, the container is still on the old image.

**Fix:**
```bash
docker compose down
docker compose pull
docker compose up -d --force-recreate
```

### Update lost my session file

`update.sh` does **not** remove the session. If the session file disappears after an update:
1. Verify the volume mount: `docker compose config | grep volumes`.
2. Check that the `./data` directory still exists.
3. Restore from backup `data/mentions_session.backup.*` if available.

---

## No alerts received

The container is running, but no alerts arrive when someone @mentions you.

**Checklist:**

1. **Container is running:** `docker compose ps` → status `Up`.
2. **Userbot is connected:** `docker compose logs bot | grep "Running"` → you should see "✅ Running: userbot listening...".
3. **`@username` matches:** check `.env` → `TG_MY_USERNAME=` must equal your Telegram username (no `@`).
4. **You're in the group:** the userbot only sees groups that **you** are a member of. The tool does not receive alerts from groups you haven't joined.
5. **It's a real `@mention`:** Telegram's `@username` (the autocomplete one) differs from a plain typed `@`. Test by pasting the exact `@username` into the message.
6. **chat_id is correct:** `.env` → `TG_ALERT_CHAT_ID=` must be the DM chat between you and the bot. If the wizard saved the wrong value, re-run setup.
7. **Live test:** from a second account, send `@your_username` in a group → check the log: `docker compose logs -f bot`.

---

## Windows

### ❌ `ERR-DIST-005: PowerShell is blocking unsigned scripts.`

ExecutionPolicy is set to `Restricted`.

**Temporary fix:**
```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

**Persistent fix:**
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# Or for a single session:
Set-ExecutionPolicy -Scope Process Bypass
```

> ⚠️ Some organizations (e.g. Viettel) have Group Policy that blocks even `Bypass`. Contact IT.

### Wizard hangs during "Telethon auth"

`docker run --rm -it` requires a TTY. PowerShell inside VS Code's integrated terminal **does not provide a TTY** → the wizard hangs.

**Fix:** run `setup.ps1` in a standalone PowerShell terminal (Windows Terminal, or `cmd.exe` → `powershell`).

### `docker: 'compose' is not a docker command.`

You're on the standalone `docker-compose` v1. The wizard will fall back. Upgrade Docker Desktop to get Compose v2.

---

## macOS

### `docker info` errors right after `colima start`

Give Colima 5–10 seconds to finish initializing. Verify with `colima status` → "Running".

### Apple Silicon (M1/M2/M3) — image runs slowly

The image may be running as linux/amd64 via Rosetta instead of native arm64.

**Verify:**
```bash
docker inspect mention-mate --format '{{.Architecture}}'
```

It should be `arm64`. If it's `amd64`, re-pull with the correct platform:
```bash
docker pull --platform linux/arm64 ghcr.io/hoangp47/mention-mate:latest
docker compose up -d --force-recreate
```

---

## General debugging

### Enable verbose mode in the wizard

```bash
./setup.sh -v
```

Prints every Docker command as it runs — useful for identifying which step is failing.

### Get full container logs

```bash
docker compose logs --tail 500 bot > debug.log
```

### Inspect container resources

```bash
docker stats mention-mate
```

Typical usage: ~50–120 MB RAM, < 5 % CPU.

### Full reset

```bash
docker compose down
rm -rf data .env
./setup.sh   # reinstall from scratch
```

> ⚠️ **Warning:** removing `data/` destroys the Telethon session. You'll need to re-authenticate (phone + OTP + 2FA) on the next run.

---

## Report a new issue

If your problem isn't covered above, open a [GitHub issue](https://github.com/hoangp47/mention-mate/issues/new) with:

1. **OS and version** (e.g. Ubuntu 22.04, Windows 11 22H2, macOS 13.5).
2. **Docker version:** `docker version`.
3. **MentionMate version:** check `CHANGELOG.md` or the image tag.
4. **Which wizard step failed.**
5. **Full wizard output** (paste into the issue; redact any tokens or credentials).
6. **Container log** (`docker compose logs --tail 100 bot`).

---

*New issues are added as pilot users discover them. Update via PR.*
