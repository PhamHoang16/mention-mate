# MentionMate — Deployment & Operations Guide

Operator-facing guide covering installation, updates, backups, and troubleshooting for running MentionMate in production.

---

## Quick Start

### Prerequisites
- Docker (20.10+) or Docker Desktop / Colima / Podman.
- Telegram account (personal, phone-verified).
- Telegram API credentials (2 minutes via https://my.telegram.org/apps).
- Bot token from @BotFather (1 minute).

### Installation (30 seconds)
1. **Download the release**: Visit [GitHub Releases](https://github.com/PhamHoang16/mention-mate/releases), download `mention-mate-v0.x.y.zip`, unzip.
2. **Run the wizard**: `./mention-mate.sh` (Linux/macOS) or `.\mention-mate.ps1` (Windows).
3. **Done**: Container runs in the background. Send a test mention to verify.

For detailed step-by-step with screenshots, see [README.md → Install](../README.md#install).

---

## Release Artifacts

### GitHub Release Contents
Each release tag (e.g., `v0.1.0`) includes:

1. **`mention-mate-v0.1.0.zip`** (source code + scripts)
   - `mention-mate.sh`, `mention-mate.ps1` (unified setup/update wizards)
   - `docker-compose.yml`, `.env.example`
   - `README.md`, `CHANGELOG.md`, `LICENSE`
   - Python source (`src/mention_mate/`)

2. **Docker image** (multi-arch: amd64, arm64)
   - Registry: `ghcr.io/phamhoang16/mention-mate`
   - Tags: `v0.1.0`, `0.1`, `latest`
   - Pulled automatically by setup wizard

3. **GitHub Release notes**
   - Description (from CHANGELOG.md [version] section)
   - Pre-release flag (if beta)
   - Contributor credits

### Build Pipeline (GitHub Actions)

**Trigger:** Push of git tag matching `v*.*.*` (e.g., `v0.1.0`).

**Workflow:** `.github/workflows/release.yml`

**Steps:**
1. Checkout code.
2. Set up Docker buildkit (multi-arch support).
3. Build image for linux/amd64 and linux/arm64.
4. Push to ghcr.io with tags:
   - `ghcr.io/phamhoang16/mention-mate:v0.1.0` (full version)
   - `ghcr.io/phamhoang16/mention-mate:0.1` (major.minor)
   - `ghcr.io/phamhoang16/mention-mate:latest` (latest release)
5. Create GitHub Release with source zip artifact.
6. Extract [0.1.0] section from CHANGELOG.md and embed as release notes.

**Duration:** ~10–15 minutes (build + push both architectures).

**Monitoring:** Check GitHub Actions tab for build status; failures block release.

---

## Installation & Setup

### Automated Setup Wizard

**File:** `mention-mate.sh` (Linux/macOS) or `mention-mate.ps1` (Windows)

**What it does:**
1. Locates project root (docker-compose.yml).
2. Checks Docker installed and running.
3. Checks Docker Compose available.
4. Detects existing `.env` and prompts for overwrite (idempotent).
5. Prompts for 4 required env vars with inline regex validation.
6. Pulls Docker image from ghcr.io.
7. Auto-discovers `ALERT_CHAT_ID` via Telegram getUpdates + test message.
8. Writes `.env` atomically with chmod 600 / ACL restrictions.
9. Launches Telethon interactive login (`docker run -it`).
10. Starts container (`docker compose up -d`).
11. Displays summary and next steps.

**Error Recovery:**
- If step N fails, wizard stops and displays error message + recovery instructions (see [README.md → Troubleshooting](../README.md#troubleshooting)).
- User can re-run wizard after fixing the issue (idempotent).

**Time:** 5–15 minutes depending on network and user interaction speed.

### Manual Setup (Expert Users)

If you prefer to skip the wizard:

1. **Get credentials:**
   ```bash
   # 1. API credentials: https://my.telegram.org/apps
   TG_API_ID=123456789
   TG_API_HASH=abc123def456...

   # 2. Your username (no @): Telegram Settings
   TG_MY_USERNAME=hoangp47

   # 3. Bot token: Chat @BotFather, send /newbot
   TG_BOT_TOKEN=999888777:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh

   # 4. Discover chat_id: https://api.telegram.org/bot<TG_BOT_TOKEN>/getUpdates
   # (Send a message to the bot first, then fetch updates and find chat.id)
   TG_ALERT_CHAT_ID=123456789
   ```

2. **Create `.env`:**
   ```bash
   cat > .env <<EOF
   TG_API_ID=$TG_API_ID
   TG_API_HASH=$TG_API_HASH
   TG_MY_USERNAME=$TG_MY_USERNAME
   TG_BOT_TOKEN=$TG_BOT_TOKEN
   TG_ALERT_CHAT_ID=$TG_ALERT_CHAT_ID
   EOF
   chmod 600 .env  # Linux/macOS
   icacls .env /inheritance:r /grant:r "%USERNAME%:F"  # Windows
   ```

3. **Authenticate (one-time):**
   ```bash
   docker run --rm -it -v ./data:/app/data --env-file .env \
       ghcr.io/phamhoang16/mention-mate:latest python -m mention_mate.auth
   ```
   (Follow prompts: phone number, OTP, 2FA password if enabled.)

4. **Start daemon:**
   ```bash
   docker compose up -d
   ```

5. **Verify:**
   ```bash
   docker compose logs bot  # Check startup logs
   # Have someone mention you in a group; bot should DM within seconds
   ```

---

## Daily Operations

### Viewing Logs

```bash
# Tail live logs
docker compose logs -f bot

# View last 100 lines
docker compose logs --tail=100 bot

# View logs from specific time
docker compose logs --since 10m bot
```

**Log rotation:** Configured in docker-compose.yml (json-file, 10 MB per file, 3 files = max 30 MB).

### Monitoring & Health

```bash
# Check container status
docker compose ps

# Health status
docker inspect mention-mate --format '{{.State.Health.Status}}'  # healthy, unhealthy, starting

# Full container info
docker compose exec bot ps aux  # Show running processes
```

**Healthcheck:** 30-second interval, 5-second timeout, 3 retries (pgrep-based in v0.1.0; Phase 1 upgrades to HTTP `/healthz`).

### Common Commands

| Task | Command |
|------|---------|
| Stop daemon | `docker compose down` |
| Restart daemon | `docker compose restart` |
| Pause alerts (keep running) | `docker compose pause bot` |
| Resume alerts | `docker compose unpause bot` |
| View resource usage | `docker stats mention-mate` |
| SSH into container | `docker compose exec -it bot /bin/bash` |

---

## Updates & Upgrades

### One-Command Update

```bash
# Linux/macOS
./mention-mate.sh update

# Windows PowerShell
.\mention-mate.ps1 update
```

**What it does:**
1. Detects current installed version (auto-detect mode if no arg; explicit `update` subcommand shown above).
2. If session file mtime >7 days old: warns user and offers backup to `data.session.bak`.
3. Pulls latest image from ghcr.io.
4. Recreates container (`docker compose up -d --force-recreate`).
5. Waits for healthcheck to pass; displays success or error.

**Time:** 1–5 minutes (image pull varies by connection speed).

**Downtime:** ~30 seconds (container restart). Mentions during this window may be missed.

### Manual Update

If update script fails:

```bash
docker compose pull bot              # Download latest image
docker compose up -d --force-recreate  # Restart with new image
docker compose logs -f bot           # Monitor startup
```

### Version Checking

```bash
# Current running version (from image tag)
docker compose config | grep image

# Check for newer versions
curl -s https://api.github.com/repos/PhamHoang16/mention-mate/releases/latest \
  | grep tag_name
```

### Breaking Changes & Migration

Each release documents breaking changes in CHANGELOG.md under [version] → Notes / Migration.

**Current (v0.1.0):** No breaking changes (first public release).

---

## Backup & Recovery

### Session File Backup

**Why:** Session file (`data/mentions_session.session`) is your "logged-in" credential. Loss requires re-authentication.

**When:** Before major updates (mention-mate.sh update prompts if session >7 days old).

**How:**
```bash
# Manual backup
cp data/mentions_session.session data/mentions_session.session.bak

# Or let mention-mate.sh do it
./mention-mate.sh update  # Offers backup if session is old
```

**Storage:** Keep backup on separate drive/cloud (avoid single point of failure).

**Restore:**
```bash
# If session corrupted or lost
cp data/mentions_session.session.bak data/mentions_session.session
docker compose restart
```

### .env Backup

**Why:** Contains API credentials. If container deleted, .env loss means manual reconfiguration.

**How:**
```bash
cp .env .env.bak
```

**Storage:** Keep backup in secure location (encrypted drive, password manager, etc.). Never commit to git.

### Full Backup (Pre-Major-Update)

```bash
# Archive everything
tar czf mention-mate-backup-$(date +%Y%m%d).tar.gz data/ .env docker-compose.yml

# Store securely
scp mention-mate-backup-*.tar.gz backup-server:/backups/
```

### Recovery from Backup

```bash
# Restore archived backup
tar xzf mention-mate-backup-20260520.tar.gz

# Start daemon with restored config
docker compose up -d

# Verify
docker compose logs bot
```

---

## Uninstall & Cleanup

### Complete Uninstall

```bash
# Stop and remove container
docker compose down

# Delete all local data (session, .env)
rm -rf data .env

# Remove image (optional, saves disk space)
docker rmi ghcr.io/phamhoang16/mention-mate:latest

# Revoke Telegram session (recommended)
# Open Telegram → Settings → Devices → find "MentionMate" → Log Out
```

**After uninstall:** Bot no longer sends alerts. If you re-install later, run setup wizard again.

### Partial Cleanup (Keep Config)

```bash
# Stop daemon but keep .env and data
docker compose down

# Later: restart with same config
docker compose up -d
```

### Docker Cleanup

```bash
# Remove unused images
docker image prune -a

# Remove unused containers
docker container prune

# Remove all dangling volumes
docker volume prune

# Full cleanup (extreme; removes all stopped containers & images)
docker system prune -a
```

---

## Troubleshooting

### Container Fails to Start

**Symptoms:** `docker compose up -d` succeeds but container exits immediately.

**Diagnosis:**
```bash
docker compose logs bot  # Check error message
```

**Common causes & fixes:**

| Error | Cause | Fix |
|-------|-------|-----|
| `TG_API_ID must be an integer` | .env has non-numeric value | Check .env; fix type; restart |
| `Missing environment variable: TG_API_HASH` | .env incomplete | Run setup wizard or add missing var |
| `Connection refused` (Telegram API) | Network blocked or Telegram down | Check firewall; verify api.telegram.org accessible |
| `Bad Request: USER_DEACTIVATED` | Telegram account disabled | Check account status; re-authenticate if needed |

### Session Revocation / Re-Auth

**Scenario:** You changed password, switched devices, or want to re-authenticate.

**Steps:**
1. Open Telegram → Settings → Devices.
2. Find "MentionMate" session → Tap to revoke.
3. Stop daemon: `docker compose down`.
4. Delete session: `rm data/mentions_session.session`.
5. Re-authenticate: `docker run --rm -it -v ./data:/app/data --env-file .env ghcr.io/phamhoang16/mention-mate:latest python -m mention_mate.auth`.
6. Restart: `docker compose up -d`.

### Bot Not Sending Alerts

**Symptoms:** Mentions detected in logs but no DM received.

**Diagnosis:**
1. Check bot token is valid: `curl https://api.telegram.org/bot<TOKEN>/getMe` (should return bot info).
2. Check chat_id is correct: `TG_ALERT_CHAT_ID` in .env should match your DM chat with the bot.
3. Verify bot has permission to message you: Send `/start` to the bot in Telegram, then check again.

**Fix:**
```bash
# Re-discover chat_id via getUpdates
curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
# Find your chat ID in the JSON response, update .env, restart
```

### High Memory or CPU Usage

**Diagnosis:**
```bash
docker stats mention-mate  # Check memory and CPU
docker compose logs bot | grep -i error  # Look for exception loops
```

**Common causes:**
- Infinite retry loop on bot API failure (Phase 1 fixes with circuit-breaker).
- Memory leak under sustained load (Phase 1 testing will find).

**Temporary fix:** Restart daemon.
```bash
docker compose restart
```

### Network Issues (Corporate Firewall)

**Symptoms:** Setup wizard fails at image pull or chat_id discovery.

**Diagnosis:** Check if firewall blocks api.telegram.org or ghcr.io.

**Solutions:**
- Use personal Wi-Fi, mobile hotspot, or VPN.
- Check with network admin if api.telegram.org can be whitelisted.
- If blocked permanently: MentionMate cannot operate on that network (by design).

### More Help

For detailed troubleshooting steps and error code reference, see [README.md → Troubleshooting](../README.md#troubleshooting).

---

## Performance & Resource Constraints

### Observed Resource Usage

| Metric | Idle | Peak | Limit |
|--------|------|------|-------|
| Memory | ~50 MB | ~120 MB | 256 MB |
| CPU | <1% | ~5–10% | 0.5 (50% of core) |
| Disk | ~130 MB (image) | +logs (capped 30 MB) | — |
| Network | <1 Mbps | ~5 Mbps (image pull) | — |

**Headroom:** 256 MB memory limit is comfortable for 100+ alerts/hour without OOM.

### Scaling Limits

- **Single-user only**: One daemon = one Telegram account.
- **One instance per machine**: Docker Compose runs one container. To run multiple instances, duplicate docker-compose.yml and change container name / ports.
- **Mention rate**: Telegram API allows ~30 messages/sec per bot; MentionMate's alert rate (~1–10/min) is well below.

### Optimization Tips

- **Reduce log verbosity** (Phase 1): Set log level to WARN to reduce I/O.
- **Disable healthcheck** (if not needed): Remove healthcheck from docker-compose.yml to save CPU.
- **Use lighter image** (future): `-alpine` base instead of `-slim` could save ~20 MB (trade-off: glibc compatibility).

### Update Subcommand Reference

The unified script supports:
- `./mention-mate.sh` (no arg): Auto-detect (setup if no `.env` + session, update otherwise).
- `./mention-mate.sh setup`: Explicit setup wizard.
- `./mention-mate.sh update`: Explicit update.
- `./mention-mate.sh -h` / `./mention-mate.sh --help`: Show help.
- `./mention-mate.sh -v` / `./mention-mate.sh --verbose`: Verbose logging (print Docker commands).

Windows PowerShell equivalents:
- `.\mention-mate.ps1` (no arg / positional): Same as above.
- `.\mention-mate.ps1 -Help`: Show help.
- `.\mention-mate.ps1 -Verbose`: Verbose mode.

---

## Security Hardening

### Default Security Posture (v0.1.0)

✅ **Good:**
- Non-root container user (uid 1001).
- .env gitignored and chmod 600.
- Session file encrypted by Telethon.
- HTTPS only for bot API.
- No telemetry or cloud dependencies.

⚠️ **Planned (Phase 1+):**
- Read-only filesystem mount (except /app/data and /tmp).
- Network policy (egress to api.telegram.org only).
- Secret scanning in CI/CD.

### Best Practices

1. **Protect `.env` file:**
   - Never commit to git (already gitignored).
   - Never share or email.
   - Restrict permissions: `chmod 600 .env`.

2. **Protect `data/` directory:**
   - Never sync to cloud (session file is credential equivalent).
   - Back up offline (separate drive).
   - Delete if machine compromised.

3. **Revoke session if compromised:**
   - Open Telegram → Settings → Devices → Revoke session.
   - Equivalent to logout; bot cannot send messages with old session.

4. **Keep image updated:**
   - Run `./mention-mate.sh update` monthly or when security updates announced.
   - Check GitHub Security Advisories for MentionMate CVEs.

5. **Firewall access (optional):**
   - Daemon uses outbound-only (no inbound ports by default).
   - If Phase 1 `/healthz` endpoint exposed: keep it localhost-only or use firewall rules.

---

## CI/CD & Automation

### GitHub Actions Release Pipeline

**File:** `.github/workflows/release.yml`

**Trigger:** Git tag push matching `v*.*.*` pattern (e.g., `git tag v0.1.0 && git push origin v0.1.0`).

**Manual trigger:** GitHub Actions UI → Workflows → Release → Run Workflow (button).

**Steps:**
1. Checkout repository.
2. Setup Docker buildkit (multi-arch cross-compilation).
3. Build docker image (linux/amd64, linux/arm64).
4. Push to ghcr.io (requires GitHub token in secrets).
5. Create GitHub Release with artifacts (source zip, changelog excerpt).
6. Publish release (auto-visible on Releases page).

**Requirements:**
- GitHub token (auto-provided as `github.token`).
- ghcr.io authentication (via Actions secret `GITHUB_TOKEN`).
- Branch protection: merge to `master` requires PR + reviews (recommended).

### Local Build (For Testing)

```bash
# Build image locally (no push)
docker build -t mention-mate:test .

# Test image
docker run --rm mention-mate:test python -m mention_mate --version

# Tag for manual push (if needed)
docker tag mention-mate:test ghcr.io/phamhoang16/mention-mate:test
docker push ghcr.io/phamhoang16/mention-mate:test
```

---

## Maintenance Schedule

### Daily
- Monitor container health: `docker compose ps` or use external monitoring (Uptime Robot, etc.).
- Check logs for errors: `docker compose logs --since 1h bot | grep -i error`.

### Weekly
- Review GitHub Issues for user-reported bugs.
- Triage and label issues (bug, feature-request, help-needed).

### Monthly
- Check for dependency updates: `pip list --outdated` (in container or local environment).
- Review security advisories (GitHub Dependabot, CVE databases).
- Update image if patches available: `./mention-mate.sh update`.

### Quarterly
- Review performance metrics (uptime, resource usage, alert latency).
- Collect user feedback for feature prioritization.
- Plan next phase (Phase 1 hardening, Phase 3 features).
- Update image if patches available: `./mention-mate.sh update`.

---

## Unresolved Questions

1. **Kubernetes deployment**: Should we provide a Helm chart for v0.2.0+? Defer pending community demand.
2. **Monitoring integration**: Should we support Prometheus metrics export? Defer to Phase 1 or later.
3. **Multi-instance load balancing**: Can multiple daemons share one bot token? No (bot can't handle concurrent auth sessions well); document as unsupported.
4. **Automated backups**: Should daemon auto-backup session file daily? Defer to Phase 1 as optional feature.
