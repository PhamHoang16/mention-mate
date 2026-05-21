# MentionMate — Project Overview & Product Development Requirements

## Problem Statement

DevOps engineers, product managers, and technical leads work across 10+ Telegram project groups simultaneously. To stay focused, they mute group notifications. But when team members @mention them (e.g., requesting urgent feedback, escalating incidents), those calls get buried in the muted feed — resulting in missed deadlines, delayed incident response, and communication friction.

**Core issue:** Telegram's notification system doesn't distinguish mention urgency from general group chatter.

## Solution

MentionMate is a lightweight, self-hosted daemon that:
1. Monitors all groups the user is in via their personal Telegram account (userbot).
2. Detects when someone @mentions the user's handle.
3. Routes each mention as a dedicated push notification via a bot DM (bypassing group mute settings).

**Key insight:** Two separate Telegram clients (userbot + bot) work around Telegram's self-message notification quirk: a userbot cannot push-notify itself, but a bot can DM the user reliably.

## Target Users

- **Primary:** DevOps engineers, SREs, technical leads in organizations with >10 active Telegram groups and mute-everything workflows.
- **Secondary:** Anyone in highly-connected teams who values interrupt-driven mention alerts without cloud dependencies.
- **Estimated cohort:** Viettel internal tech teams (~150–500 users initially), then open-source adoption.

## Goals & Non-Goals

### Goals (v0.1.0 — Productization)
- ✅ Distribute as a Docker image (ghcr.io) with multi-arch builds (amd64 + arm64).
- ✅ Cross-platform installation wizard (mention-mate.sh for Linux/macOS, mention-mate.ps1 for Windows).
- ✅ End-user-focused documentation (README.md with step-by-step guides, Troubleshooting section with error codes).
- ✅ Transparent, idempotent container startup.
- ✅ Security by default: session files and env-vars excluded from repo, chmod 600 permissions, non-root container user.

### Goals (Phase 1 — Hardening) **In Progress**
- ✅ **First test scaffold**: 13 tests covering new seams (permalink resolver, alert renderer); pytest installed as optional dev dependency.
- Structured logging (timestamps, severity levels, JSON output for SIEM).
- HTTP `/healthz` health check endpoint (replaces `pgrep` in compose).
- Exponential backoff + circuit-breaker for Telegram API failures.
- Expand test coverage (mention detection, config loading, integration tests) → 80% full codebase.
- Dependency pinning + CVE scanning in CI/CD.

### Goals (Phase 3 — Feature Expansion) **Planned**
- Multi-keyword detection: regex patterns for project names, incident triggers, @team mentions.
- Digest mode: batch hourly/daily mentions instead of real-time spam if user is offline.
- Inline action buttons: "Mark as read", "Snooze 1h", "Mute group" directly from the alert.
- Optional web UI for configuration (keyword rules, alert frequency, etc.).
- Webhook forwarding to incident management systems (Pagerduty, Opsgenie).

### Non-Goals
- Cloud-hosted service: MentionMate is explicitly self-hosted. No central server, no SaaS.
- General-purpose notification hub: not a replacement for Telegram Desktop or mobile.
- Multi-account support: one daemon = one Telegram account.
- Message storage or history: no database, no audit trail.
- Telemetry or analytics: no pings home, no usage tracking.

## Scope by Phase

### Phase 1: Hardening
- **Functional**: No new features; improve observability, resilience, and test coverage.
- **Deliverables**: Structured logging, `/healthz` endpoint, retry policy, unit tests (mention detection, alert formatting), integration test (alert pipeline end-to-end).
- **Timeline**: TBD.

### Phase 2: Productization (v0.1.0 — This Release)
- **Functional**: Distribution, wizard, end-user docs.
- **Deliverables**: Docker image, GHA release pipeline, unified setup/update scripts (mention-mate.sh and mention-mate.ps1).
- **Timeline**: Pilot release; then public v0.1.0 after pre-release cleanup.

### Phase 3: Feature Expansion
- **Functional**: Multi-keyword, digest, action buttons, web UI, integrations.
- **Deliverables**: New modules (keyword/pattern engine, digest scheduler, REST API layer), web UI frontend, webhook handlers.
- **Timeline**: Post-v0.1.0; user feedback will prioritize which features to include.

## Success Metrics

### Phase 2 (Productization)
- **Installation success rate**: ≥95% of users complete setup wizard without manual intervention (tracked via issue reports).
- **Time-to-running**: ≤15 min from first download to first mention alert (per README.md target).
- **Documentation coverage**: Every environment-var, error code, and CLI command documented with examples.
- **Release automation**: Zero manual steps in tag → image push → GitHub Release flow.

### Phase 1 (Hardening)
- **Test coverage**: ≥80% code coverage (measured by coverage.py).
- **Structured logs**: All internal events logged with timestamp, level, context (sender, group, status).
- **Uptime**: Dashboard/`/healthz` endpoint confirms container alive ≥99% of the time (under normal network conditions).
- **Failure recovery**: Exponential backoff prevents bot API hammering; circuit breaker disables alerts after 10 consecutive failures, prevents app crash.

### Phase 3 (Feature Expansion)
- **User adoption of new keywords**: ≥30% of users create >1 custom keyword rule.
- **Digest usage**: If enabled, ≥10% opt into digest mode.
- **Integration requests**: Track webhook / action-button feature requests as proxy for demand.

## Constraints

### Technical Constraints
- **Python 3.11+**: Project uses f-strings, async/await, type-hint syntax available in 3.11.
- **Telethon 1.33.1**: Fixed version; newer versions may introduce breaking changes in MTProto protocol. Pinned to avoid surprises.
- **Docker image size**: Multi-stage build keeps runtime image <200 MB (slim base + minimal deps: telethon, aiohttp, python-dotenv).
- **No database**: Stateless daemon; session file is the only persistent artifact (Telethon-managed).
- **No cloud dependencies**: Outbound traffic only to api.telegram.org (Telegram's server) and ghcr.io (one-time image pull).

### Regulatory & Platform Constraints
- **Telegram Terms of Service**: Bot must not spam, must honor user rate limits, must not sell/resell data. MentionMate is compliant: one user per instance, no data resale, user-controlled filtering.
- **Telegram API rate limits**: ~30 messages/second per bot. MentionMate's alert load is ~1–10 per minute (well below limits).
- **Session file security**: Telethon session ≈ logged-in device credential. User responsible for protecting .env and data/ directory (wizard enforces chmod 600).
- **Container image distribution**: Must pass OCI best practices (non-root user, labels, health checks); GHA release pipeline validates signatures on multi-arch builds.

### Operational Constraints
- **Always-on requirement**: Daemon must run continuously (docker compose restart: unless-stopped). If user's machine is off, mentions are lost (Telegram doesn't queue for offline clients).
- **Network availability**: Requires outbound access to api.telegram.org. Firewall blocks or network outages → no alerts.
- **User machine resources**: 256 MB memory limit enforces low overhead; observed idle ~50 MB, peak ~120 MB.

### User Constraints
- **Requires personal Telegram account**: Must be phone-verified and capable of receiving OTP/2FA.
- **Requires BotFather interaction**: User must create a new bot via @BotFather (one-time, ~1 min).
- **Basic CLI comfort**: mention-mate.sh and mention-mate.ps1 require terminal access; not suitable for non-technical users without instructions.

## Architecture Summary

### System Overview
```
Telegram Groups (user in multiple groups)
         ↓
  [Userbot — Telethon client using user's credentials]
         ↓
    [Mention detector — regex/substring match on @username]
         ↓
  [Permalink resolver — discriminate Channel vs Chat vs User]
         ↓
  [Alert renderer — HTML + plain-text with user content escaped]
         ↓
 [Bot — aiohttp POST to api.telegram.org]
         ↓
  [User — DM push notification]
```

### Key Design Decisions
1. **Two-client architecture**: Userbot reads (MTProto), bot sends (HTTPS). Solves self-message notification gap.
2. **HTML mode primary, plain-text fallback**: Telegram's HTML parser is more lenient than Markdown; fallback ensures alerts never silently drop.
3. **Session file on disk**: Telethon stores encrypted session; persists across container restarts.
4. **Env-var contract**: 5 required variables (API_ID, API_HASH, MY_USERNAME, BOT_TOKEN, ALERT_CHAT_ID) cover all setup variations.
5. **Docker Compose default**: Simplifies user onboarding; single-service architecture (no separate DB, cache, queue).

## Dependencies

### Runtime
- **telethon 1.33.1**: Telegram client library (MTProto protocol).
- **aiohttp 3.9.5**: Async HTTP client for bot sendMessage API.
- **python-dotenv 1.0.1**: Load .env configuration.
- **Python 3.11+**: Async/await syntax, f-strings, type hints.

### Build & Deployment
- **Docker 20.10+**: Multi-stage Dockerfile, buildkit syntax.
- **GitHub Actions**: Release workflow (tag-triggered, multi-arch build, ghcr.io push).
- **bash / PowerShell**: mention-mate.sh and mention-mate.ps1 wizards for cross-platform install.

### External Services (Runtime)
- **api.telegram.org**: Telegram's MTProto server (for userbot) and HTTPS bot API (for alert send).
- **ghcr.io**: Docker image registry for distribution (one-time pull per user).

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Telegram API breaking changes | Userbot fails to read messages or send alerts | Pinned telethon version; subscribe to Telegram API announcements; test on pre-release tags. |
| User's machine offline | Mentions not detected (Telegram doesn't queue for offline clients) | Document as expected behavior in README.md → Troubleshooting; no fix (by design). |
| Session file lost or corrupted | User must re-authenticate (full wizard re-run) | Backup session file before major updates (mention-mate.sh update checks mtime); doc in README.md → Troubleshooting. |
| Bot token leaked (accidentally committed) | Attacker can send messages as the bot | .gitignore and .dockerignore enforce .env exclusion; wizard enforces chmod 600; README.md → Troubleshooting covers revocation (BotFather /revoke). |
| High CPU/memory under spam load | Container OOM-killed or CPU throttled | Resource limits (256 MB mem, 0.5 CPU) prevent runaway; backoff logic under Phase 1 hardens against API loops. |
| Network latency to api.telegram.org | Alerts delayed or timeout | aiohttp timeout defaults (5s) + exponential backoff (Phase 1) mitigate transient failures. |
| Regex attack on custom keywords (Phase 3) | ReDoS vulnerability if user enters pathological regex | Validate regex at config time; use timeout=1s on re.search() to prevent hangs. |

## Unresolved Questions

1. **Phase 1 logging level**: Should structured logs default to INFO or DEBUG? INFO (current assumption) requires less disk; DEBUG helps troubleshooting. Defer to user feedback post-v0.1.0.
2. **Phase 3 web UI framework**: FastAPI (Python, async-friendly) vs. Svelte + Vite (lighter frontend)? Defer pending feature request volume.
3. **Multi-account support**: Blocking non-goal now, but might reconsider if demand emerges. Requires session-per-account and process-per-bot architecture overhaul. Revisit in Phase 3 prioritization.
