# MentionMate — Codebase Summary

## Directory Structure

```
mention-mate/
├── src/mention_mate/               # Main Python package
│   ├── __init__.py                # Version string: __version__ = "0.1.0"
│   ├── __main__.py               # Entry point: daemon loop (132 LOC)
│   └── auth.py                   # Interactive Telethon login (42 LOC)
├── scripts/                        # Setup and update wizards (unified)
│   ├── mention-mate.sh           # Linux/macOS unified setup/update (~430 LOC)
│   └── mention-mate.ps1          # Windows unified setup/update (~370 LOC)
├── docs/                          # Developer documentation (user docs in README.md)
├── .github/workflows/
│   └── release.yml               # GHA multi-arch Docker build + publish
├── Dockerfile                     # Multi-stage Python image (44 LOC)
├── docker-compose.yml             # Single-service Compose config (49 LOC)
├── pyproject.toml                 # Package metadata, dependencies
├── .env.example                   # Configuration template (41 LOC)
├── README.md                      # Public-facing overview (172 LOC)
├── CHANGELOG.md                   # Keep-a-Changelog format
├── LICENSE                        # MIT license
└── .gitignore / .dockerignore     # Exclude .env, session files, etc.
```

## Entry Points

### Runtime: `python -m mention_mate`
**File:** `src/mention_mate/__main__.py`

Loads `.env` variables, starts a Telethon `TelegramClient` connected to the user's Telegram account, registers an event handler on `NewMessage(incoming=True)`, and waits for mentions. Runs indefinitely until `KeyboardInterrupt` or network failure.

**Flow:**
1. Load env vars: `TG_API_ID`, `TG_API_HASH`, `TG_MY_USERNAME`, `TG_BOT_TOKEN`, `TG_ALERT_CHAT_ID`.
2. Parse `BOT_ID` from token (prefix before `:`).
3. Create Telethon userbot client + aiohttp session.
4. Register event listener on all incoming messages.
5. For each message: check if text contains `@{MY_USERNAME}` (case-insensitive).
6. If match: format HTML + plain-text alert, POST to Telegram bot API via aiohttp.
7. If HTML fails: retry with plain text. If both fail: log raw text for manual recovery.
8. Run until disconnected.

**Error Handling:**
- Bot API errors: logged and re-raised (cause daemon restart).
- Network timeouts: aiohttp defaults (5s) + exception logged.
- Malformed HTML in user messages: caught, escaped with `html.escape()`, and fallback to plain text.

### Setup: `python -m mention_mate.auth`
**File:** `src/mention_mate/auth.py`

Interactive Telethon login. Prompts for phone number, OTP, and 2FA password. Saves session to `/app/data/mentions_session.session`. Invoked by the setup wizard inside a one-time `-it` container.

**Output:** Exit code 0 on success, 1 on missing env vars or API errors.

## Core Modules

### `__main__.py` (132 LOC)

**Responsibilities:**
- Telethon client initialization and lifecycle management.
- Message filtering and @mention detection (case-insensitive substring match on `@{username}`).
- Alert formatting: HTML with escaping + plain-text fallback.
- aiohttp POST to Telegram bot API (sendMessage).
- Graceful error handling: try HTML → try plain → log raw text.

**Key Functions:**
- `_post_message(session, text, parse_mode)`: POST payload to bot API.
- `send_alert(session, html_msg, plain_msg, original_text)`: Two-attempt send with fallback.
- `handle_new_message(event)`: Event handler; runs on each incoming message.
- `main()`: Async entry point; initializes clients, starts userbot, runs event loop.

**Dependencies:**
- `telethon.TelegramClient`, `telethon.events.NewMessage`
- `aiohttp.ClientSession`
- `python-dotenv.load_dotenv`
- Standard library: `os`, `html`, `asyncio`

### `auth.py` (42 LOC)

**Responsibilities:**
- Interactive Telethon login flow.
- Session persistence to `/app/data/mentions_session.session`.

**Key Functions:**
- `main()`: Reads env vars, creates Telethon client, calls `client.start()` (prompts for credentials), disconnects.

**Dependencies:**
- `telethon.TelegramClient`
- Standard library: `os`, `sys`

### `__init__.py` (3 LOC)

**Responsibilities:**
- Package metadata: `__version__ = "0.1.0"`.

---

## Build & Distribution

### Docker Image

**File:** `Dockerfile` (44 LOC)

Multi-stage build:
- **Stage 1 (builder)**: Python 3.11-slim. Installs mention-mate package and dependencies from `pyproject.toml`.
- **Stage 2 (runtime)**: Python 3.11-slim. Copies installed packages from builder. Adds non-root user `tgbot` (uid 1001). Installs `procps` for `pgrep` in healthcheck. Sets `HOME=/app`. Declares OCI labels (title, description, source, license, authors). Defines `HEALTHCHECK` (pgrep for process alive). Runs as non-root.

**Healthcheck:** `pgrep -f 'python.*mention_mate'` every 30s (timeout 5s, retries 3, start_period 10s).

**CMD:** `python -m mention_mate`

**Image size:** ~150–180 MB (slim base ~130 MB + deps ~30–50 MB).

### Docker Compose

**File:** `docker-compose.yml` (49 LOC)

Single service `bot`:
- Image: `ghcr.io/phamhoang16/mention-mate:latest`
- Container name: `mention-mate`
- Env-file: `.env` (5 required vars)
- Volumes: `./data:/app/data` (session persistence)
- Healthcheck: Duplicates Dockerfile check; retries 3 times
- Resource limits: 256 MB memory (hard limit), 64 MB reserved, 0.5 CPU
- Logging: json-file, 10 MB per file, 3 files retained (max 30 MB)
- Restart: unless-stopped

---

## Configuration

### Environment Variables

**File:** `.env.example` (41 LOC)

| Variable | Type | Source | Purpose |
|----------|------|--------|---------|
| `TG_API_ID` | int | https://my.telegram.org/apps | Telegram API credential (user account) |
| `TG_API_HASH` | str | https://my.telegram.org/apps | Telegram API credential (user account) |
| `TG_MY_USERNAME` | str | Telegram Settings | Username to detect (without @) |
| `TG_BOT_TOKEN` | str | @BotFather /newbot | Token for alert delivery (bot account) |
| `TG_ALERT_CHAT_ID` | int | getUpdates or wizard auto-discovery | Chat ID for alerts (usually user's own DM) |

**Security Notes:**
- Wizard writes `.env` with chmod 600 (POSIX) / ACL restrictions (Windows).
- Sensitive inputs (API_HASH, BOT_TOKEN) read with terminal echo disabled.
- `.env` is gitignored and dockerignored.

---

## Setup Wizards

### `scripts/mention-mate.sh` (~430 LOC)

**Role:** Unified Linux/macOS setup/update wizard. Structured as 12 numbered steps for setup; update mode skips credential prompts.

**Interface:**
- `./mention-mate.sh` (no arg): Auto-detect mode (setup if no `.env` + session, update otherwise).
- `./mention-mate.sh setup`: Explicit setup wizard.
- `./mention-mate.sh update`: Explicit update mode.
- `./mention-mate.sh -h` / `--help`: Show help.
- `./mention-mate.sh -v` / `--verbose`: Verbose mode (print Docker commands).

**Setup Steps:**
1. Locate project root (auto-detect from script position or cwd).
2. Check Docker installed and running.
3. Check Docker Compose installed.
4. Check for existing configuration; offer overwrite.
5. Prompt and validate `TG_API_ID` (integer).
6. Prompt and validate `TG_API_HASH` (40 chars, hex; silent input).
7. Prompt and validate `TG_MY_USERNAME` (no @; alphanumeric + underscore).
8. Prompt and validate `TG_BOT_TOKEN` (silent input).
9. Pull Docker image from ghcr.io.
10. Discover `ALERT_CHAT_ID` via `docker run` + Telegram getUpdates + test message round-trip.
11. Write `.env` atomically (tmp + rename) with chmod 600.
12. Launch Telethon interactive login via `docker run -it`.
13. Start container via `docker compose up -d`.
14. Summary and success message.

**Update Steps:**
1. Detect current installed version.
2. If session file exists and mtime >7 days old: warn and offer backup to `data.session.bak`.
3. `docker compose pull`.
4. `docker compose up -d --force-recreate`.
5. Success message.

**Utilities:**
- `__locate_project_root()`: Walk up directory tree to find docker-compose.yml.
- `__get_subcommand()`: Parse `setup` / `update` / auto-detect.
- `log_step()`, `log_ok()`, `log_warn()`, `log_err()`: Colored output.
- `prompt_with_validation()`: Regex-validated re-prompt.
- `run_command_or_exit()`: Error handling with user-friendly messages.

### `scripts/mention-mate.ps1` (~370 LOC)

**Role:** Windows PowerShell equivalent of mention-mate.sh. Same interface and logic, adapted for Windows idioms.

**Interface:**
- `.\mention-mate.ps1` (no arg / positional): Auto-detect or `setup` / `update` subcommand.
- `.\mention-mate.ps1 setup` / `.\mention-mate.ps1 update`: Explicit modes.
- `.\mention-mate.ps1 -Help`: Show help.
- `.\mention-mate.ps1 -Verbose`: Verbose mode.

**Key Differences from Bash:**
- PowerShell syntax (arrays, hashtables, string interpolation).
- No `chmod` (uses `icacls` for ACL restrictions).
- No `realpath` (uses `Resolve-Path`).
- Error messages specify `powershell -ExecutionPolicy Bypass` workaround.

---

## Documentation

### `README.md` (≈225 LOC)

Public-facing overview and end-user guide. Contains:
- How it works, what you need.
- Install section with Docker setup per OS, credential retrieval, wizard execution (mention-mate.sh or mention-mate.ps1).
- Common commands (logs, stop, restart, update).
- Troubleshooting section with error codes (ERR-DIST-001 through ERR-DIST-006) and diagnosis/fixes.
- Privacy & security, roadmap, contribution links.

**Audience:** End-users (non-technical to moderately technical).

### Developer Documentation (in `docs/`)

- `docs/project-overview-pdr.md`: Problem, solution, target users, goals/non-goals, roadmap, constraints, risks, architecture, dependencies.
- `docs/codebase-summary.md`: Directory structure, entry points, modules, dependencies, runtime behavior.
- `docs/code-standards.md`: File naming, Python/shell/Docker conventions, commit rules, testing standards, security guidelines.
- `docs/system-architecture.md`: Component diagram, data flows, security model, deployment topology.
- `docs/project-roadmap.md`: Phases, milestones, success metrics, release schedule.
- `docs/deployment-guide.md`: Installation, updates, backups, troubleshooting, performance, security hardening, CI/CD, maintenance.

### `CHANGELOG.md`

Keep-a-Changelog format tracking all releases and changes. Current version [0.1.0] is planned/unreleased.

---

## Dependencies & Versions

### Runtime Dependencies
```
telethon==1.33.1       # Telegram client (MTProto)
aiohttp==3.9.5         # Async HTTP client
python-dotenv==1.0.1   # .env loader
Python >=3.11          # Language version
```

### Build Dependencies
```
setuptools>=68         # Package builder
Docker >=20.10         # Container runtime
GitHub Actions         # CI/CD (no local tool)
```

### External Services
```
api.telegram.org       # Telegram API (MTProto + bot HTTPS)
ghcr.io                # Docker image registry
```

---

## Code Quality & Standards

### Style
- **Python version**: 3.11+ (f-strings, async/await, type hints).
- **Type hints**: Current code is untyped (legacy from internal version); Phase 1 will add type hints for new code.
- **Async patterns**: Used throughout (`async def`, `await`, `aiohttp.ClientSession`, `asyncio.run`).
- **Error handling**: Try/catch with fallback (HTML → plain-text). Critical errors logged before re-raise.

### Shell Scripts
- Bash: `set -euo pipefail` for safety (exit on error, undefined vars, pipe failures).
- PowerShell: `$ErrorActionPreference = "Stop"` equivalent.
- Regex validation on user input (TG_API_ID integer, TG_API_HASH hex, etc.).
- Atomic file writes (write to tmp, rename to final path).

### Security
- `.env` and session files gitignored/dockerignored.
- Sensitive inputs read without echo (shell `read -s`).
- User runs as non-root in container (uid 1001).
- Session file chmod 600 (owner read/write only).
- HTML escaping on all user-generated content (sender names, group titles, message text).

### Testing
- **Current state**: No test suite (Phase 1 goal: ≥80% coverage).
- **Planned**: Unit tests for mention detection, alert formatting, HTML escaping; integration test for full alert pipeline.

---

## Known Limitations & TODOs

### Current (v0.1.0)
- No structured logging (print statements + stdout).
- No HTTP `/healthz` endpoint (pgrep healthcheck fragile on some systems).
- No retry/backoff logic (single attempt to send alert; logs on failure).
- No test coverage.
- Markdown mode fallback (Phase 1 goal: improve error handling).

### Deferred to Phase 1
- Structured logging with JSON output.
- `/healthz` REST endpoint replacing pgrep.
- Exponential backoff + circuit-breaker for bot API failures.
- Unit + integration tests.
- Dependency scanning (CVE checks) in release pipeline.

### Deferred to Phase 3
- Multi-keyword / regex pattern support.
- Digest mode (batch mentions).
- Web UI for configuration.
- Inline action buttons in alerts.
- Webhook forwarding to incident management systems.

---

## Runtime Behavior

### Daemon Loop
1. Telethon client connects (uses cached session or prompts for auth on first run).
2. Event listener registered: fire on every incoming message to any of the user's groups.
3. For each message:
   - Check sender_id ≠ BOT_ID (skip bot's own DM echoes).
   - Check text contains `@{MY_USERNAME}` (case-insensitive).
   - Fetch sender and chat details (async calls to Telegram API).
   - Format HTML alert with escaped content and jump link.
   - POST to bot API (aiohttp, 5s timeout).
   - On HTML failure: retry with plain text (no Telegram parsing).
   - On both failures: log raw text and error for manual recovery.
4. Log message forwarded to console.
5. Repeat until `KeyboardInterrupt` or network failure.

### Session Management
- **Location**: `/app/data/mentions_session.session` (inside container), mounted from `./data/` on host.
- **Lifecycle**: Created on first `client.start()` (interactive Telethon auth). Reused on subsequent runs (no re-auth needed).
- **Backup strategy**: mention-mate.sh update offers backup if mtime >7 days (prevent accidental loss on major version jump).
- **Revocation**: User opens Telegram Settings → Devices and logs out the session manually. Equivalent to revoking a bot token.

---

## Unresolved Questions

1. **Telethon event ordering**: Are messages guaranteed to be processed in order, or can concurrent events race? Defer to Phase 1 testing.
2. **Memory leak under sustained load**: Current code runs async handlers but doesn't close/cleanup on every event. Monitor peak memory in long-running tests (Phase 1).
3. **Telegram API rate limits**: Observed ~30 msg/sec per bot. MentionMate's load (~1–10 alerts/min) is well within limits, but confirm under peak usage.
