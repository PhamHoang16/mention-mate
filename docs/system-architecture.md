# MentionMate — System Architecture

## Overview

MentionMate is a lightweight, self-hosted daemon that monitors Telegram group messages for @mentions and delivers them as dedicated push notifications via a bot DM.

**Core insight:** Two separate Telegram clients are required because a userbot (personal account) can read messages but cannot self-notify; a bot can DM the user and trigger a push notification. Both clients run in the same container, coordinated by a single async event loop.

---

## System Diagram

```
User's Groups (Telegram)
         |
         | (user subscribed to messages)
         v
    [Telegram Server — api.telegram.org]
         |
         | (NewMessage event via MTProto)
         v
   [__main__.py (Telethon)]
   (userbot event handler)
         |
   [Match @mention?]
   (case-insensitive substring)
         |
         | (if match)
         v
[permalink_resolver.resolve_message_link()]
   (discriminate Channel vs Chat vs User)
         |
         v
[alert_renderer.render_alert()]
   (HTML + plain-text, escape user content)
         |
         v
[aiohttp POST → Telegram Bot API]
   (https://api.telegram.org/bot<TOKEN>/sendMessage)
         |
         | (if HTML fails, retry with plain text)
         v
[Bot (Telegram API)]
         |
         | (DM to user's chat)
         v
[User — Push Notification]
   (Telegram Desktop / Mobile)
```

---

## Component Architecture

### 1. Userbot (Telethon Client)

**Role:** Listen to all groups the user is in and filter incoming messages.

**Technology:** Telethon 1.33.1 (Telegram MTProto client library).

**Responsibilities:**
- Establish persistent connection to Telegram's MTProto server.
- Subscribe to `NewMessage(incoming=True)` events (all messages user receives).
- For each event: extract sender ID, chat ID, message text, and sender/chat metadata.
- Skip messages sent by the bot itself (avoid self-notification loop).
- Detect @mention substring (case-insensitive).
- Trigger downstream alert pipeline on match.

**Session Persistence:**
- Telethon manages encrypted session file at `data/mentions_session.session`.
- First run: interactive auth (phone number, OTP, 2FA).
- Subsequent runs: reuse session (no re-auth).
- Host mounts `./data` volume so session survives container restart.

**Event Loop:**
- Async handler; single-threaded, multiplexed via asyncio.
- Non-blocking I/O on all Telegram API calls (`await event.get_sender()`, etc.).

### 2. Mention Detector

**Role:** Filter and identify @mention patterns.

**Logic:**
```
text = event.raw_text or event.message.message or ""
if MENTION_TOKEN in text.lower():
    # Match found
```

**Details:**
- Case-insensitive substring match: `"@hoangp47"` matches `@HOANGP47`, `@hoangp47`, etc.
- Fallback to `event.message.message` if raw_text is empty (e.g., media captions).
- Literal substring matching (no regex yet); Phase 3 will add regex support.

**Performance:** O(n) string search; acceptable for typical message lengths (<4KB).

### 3. Alert Formatter & Permalink Resolver (Separated Seams)

**Files:** `alert_renderer.py`, `permalink_resolver.py`

**Division of Responsibility:**

#### `permalink_resolver.resolve_message_link(chat, message_id) → str | None`
- **Input**: Telethon `chat` object (Channel, Chat, or User) + message ID.
- **Logic**: Discriminate by chat type using `isinstance(chat, Channel)`.
  - **Channels with username**: Return `https://t.me/{username}/{message_id}`.
  - **Channels without username**: Return `https://t.me/c/{chat_id}/{message_id}`.
  - **Basic groups & DMs**: Return `None` (no public permalink scheme).
- **Output**: URL string or None.
- **Why separate?** Telethon import boundary; testable in isolation; swappable for future schemes (deep-links, invite tokens).

#### `alert_renderer.render_alert(sender_name, chat_title, message_text, message_link) → (html_msg, plain_msg)`
- **Pure function**: keyword-only args, deterministic output, no side effects.
- **HTML Template:**
  ```html
  🔔 <b>You were mentioned!</b>
  👤 <b>From:</b> {sender_name_escaped}
  🏢 <b>Group:</b> {chat_title_escaped}
  
  <blockquote>{message_text_escaped}</blockquote>
  
  🔗 <a href="{message_link}">Jump to message</a>
  ```
  Or (if `message_link is None`):
  ```html
  💡 Basic group — open Telegram and check {chat_title_escaped} to find this message.
  ```
- **Escaping**: All user content via `html.escape()` before template insertion.
- **Plain-Text Fallback:**
  ```
  🔔 You were mentioned!
  👤 From: {sender_name}
  🏢 Group: {chat_title}
  
  {message_text}
  
  🔗 {message_link}
  ```
  (No escaping; used if HTML send fails.)
- **Why separate?** Pure, testable, format-change hub; imports only stdlib `html`.

### 4. HTTP Alert Sender (aiohttp) — `__main__.py`

**Role:** POST alert to Telegram bot API with retry/fallback logic.

**Endpoint:** `https://api.telegram.org/bot{TG_BOT_TOKEN}/sendMessage`

**Payload:**
```json
{
  "chat_id": {TG_ALERT_CHAT_ID},
  "text": "{alert_message}",
  "parse_mode": "HTML",  // or omitted for plain text
  "disable_web_page_preview": true
}
```

**Request Details:**
- Method: POST.
- Content-Type: application/json.
- Timeout: 5 seconds (aiohttp implicit default used; explicit in Phase 1).
- Retry logic: Try HTML → if exception, fallback to plain text → if both fail, log raw message.

**Response Handling:**
```python
{
  "ok": true,
  "result": { "message_id": 12345, ... }  // success
}

{
  "ok": false,
  "error_code": 400,
  "description": "Bad Request: ..."  // error
}
```
- Success: `ok=true` → silent success, log forwarding.
- Failure: `ok=false` or exception → raise `RuntimeError` for fallback attempt.

**Backoff Strategy (Phase 1):**
- Current: None; single attempt, fail and log.
- Planned: Exponential backoff (1s, 2s, 4s, 8s) with circuit-breaker (disable after 10 consecutive failures).

### 5. Bot (Telegram Bot API)

**Role:** Deliver alert DM to user, triggering push notification.

**Identity:**
- Created by user via @BotFather (/newbot).
- Token: `<bot_id>:<35-char-secret>` (immutable).
- Bot ID extracted from token: `int(token.split(':')[0])`.

**Responsibilities:**
- Receive sendMessage POST from userbot.
- Queue DM to user's chat.
- Telegram server delivers DM as notification (even if user muted the original group).

**Telegram Behavior:**
- Self-messages from userbot: delivered silently (no push notification).
- Messages from bot: delivered with push notification (assuming user has not muted the bot).
- Mute context: Group mute settings do NOT affect bot DMs; DMs are always notified (by default).

### 6. Configuration & Secrets

**Environment Variables** (loaded from `.env`):
| Variable | Type | Source | Used By |
|----------|------|--------|---------|
| `TG_API_ID` | int | my.telegram.org | Telethon (userbot) |
| `TG_API_HASH` | str | my.telegram.org | Telethon (userbot) |
| `TG_MY_USERNAME` | str | User's Telegram Settings | Mention detector (case-insensitive match) |
| `TG_BOT_TOKEN` | str | @BotFather | HTTP alert sender (bot endpoint) + bot_id extraction |
| `TG_ALERT_CHAT_ID` | int | Wizard auto-discovery | HTTP alert sender (sendMessage chat_id) |

**Security:**
- `.env` file: gitignored, dockerignored, chmod 600 (POSIX) / ACL-restricted (Windows).
- Sensitive inputs (API_HASH, BOT_TOKEN): read without terminal echo in setup wizard.
- Session file: encrypted by Telethon, chmod 600, not committed to git.

### 7. Container Runtime

**Docker Image:**
- Base: `python:3.11-slim` (~130 MB).
- Installed packages: telethon, aiohttp, python-dotenv (~30–50 MB).
- Total size: ~150–180 MB.

**Image Layers:**
1. Builder stage: Install Python 3.11, compile mention-mate package, install deps.
2. Runtime stage: Copy installed packages, add non-root user (uid 1001), procps for healthcheck, OCI labels.

**User & Permissions:**
- Non-root user: `tgbot` (uid 1001, gid 1001).
- Home directory: `/app`.
- Data directory: `/app/data` (chowned to tgbot, mounted to `./data` on host).

**Healthcheck:**
```bash
pgrep -f 'python.*mention_mate' > /dev/null || exit 1
```
- Interval: 30 seconds.
- Timeout: 5 seconds.
- Start period: 10 seconds (grace time after container start).
- Retries: 3 (fail healthcheck after 3 consecutive failures).
- **Limitation**: pgrep is fragile (process name match). Phase 1 replaces with HTTP `/healthz` endpoint.

**Entrypoint:**
```
CMD ["python", "-m", "mention_mate"]
```
- Runs the daemon in the foreground (no daemonization; Docker manages process).

### 8. Docker Compose Orchestration

**File:** `docker-compose.yml`

**Service: `bot`**
- Image: `ghcr.io/phamhoang16/mention-mate:latest` (pulled from GitHub Container Registry).
- Container name: `mention-mate` (fixed for user convenience).
- Env file: `.env` (5 required variables).
- Volumes: `./data:/app/data` (session persistence across restarts).
- Restart policy: `unless-stopped` (auto-restart unless user explicitly stops it).
- Resource limits: 256 MB memory (hard), 64 MB reserved, 0.5 CPU.
- Logging: json-file driver, 10 MB per file, 3 files retained (max 30 MB on disk).

**Lifecycle:**
1. `docker compose up -d`: Pull image, create container, start daemon.
2. Container runs indefinitely; restarts on failure (unless user stops it).
3. On update: `docker compose pull && up -d --force-recreate` (pull new image, recreate container).
4. On stop: `docker compose down` (remove container; volume persists).

---

## Data Flow (Happy Path)

```
1. User's phone (Telegram app) receives group message mentioning @hoangp47.

2. Telegram server routes NewMessage update to all connected clients.

3. Userbot (Telethon) receives NewMessage event:
   - sender_id = <user who sent message>
   - chat_id = <group chat id>
   - text = "<@hoangp47 please review this>"

4. Mention Detector (__main__.py):
   - Skip if sender_id == BOT_ID (self-check).
   - Check if "@hoangp47" (lowercased) in text.lower() → MATCH.

5. Permalink Resolver (permalink_resolver.py):
   - Fetch chat object: Channel("Team Alpha", id=123456, username="team-alpha")
   - Discriminate: Channel with username → resolve to "https://t.me/team-alpha/{msg_id}"

6. Alert Renderer (alert_renderer.py):
   - Fetch sender name: "Alice"
   - Fetch chat title: "Team Alpha"
   - Escape all: sender_html="Alice", chat_html="Team Alpha", text_html="<@hoangp47...>"
   - Render HTML + plain-text templates with escaped content + resolved link.
   - Return: (html_msg, plain_msg)

7. HTTP Alert Sender (__main__.py):
   - POST to https://api.telegram.org/bot<TOKEN>/sendMessage
   - Payload: {"chat_id": 123456, "text": "<HTML>...", "parse_mode": "HTML"}
   - Response: {"ok": true, "result": {...}}

8. Bot (Telegram API):
   - Receives sendMessage request from our code.
   - Queues DM to user's chat (ALERT_CHAT_ID).

9. Telegram server:
   - Delivers DM to user's Telegram app.
   - Since DM is from a bot and user hasn't muted the bot, push notification sent.

10. User's phone:
    - Receives push notification "You were mentioned! From: Alice..."
    - User taps notification → jumps to the original message in the group.
```

---

## Error Paths

### Path 1: HTML Parse Failure
```
1. Alert Formatter creates HTML.
2. HTTP POST with parse_mode="HTML" fails (e.g., malformed HTML from user content).
3. Exception caught in send_alert().
4. Fallback: retry POST with plain_msg, parse_mode=None (or omitted).
5. If plain-text also fails: log raw message and raise exception.
6. Daemon logs error and waits for next message (no crash).
```

### Path 2: Bot API Rate Limit
```
1. HTTP POST returns 429 Too Many Requests.
2. Exception raised and caught.
3. Logged with warning emoji.
4. Fallback attempted (plain text).
5. If all retries fail: alert lost, logged with error code (Phase 1 adds circuit-breaker).
```

### Path 3: Network Timeout
```
1. aiohttp timeout (5s) exceeded while waiting for bot API response.
2. asyncio.TimeoutError raised.
3. Caught in send_alert(), logged with warning.
4. Fallback attempted.
5. If both attempts timeout: alert lost, logged with timestamp for manual recovery.
```

### Path 4: Missing .env Variable
```
1. Daemon starts; loads .env via python-dotenv.
2. os.getenv('TG_API_ID') returns None.
3. int(None) raises TypeError at module load time.
4. Container fails to start; docker compose logs shows error.
5. User must populate .env and restart: docker compose restart.
```

---

## Deployment Topology

### Single-Machine Deployment (Current)
```
User's Machine
├── Docker Runtime (Engine or Desktop)
├── docker-compose.yml + .env
├── data/ (session file, logs)
└── mention-mate container
    ├── Telethon userbot (MTProto ↔ Telegram server)
    ├── Mention detector (filter)
    ├── Alert formatter (HTML/plain)
    └── aiohttp (HTTPS ↔ Telegram bot API)

Outbound Connections:
- api.telegram.org (Telegram's server)
- ghcr.io (one-time image pull)
```

### Kubernetes Deployment (Future, Phase 2)
- Pod: Single container (mention-mate).
- Volume: PersistentVolumeClaim for `data/` (session file).
- ConfigMap: Environment variables (except secrets).
- Secret: TG_BOT_TOKEN, TG_API_HASH (sensitive).
- Liveness probe: Replace pgrep with HTTP `/healthz` (Phase 1).
- Resource requests/limits: 64 MB / 256 MB memory, 0.5 CPU.

---

## API Contracts

### Environment Variables (Input)
```bash
TG_API_ID=123456789              # Integer
TG_API_HASH=abc123...def456      # 40 hex characters
TG_MY_USERNAME=hoangp47          # Alphanumeric + underscore (no @)
TG_BOT_TOKEN=999888777:secret    # <id>:<35-char-secret>
TG_ALERT_CHAT_ID=123456789       # Integer (positive or negative)
```

### Telegram Bot API (Output)
```
POST https://api.telegram.org/bot{TOKEN}/sendMessage
Content-Type: application/json

{
  "chat_id": 123456789,
  "text": "...",
  "parse_mode": "HTML",
  "disable_web_page_preview": true
}

Response (success):
{
  "ok": true,
  "result": {
    "message_id": 12345,
    "chat": {...},
    "date": 1234567890,
    ...
  }
}

Response (error):
{
  "ok": false,
  "error_code": 400,
  "description": "Bad Request: ..."
}
```

### Telethon API (Input)
```python
client = TelegramClient('data/mentions_session', api_id, api_hash)
await client.start()

@client.on(events.NewMessage(incoming=True))
async def handler(event):
    event.raw_text       # Message text
    event.sender_id      # User ID of sender
    event.id             # Message ID
    chat = await event.get_chat()
    chat.id              # Chat ID
    chat.title           # Group name
    sender = await event.get_sender()
    sender.first_name    # Sender's display name
```

---

## Scalability Considerations

### Limits
- **Telegram API rate limit**: ~30 messages/second per bot. MentionMate's alert load (~1–10/min) is well below.
- **Telethon session**: One per account. Multi-account support (Phase 3?) requires separate processes/containers.
- **Memory**: Observed ~50 MB idle, ~120 MB peak under normal load. 256 MB limit is comfortable.
- **Network**: Outbound-only to api.telegram.org (no inbound). Suitable for NAT, firewall, offline scenarios.

### Non-Scalable Aspects (By Design)
- **No database**: Stateless daemon (except session file). Can't aggregate data across instances.
- **Single user**: One daemon = one Telegram account. No multi-user hub.
- **No cloud**: Self-hosted only. No central server to scale.

### Future Scaling (Phase 3 + beyond)
- **Webhook integration**: Forward mentions to incident management (Pagerduty, Opsgenie).
- **Digest mode**: Batch mentions hourly/daily instead of real-time (reduces alert spam).
- **Web UI**: Central config dashboard (would require separate web service + database).

---

## Security Architecture

### Threat Model
| Threat | Impact | Mitigation |
|--------|--------|-----------|
| .env file leak (exposed API_HASH, BOT_TOKEN) | Attacker can read user's messages (userbot) or send spam as bot | .env gitignored, chmod 600, only on user's machine |
| Session file stolen | Attacker can read messages as the user | Session encrypted by Telethon, chmod 600, revocable via Telegram |
| bot_id extracted from token | Attacker knows the bot's ID but can't send messages (token secret unknown) | Token secret never logged or exposed; only token prefix used (bot_id) |
| HTML injection in user content | Alert message corrupted or Telegram parsing error | All user content escaped via html.escape() before HTML mode |
| ReDoS in regex (Phase 3) | CPU exhaustion from pathological regex patterns | Validate regex at config time, timeout=1s on re.search() |

### Security by Design
1. **Non-root container**: Daemon runs as uid 1001 (tgbot user). Even if container escaped, attacker has limited system access.
2. **Read-only filesystem (future)**: Phase 1 can add read-only mount for non-data parts (improve hardening).
3. **No telemetry**: No pings home, no analytics, no user tracking. Data stays on user's machine.
4. **Immutable secrets**: Token revocable via Telegram; session revocable via Telegram Settings → Devices.
5. **Atomic file writes**: .env and session writes never partial; prevents corruption on crash.

---

## Monitoring & Observability

### Current (v0.1.0)
- **Logging**: print() statements with emoji prefixes (🚀, ✅, ⚠️, ❌).
- **Healthcheck**: pgrep for process alive (30s interval).
- **Metrics**: None (Phase 1 goal).

### Planned (Phase 1)
- **Structured logging**: JSON format with timestamps, severity, context (sender, group, status).
- **HTTP `/healthz` endpoint**: Replace pgrep with REST health check (more reliable).
- **Metrics export**: Prometheus-compatible metrics (alerts sent, errors, latency).
- **Log aggregation**: Option to forward logs to external SIEM (optional, not forced).

---

## Unresolved Questions

1. **Session expiry**: Does Telethon session eventually expire? How is re-auth handled? Defer to Phase 1 testing under sustained load.
2. **Concurrent message handling**: If two groups emit mentions simultaneously, are handlers serialized or concurrent? Affects latency. Defer to async analysis.
3. **Memory leaks**: Long-running daemons may accumulate unreferenced objects. Monitor in Phase 1 stress tests.
4. **Telegram API versioning**: Does api.telegram.org have stable semver? Or do breaking changes roll out silently? Subscribe to Telegram API announcements.
