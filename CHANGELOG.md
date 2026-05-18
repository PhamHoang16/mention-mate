# Changelog

All notable changes to MentionMate are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial public release scaffolding (Phase 2 Productization).

## [0.1.0] — TBD

First public release.

### Added
- **Distribution pipeline**: GitHub Actions workflow builds multi-arch Docker image (linux/amd64 + linux/arm64) and publishes to `ghcr.io/hoangp47/mention-mate` on every `v*.*.*` tag push.
- **Setup wizard**: Cross-platform interactive installer (`setup.sh` for Linux/macOS, `setup.ps1` for Windows) that handles Docker checks, credential prompting with inline validation, automatic chat_id discovery via Telegram getUpdates, round-trip test message verification, Telethon userbot authentication (phone + OTP + 2FA), and container startup.
- **Update wizard**: One-command upgrade flow (`update.sh` / `update.ps1`) with session file backup warning when older than 7 days.
- **Container image**: Multi-stage Dockerfile with non-root user (uid 1001), `HEALTHCHECK` directive verifying the Python entry process, and OCI annotations linking image to source repo.
- **Docker Compose template**: `docker-compose.yml` with `restart: unless-stopped`, volume mount for session persistence, resource limits (256MB memory, 0.5 CPU), and log rotation (10MB × 3 files).
- **Documentation**: README with quick install instructions, step-by-step SETUP guide, TROUBLESHOOTING reference covering common errors (Docker not running, network issues, auth failures, container startup problems, PowerShell ExecutionPolicy).

### Security
- `.dockerignore` and `.gitignore` ensure secrets (`.env`, Telethon session files) are excluded from both Docker images and Git history.
- Setup wizard writes `.env` and session files with `0600` permissions on POSIX, restrictive ACLs on Windows.
- chat_id is verified by round-trip test message before being persisted, preventing accidental delivery to wrong chats.
- Sensitive inputs (`TG_API_HASH`, `TG_BOT_TOKEN`) are read without terminal echo.

### Notes
- Core daemon logic (`main.py`) is unchanged from pre-release private version. This release adds only the distribution and installation layer.
- Pre-release prerequisites (token revocation, git history purge) must be completed before this version can be tagged.

[Unreleased]: https://github.com/hoangp47/mention-mate/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/hoangp47/mention-mate/releases/tag/v0.1.0
