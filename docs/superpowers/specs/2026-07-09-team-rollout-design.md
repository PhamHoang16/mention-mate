# MentionMate — Team Rollout Design (Centralized VPS)

Status: approved (design phase) — 2026-07-09

## Context

MentionMate today is a single-user tool: one person runs `mention-mate.sh`/`.ps1`
locally (or on their own box), logs their own Telegram account in as a userbot,
creates their own alert bot, and gets DMs when someone @mentions them.

The team now wants this rolled out to the whole department (~10–20 people),
run centrally on the admin's own VPS instead of everyone self-hosting. This
doc captures the architecture and rollout process for that; it does **not**
change the core MentionMate application (userbot + alert-bot logic stays as
is).

## Decisions ruled out (and why)

- **Single shared userbot account** watching all team groups — rejected:
  only sees groups it's manually added to, misses private/unlisted groups per
  member.
- **Fully local per-user Docker (self-hosted on personal machines)** —
  considered, but requires the device to stay on/awake and gives the admin no
  central operational lever; superseded once web-based OTP registration was
  judged acceptable friction for non-technical users.
- **Native binary (PyInstaller) as OS service, no Docker** — feasible
  (systemd/launchd/Windows Service all support autostart+autorestart
  natively), but doesn't remove the real friction point (Telegram OTP login
  is unavoidable regardless of packaging) and adds cross-platform
  code-signing cost. Dropped once centralized VPS was chosen.
- **Multi-tenant single process** (one backend holding N `TelegramClient`
  instances in one event loop) — more resource-efficient, but requires
  rewriting the existing app and loses per-user crash isolation. At 10–20
  users the per-container resource cost is negligible (~80–150MB idle RAM
  each), so isolation wins.
- **Per-session outbound proxy** (residential/mobile, to avoid Telegram
  treating N logins from one VPS IP as suspicious) — technically valid
  mitigation (Telethon/Pyrogram support a `proxy=` param), but judged
  overkill for this scale: the userbot only *reads* messages (passive), and
  Telegram's abuse heuristics key off active behavior (mass send/join), not
  passive listening. Staggered registration (below) is the chosen mitigation
  instead. Left as an optional future hardening item, not in scope.

## Architecture

Centralized on the admin's VPS. Every user gets their own isolated Docker
container running the **unmodified** MentionMate image. Nothing in
`src/mention_mate/` changes for this rollout — this is a deployment/ops
concern, not an application change.

| Component | Role | New or existing |
|---|---|---|
| MentionMate image (`ghcr.io/phamhoang16/mention-mate`) | Per-user userbot (reads mentions) + relays to alert bot | Existing, unchanged |
| Shared alert bot (BotFather) | Delivers DM alerts for every user | Existing mechanism, created once, token reused across all containers |
| Registration Web UI | Collects phone / API_ID / API_HASH / username, runs the Telegram OTP (+2FA) flow | **New** |
| Backend orchestrator | Drives Telethon login, persists session, generates `.env`, `docker run`s the user's container, enforces a staggered-login queue | **New** |

Per-container config: identical image, different `.env` (shared
`TG_BOT_TOKEN`; per-user `TG_API_ID`/`TG_API_HASH`/`TG_MY_USERNAME`; per-user
data volume `./data/<username>/`).

## Registration flow

1. **Admin, once:** create the shared bot via BotFather, get `TG_BOT_TOKEN`,
   configure it into the backend.
2. **User, once, outside the web UI:** create their own app at
   my.telegram.org to get their own `TG_API_ID`/`TG_API_HASH` — this cannot
   be done on the user's behalf, it's tied to their personal account.
3. **User visits the Web UI** (internal-only, see Security) and submits:
   phone number, `TG_API_ID`, `TG_API_HASH`, Telegram username.
4. **Backend requests an OTP** via Telethon; user enters the code (+2FA
   cloud password if their account has one enabled).
5. **On successful login**, backend:
   - Persists the Telethon session under `./data/<username>/` (restrictive
     permissions).
   - Generates the user's `.env` (shared bot token + their own
     API_ID/HASH/username; `TG_ALERT_CHAT_ID` auto-resolved since the bot is
     already known).
   - `docker run`s a new container named `mention-mate-<username>` with its
     own data volume.
6. **Staggered queue:** if several people register close together, the
   backend enqueues actual session creation with a minimum gap between logins
   (e.g. 10–15 min) rather than firing them all at once, to avoid a burst of
   new sessions from a single IP looking anomalous to Telegram.
7. User gets a confirmation DM via the shared bot once their container is up.

**Re-registration** (session revoked/logged out remotely): user repeats the
OTP flow via the Web UI; the backend treats this as idempotent per
username — stops the old container, starts fresh with the new session.

## Operation

- Self-service model — no central health dashboard for the admin. Each
  user notices if alerts stop arriving and re-registers.
- `restart: unless-stopped` (already in `docker-compose.yml`) handles
  crash-recovery automatically.
- Admin's periodic tasks: watch aggregate VPS resource usage
  (`docker stats`, `df -h`), pull image updates, rotate `TG_BOT_TOKEN` if it
  is ever suspected compromised.

## Security

This setup holds custody of everyone's personal Telegram session on one
box, so:

- Web UI is **internal-only** (VPN/company network) — never publicly
  exposed. It's handling personal-account OTP/2FA.
- TLS required even for internal-only access — OTP/2FA must never cross the
  network in the clear.
- No logging of phone numbers, OTP codes, or 2FA passwords anywhere
  (application logs, web server access logs).
- Per-user session directories (`./data/<username>/`) locked down
  (`chmod 700`), readable only by the account running the Docker daemon.
  Consider OS-level volume encryption (LUKS) given the sensitivity of this
  data.
- SSH access to the VPS restricted to the admin only. The backend runs with
  the minimum privilege needed to call the Docker API — avoid running it as
  full root where avoidable.

## Resource sizing (10–20 users)

Per-container footprint is small and mostly idle (event-driven userbot,
wakes only on incoming messages):

| Resource | Per container (idle) | 20 containers | VPS recommendation |
|---|---|---|---|
| RAM | ~80–150MB | ~2–3GB | 4–8GB |
| CPU | ~0, brief spikes on message | <0.3 core aggregate | 2 vCPU |
| Disk | image layers shared + 30MB log cap + KB-scale session | ~1–2GB | 20–40GB SSD |

A modest VPS (4 vCPU / 8GB RAM / 40GB SSD) comfortably covers 20 users plus
the registration backend and Docker daemon overhead, with headroom to grow.

## Out of scope / future hardening

- **IP-ban risk reassessment (2026-07-10, after real rollout started):**
  userbot is passive-read-only (no send/join-spam behavior), which is the
  main trigger for Telegram's anti-abuse — so risk stays low/moderate at
  the current ~10-20 user scale, especially with the stagger queue already
  in place. Two real testers logged in successfully with no restrictions
  observed. If flagging is actually observed, or the team grows well past
  ~20 users, two mitigations to revisit (cheapest first):
  1. Increase `REGISTRAR_STAGGER_SECONDS` (free, one env var).
  2. Per-session outbound proxy via `TelegramClient(proxy=...)` — routed
     through the admin's own already-owned Tailscale-connected devices
     (phone/laptop) for a real residential IP at zero extra cost, rather
     than paying for residential/mobile proxy services or extra VPS IPs
     (still datacenter-flagged). Needs code: thread a proxy config through
     `telegram_login.py`.
- Central health/heartbeat dashboard, if self-service stops being
  sufficient.
