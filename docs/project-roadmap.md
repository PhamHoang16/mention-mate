# MentionMate — Project Roadmap

Living document tracking project phases, milestones, and progress. Last updated: 2026-05-20.

---

## Phase 1: Hardening

**Status:** 🚀 In Progress (started during v0.1.0)

**Goal:** Improve observability, resilience, and test coverage. No new user-facing features.

**Timeline:** TBD (v0.2.0-beta target: ~6–8 weeks post-v0.1.0).

### Deliverables

#### 1. Structured Logging
- **Scope**: Replace print() statements with JSON-formatted logs (timestamp, severity, context).
- **Acceptance Criteria**:
  - All internal events logged: daemon start, message received, mention detected, alert sent, error.
  - Log levels: INFO (normal flow), WARN (retries), ERROR (failures).
  - JSON schema: `{"timestamp": "...", "level": "INFO", "event": "mention_detected", "sender": "...", "group": "...", ...}`.
  - Configuration: log level switchable via env var (default INFO).
- **Files affected**: `src/mention_mate/__main__.py`, `src/mention_mate/auth.py`.
- **Dependencies**: Python stdlib logging (no external lib).

#### 2. HTTP Health Check Endpoint
- **Scope**: Replace pgrep-based healthcheck with REST `/healthz` endpoint.
- **Acceptance Criteria**:
  - GET `/healthz` returns 200 OK with JSON: `{"status": "healthy", "uptime_seconds": ..., "alerts_sent": ...}`.
  - Endpoint listens on `localhost:8080` (configurable via env var, default 8080).
  - Accessible from inside container (docker compose healthcheck uses container DNS).
  - Healthcheck interval: 30s (from docker-compose.yml).
  - Track uptime and alert count in memory (reset on restart).
- **Files affected**: `src/mention_mate/__main__.py` (add aiohttp server), `Dockerfile` (expose port, update HEALTHCHECK), `docker-compose.yml` (update healthcheck).
- **Dependencies**: aiohttp (already a runtime dep; add route handler).

#### 3. Retry & Backoff Logic
- **Scope**: Prevent bot API hammering; gracefully degrade on transient failures.
- **Acceptance Criteria**:
  - Exponential backoff on sendMessage POST failure: 1s, 2s, 4s, 8s, then give up.
  - Circuit-breaker: After 10 consecutive failures, disable alerts for 5 minutes, then retry.
  - Log each retry attempt with backoff delay.
  - Transient errors (connection timeout, 5xx): retry. Permanent errors (400 Bad Request, invalid token): fail immediately.
- **Files affected**: `src/mention_mate/__main__.py` (update send_alert function).
- **Dependencies**: None (implement with asyncio.sleep, manual counter).

#### 4. Unit Tests
- **Scope**: Test core logic (mention detection, alert formatting, HTML escaping, permalink resolution).
- **Status**: ✅ **First scaffold complete** (13 tests in place).
  - `tests/test_permalink_resolver.py`: 6 tests covering Channel (with/without username), basic groups, DMs, None cases.
  - `tests/test_alert_renderer.py`: 7 tests covering HTML escaping, plain-text rendering, link/fallback handling, byte-identical rendering.
  - Install: `pip install -e ".[dev]"` (pytest>=8 from optional-dependencies).
  - Run: `pytest tests/`.
- **Remaining Phase 1 Coverage**:
  - Mention detection: case-insensitive match, media captions fallback, non-matches.
  - Config loading: env var parsing, validation, missing required vars.
  - HTTP errors: 400, 429, 5xx; verify backoff/circuit-breaker.
  - Integration test: full alert pipeline end-to-end.
- **Acceptance Criteria**:
  - ≥80% code coverage (measured by coverage.py).
  - All tests pass on CI (GitHub Actions).
  - Performance: test suite runs in <10 seconds.
- **Files affected**: `tests/` directory (already created), `pyproject.toml` (pytest>=8 already added).
- **Dependencies**: pytest, pytest-asyncio, coverage.py.

#### 5. Integration Tests
- **Scope**: Test full alert pipeline (message injection → detection → formatting → API post).
- **Acceptance Criteria**:
  - Scenario: Mock Telegram API, inject NewMessage event, verify sendMessage POST.
  - Tools: pytest with docker-compose fixtures (or testcontainers).
  - All tests pass on CI.
  - Performance: integration tests run in <30 seconds.
- **Files affected**: New `tests/integration/` directory.
- **Dependencies**: pytest, pytest-docker (or similar).

#### 6. Dependency & Security Scanning
- **Scope**: Add CVE scanning to release pipeline; pin all dependencies.
- **Acceptance Criteria**:
  - GitHub Actions workflow runs `pip-audit` or `safety check` on every commit.
  - Blocks release if high/critical CVEs detected.
  - All dependencies pinned to exact versions in `pyproject.toml` (no floating ranges like `>=1.0`).
  - Lock file (optional but recommended): `requirements.lock` generated from `pyproject.toml`.
- **Files affected**: `.github/workflows/ci-test.yml` (new), `pyproject.toml` (pin versions).
- **Dependencies**: pip-audit or safety (dev tools).

#### 7. Pre-Commit Hooks
- **Scope**: Run linting and type checking locally before push.
- **Acceptance Criteria**:
  - Tools: ruff (linter), mypy (type checker), black or ruff format (formatter).
  - Config: `.pre-commit-config.yaml` and `pyproject.toml` [tool.*].
  - Checks: code style, unused imports, type errors, trailing whitespace.
  - All team members use hooks (documented in CONTRIBUTING.md).
- **Files affected**: New `.pre-commit-config.yaml`, update `pyproject.toml`.
- **Dependencies**: pre-commit framework, ruff, mypy, black.

### Success Criteria
- Test coverage ≥80%.
- All Phase 1 deliverables merged and released as v0.2.0-beta.
- CI/CD pipeline fully automated (no manual testing steps).
- Zero known CVEs in release build.

### Timeline Estimate
- Research & planning: 1–2 weeks.
- Implementation: 3–4 weeks (parallel streams: logging, tests, healthcheck, backoff).
- Review & hardening: 1–2 weeks.
- **Total: ~6–8 weeks post-v0.1.0**.

---

## Phase 2: Productization

**Status:** ✅ In Progress / Released as v0.1.0 (planned).

**Goal:** Distribute as a polished, installable product with end-user docs and wizards.

**Completion:** v0.1.0 public release (TBD, pending pilot feedback).

### Deliverables (Completed or In Progress)

#### ✅ Docker Multi-Arch Build
- Linux/amd64, Linux/arm64 (supports x86-64 servers and Apple Silicon Macs).
- Published to ghcr.io/phamhoang16/mention-mate.

#### ✅ GitHub Actions Release Pipeline
- Triggered on `v*.*.*` git tag.
- Builds multi-arch image, pushes with semver tags (v0.1.0, 0.1, latest).
- Creates GitHub Release with source zip + changelog extract.

#### ✅ Setup Wizard & Update (Cross-Platform, Unified)
- `scripts/mention-mate.sh` (Linux/macOS, ~430 LOC): Unified setup/update with subcommand interface (setup, update, auto-detect).
- `scripts/mention-mate.ps1` (Windows, ~370 LOC): PowerShell equivalent.
- Setup: 12-step flow (Docker check → prompt credentials → pull image → discover chat_id → Telethon auth → start container).
- Update: Version detection, optional session backup (if mtime >7 days), compose pull/recreate.
- Real-time input validation with regex.
- Atomic .env writes (chmod 600 / ACL-restricted).

#### ✅ End-User Documentation
- `README.md` (≈225 LOC): Install section (OS-specific Docker setup, credential retrieval, wizard execution, troubleshooting section with 6 error codes ERR-DIST-001 to 006).

#### ✅ Internal Documentation (This Phase)
- `docs/project-overview-pdr.md`: Problem, solution, target users, goals/non-goals, roadmap, constraints, risks.
- `docs/codebase-summary.md`: Directory tree, entry points, modules, dependencies, runtime behavior.
- `docs/code-standards.md`: File naming, Python style, shell conventions, Docker best practices, commit rules, testing standards.
- `docs/system-architecture.md`: Component diagram, data flows, security model, deployment topology, API contracts.
- `docs/project-roadmap.md`: This document (phases, milestones, success metrics).

#### ✅ README & Changelog
- `README.md` (172 LOC): Public overview, feature table, install instructions, common commands.
- `CHANGELOG.md`: Keep-a-Changelog format, v0.1.0 release notes.

#### ✅ Container & Config
- `Dockerfile`: Multi-stage, non-root user, healthcheck, OCI labels.
- `docker-compose.yml`: Single-service, resource limits, log rotation, health check.
- `.env.example`: 5 required variables with inline documentation.

#### ✅ License & Git Hygiene
- `LICENSE` (MIT).
- `.gitignore` / `.dockerignore`: Exclude .env, session files, test artifacts.
- Pre-release cleanup: token revocation, git history sanitization (if needed).

### Success Criteria
- ≥95% setup wizard success rate (no manual intervention required).
- ≤15 min from download to first alert (per README.md target).
- Every env var, error code, CLI command documented with examples.
- Zero manual steps in tag → image push → release flow.

### Status
- **ETA for v0.1.0 release**: TBD (pending pilot feedback and pre-release cleanup).
- **Current milestone**: All deliverables merged and tested; awaiting public release decision.

---

## Phase 3: Feature Expansion

**Status:** ⏳ Planned (post-v0.2.0, pending user feedback).

**Goal:** Add advanced features requested by users; position for broader adoption.

**Timeline:** TBD (likely Q3–Q4 2026 or later).

### Candidate Features

#### 1. Multi-Keyword Detection (High Priority)
- **Scope**: Allow users to create rules matching multiple keywords, regex patterns, or team mentions.
- **Examples**:
  - `@hoangp47` (existing behavior).
  - `\@team-alpha` (team mentions).
  - `regex: (urgent|critical|FIRE)` (severity keywords).
  - `project:viettel` (custom tags).
- **Acceptance Criteria**:
  - Web UI or CLI tool to add/edit/delete rules.
  - Rules stored in SQLite DB (first database for the project).
  - Mention detection uses regex matcher (with timeout=1s to prevent ReDoS).
  - Default rule: `@{TG_MY_USERNAME}` (backward compatible).
- **Effort**: Medium (~2–3 weeks).
- **Blockers**: Web UI framework choice (defer decision).

#### 2. Digest Mode (Medium Priority)
- **Scope**: Batch mentions into hourly/daily digest instead of real-time spam.
- **Options**:
  - Option A: Suppress real-time alerts; send digest at 9 AM daily.
  - Option B: Real-time + digest summary at end of day.
- **Acceptance Criteria**:
  - Configurable via web UI or env var.
  - SQLite stores pending mentions (sender, group, timestamp, link).
  - Scheduled job sends digest (aioscheduler or APScheduler).
  - User can mark digest items as read.
- **Effort**: Medium (~2 weeks).
- **Risk**: Increased storage (database grows unbounded without pruning).

#### 3. Inline Action Buttons (Medium Priority)
- **Scope**: Add Telegram inline buttons to alert messages (Mark Read, Snooze 1h, Mute Group).
- **Example Alert**:
```
🔔 You were mentioned!
...
[✓ Mark Read] [🔕 Snooze 1h] [🤐 Mute Group]
```
- **Acceptance Criteria**:
  - Callback handlers for button presses (requires bot webhook or polling).
  - Update SQLite to track mention state (unread/read/snoozed).
  - Snooze: suppress further alerts from same group for 1 hour.
  - Mute: suppress alerts from that group permanently (stored as user preference).
- **Effort**: Medium (~2 weeks).
- **Complexity**: Adds webhook/polling logic; requires more robust error handling.

#### 4. Web UI for Configuration (Low Priority, High Polish)
- **Scope**: Optional dashboard for managing keywords, digest settings, muted groups, etc.
- **Technologies**: FastAPI backend (Python) + Svelte/React frontend (optional static HTML).
- **Acceptance Criteria**:
  - Listens on `http://localhost:8081` (or port from env var).
  - Endpoints: GET/POST keywords, GET/POST digest settings, GET muted groups, DELETE mention.
  - Authentication: none (assumes local machine; if remote deployment desired, add simple token auth).
  - Responsive design (mobile-friendly for quick config changes).
- **Effort**: High (~4–5 weeks).
- **Consideration**: Adds complexity and potential attack surface; maybe keep optional.

#### 5. Webhook Forwarding (Low Priority, Integrations)
- **Scope**: Forward mentions to incident management systems (Pagerduty, Opsgenie, Slack).
- **Example**:
  - User creates rule: `urgent → forward to Pagerduty`.
  - Daemon POSTs mention details to external webhook.
- **Acceptance Criteria**:
  - Web UI to add webhook endpoints.
  - Retry logic for webhook failures (exponential backoff).
  - Payload format: JSON with sender, group, text, link, timestamp.
- **Effort**: Medium (~2 weeks, mostly boilerplate).
- **Consideration**: May be better served by IFTTT/Zapier integration (no code change needed).

#### 6. Database & Persistence Layer (Enabler for 1, 2, 3)
- **Scope**: Move from stateless daemon to persistent storage (SQLite).
- **Schema**:
  - `mentions` (id, sender_id, group_id, text, timestamp, state: unread|read|snoozed, link).
  - `rules` (id, pattern, enabled).
  - `muted_groups` (id, group_id, muted_until).
- **Acceptance Criteria**:
  - Schema versioning + migrations (alembic or custom).
  - Data integrity: transactions, foreign keys.
  - Backup/restore documentation.
  - Retention policy: delete mentions older than 90 days.
- **Effort**: Medium (~1–2 weeks).
- **Risk**: Adds operational complexity; users must back up DB.

### Feature Priority Matrix

| Feature | Impact | Effort | Priority | Planned For |
|---------|--------|--------|----------|-------------|
| Multi-keyword | High (user requests) | Medium | 1 | v0.3.0 (Q3 2026) |
| Digest mode | Medium (reduces spam) | Medium | 2 | v0.4.0 (Q4 2026) |
| Inline buttons | Medium (better UX) | Medium | 3 | v0.4.0 (Q4 2026) |
| Web UI | Medium (convenience) | High | 4 | v1.0.0 (Q1 2027, optional) |
| Webhook forwarding | Low (integrations) | Medium | 5 | v1.0.0+ (post-release) |
| Database layer | N/A (enabler) | Medium | 0 | Before multi-keyword (v0.3.0 prep) |

### Success Criteria (for Phase 3 as a whole)
- ≥30% of users create ≥1 custom keyword rule (opt-in beta feedback).
- If digest enabled: ≥10% adoption.
- If buttons implemented: ≥5% usage rate.
- No database locks or corruption under normal usage.

### Timeline Estimate
- v0.3.0 (database + multi-keyword): 4–5 weeks (starting Q3 2026).
- v0.4.0 (digest + buttons): 4–5 weeks (starting Q4 2026).
- v1.0.0 (web UI, optional): 5–6 weeks (Q1 2027 or defer).

---

## Post-Phase 3 Ideas (Speculative)

These are not committed; listed for long-term vision and user feedback.

### Self-Hosted Variants
- **Kubernetes Helm chart**: Deploy MentionMate on K8s clusters.
- **Docker Swarm template**: Multi-node deployments.
- **Cloud SaaS option** (if demand): Hosted version for users unwilling to self-host (conflicts with no-cloud goal; only if explicitly requested).

### Mobile Companion App
- Native iOS / Android app for offline mention history, quick muting, snooze management.
- Syncs with local daemon via local network API (no cloud).

### Desktop Client (Electron)
- System tray icon with mention history and quick actions.
- Local only; no cloud sync.

### Enterprise Features (Hypothetical)
- Multi-user/team support (one daemon per team).
- Audit logs for compliance.
- LDAP/SSO integration for authentication.
- Rate limiting and quotas per user.

---

## Known Blockers & Risks

| Blocker | Impact | Resolution |
|---------|--------|-----------|
| Telegram API breaking changes | Daemon fails to read/send messages | Subscribe to announcements; pin telethon version; test on pre-release tags |
| User's machine offline | Mentions not detected | Document as expected behavior; no fix (by design) |
| Session file corruption | User must re-authenticate | Backup strategy in mention-mate.sh update; recovery docs in README.md → Troubleshooting |
| Multi-account support demand (Phase 3) | Architecture blocker | Defer or design multi-process variant (complex) |
| Database migration complexity | Upgrade risk for v0.3.0+ | Implement robust migration tooling early (Phase 1?) |

---

## Metrics & Success Tracking

### v0.1.0 (Productization)
- [ ] Setup wizard success rate ≥95%.
- [ ] Average install time ≤15 minutes.
- [ ] GitHub releases viewed ≥100 times.
- [ ] No critical bugs reported in first month.

### v0.2.0 (Hardening, TBD Q2–Q3 2026)
- [ ] Test coverage ≥80%.
- [ ] Zero CVEs in dependency audit.
- [ ] HTTP `/healthz` endpoint passes all health checks.
- [ ] Backoff logic prevents bot API hammering (load test confirms <1 req/sec peak).

### v0.3.0 (Multi-Keyword, TBD Q3 2026)
- [ ] ≥30% of users create custom rules (beta feedback).
- [ ] Database schema stable (no migration issues).
- [ ] Regex timeout=1s enforced (no ReDoS attacks in fuzzing).

### v0.4.0 (Digest + Buttons, TBD Q4 2026)
- [ ] Digest mode: ≥10% adoption.
- [ ] Button UX: ≥5% engagement (Mark Read, Snooze).
- [ ] No data loss under stress testing (10K mentions/day).

---

## Release Schedule (Tentative)

| Version | Phase | Goal | ETA | Status |
|---------|-------|------|-----|--------|
| **v0.1.0** | Phase 2 | Productization (distribution, wizard, docs) | TBD (May–Jun 2026) | ✅ In progress |
| **v0.2.0-beta** | Phase 1 | Hardening (logging, tests, healthcheck, backoff) | TBD (Jul–Sep 2026) | ⏳ Planned |
| **v0.3.0-beta** | Phase 3 | Database + multi-keyword | TBD (Sep–Oct 2026) | ⏳ Planned |
| **v0.4.0-beta** | Phase 3 | Digest + inline buttons | TBD (Oct–Nov 2026) | ⏳ Planned |
| **v1.0.0** | Phase 3+ | Stable release (web UI optional) | TBD (Q1 2027+) | ⏳ Planned |

---

## Maintenance & Support

### Ongoing (All Phases)
- **Issue triage**: 1× per week, prioritize bugs over features.
- **Dependency updates**: Monthly review of CVE alerts; patch critical issues immediately.
- **User support**: Track issues on GitHub; respond to setup/troubleshooting questions in issues (no separate support channel yet).

### Communication Channels
- GitHub Issues: Bug reports, feature requests, discussions.
- README.md: End-user documentation (install, troubleshooting).
- Internal docs (docs/): Developer reference.

---

## Unresolved Questions

1. **v0.1.0 release timing**: Awaiting pilot feedback and pre-release cleanup. Should we do closed beta or go public directly?
2. **User feedback collection**: How to gather feature requests post-v0.1.0? GitHub Discussions? Community chat?
3. **Phase 1 vs Phase 3 priority**: Should hardening (Phase 1) or features (Phase 3) take priority post-release? Recommend Phase 1 first (stability before features).
4. **Web UI necessity**: Required for v1.0.0, or optional nice-to-have? Defer pending user surveys.
5. **Multi-account support**: Frequently requested? If yes, redesign for multi-process architecture. If no, document as non-goal.
