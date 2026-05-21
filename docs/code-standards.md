# MentionMate — Code Standards & Development Guidelines

## File Organization

### Python Modules
- **Location**: `src/mention_mate/` (package root).
- **Naming**: snake_case (Python convention). Examples: `__main__.py`, `auth.py`, `alert_renderer.py`, `permalink_resolver.py`.
- **Size limit**: Keep under 200 LOC per file for readability. Refactor into separate modules if exceeded.
  - Example: `__main__.py` was split to extract `alert_renderer.py` (64 LOC) and `permalink_resolver.py` (33 LOC) for testability.
- **Entry point**: `src/mention_mate/__main__.py` serves as the daemon entry point (`python -m mention_mate`).
- **Module dependency rules**: See section below.

### Shell Scripts
- **Location**: `scripts/` directory.
- **Naming**: kebab-case. Examples: `mention-mate.sh`, `mention-mate.ps1`.
- **Windows variant**: Parallel `.ps1` file with identical logic, PowerShell syntax.
- **Permissions**: Mark executable: `chmod +x scripts/*.sh` (enforced in git pre-commit).

### Documentation Files
- **Location**: `docs/` directory (public user docs) and repo root (LICENSE, README, CHANGELOG).
- **Naming**: UPPERCASE.md or descriptive kebab-case.md. Examples: `README.md`, `project-overview-pdr.md`.
- **Size limit**: Keep individual files under 800 LOC. Split large topics into subdirectories (e.g., `docs/guides/` for multi-part tutorials).

### Docker & Config Files
- **Naming**: Conventional (Dockerfile, docker-compose.yml, .env.example, pyproject.toml).
- **Location**: Repository root.

---

## Python Style Guide

### Language Version
- **Minimum**: Python 3.11+
- **Rationale**: f-strings, async/await, type hint syntax, match statements.

### Type Hints
- **Current state**: Existing code (v0.1.0) is untyped (legacy from pre-release internal version).
- **New code (Phase 1+)**: Add type hints to all function signatures and module-level variables.
  - Example: `async def send_alert(session: aiohttp.ClientSession, html_msg: str, plain_msg: str, original_text: str) -> None:`
- **Return types**: Always declare; use `-> None` for side-effect functions.
- **Optional/Union**: Use `Optional[T]` for nullable types; `Union[T1, T2]` for multiple types. Prefer `T | None` (3.10+) style in new code.

### Async/Await Patterns
- **Event handlers**: All Telethon event handlers are `async def` (required by telethon API).
- **HTTP calls**: Use `aiohttp.ClientSession` for all HTTP operations. Always use context manager or explicit cleanup.
  ```python
  async with session.post(url, json=payload) as resp:
      data = await resp.json()
  ```
- **Timeouts**: Declare explicit timeouts (default aiohttp is 300s; MentionMate uses 5s implicit default). Example: `aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=5))`.

### Error Handling
- **Principle**: Never silently drop errors. Log, fallback, or re-raise.
- **Pattern 1 — Try with fallback**: Try primary method, catch, fallback to secondary, log reason.
  ```python
  try:
      await _post_message(session, html_msg, parse_mode="HTML")
  except Exception as e:
      print(f"⚠️  HTML send failed ({e}); falling back to plain text")
      await _post_message(session, plain_msg)
  ```
- **Pattern 2 — Log and re-raise**: If error is unrecoverable.
  ```python
  except Exception as e:
      print(f"❌ ALERT LOST. Original text: {original_text!r}. Error: {e}")
      raise
  ```
- **Logging**: Use `print()` for now (Phase 1 will add structured logging). Include emoji for severity: 🚀 (info), ✅ (success), ⚠️ (warn), ❌ (error).

### String Formatting
- **Use f-strings**: Always. Examples: `f"@{MY_USERNAME}".lower()`, `f"https://t.me/c/{chat_id}/{msg_id}"`.
- **HTML escaping**: Use `html.escape()` on all user-generated content before inserting into HTML templates.
  ```python
  sender_html = html.escape(sender_name)
  html_msg = f"<b>From:</b> {sender_html}"
  ```

### Imports
- **Organization**: Standard library, third-party, local imports in that order.
  ```python
  import os
  import html
  import asyncio
  
  import aiohttp
  from telethon import TelegramClient, events
  from dotenv import load_dotenv
  
  from . import config  # future: local imports
  ```
- **Explicit imports**: Avoid `from X import *`.

### Constants
- **Naming**: UPPER_SNAKE_CASE.
- **Scope**: Module-level constants at the top (after imports).
  ```python
  API_ID = int(os.getenv('TG_API_ID'))
  BOT_TOKEN = os.getenv('TG_BOT_TOKEN')
  MENTION_TOKEN = f"@{MY_USERNAME}".lower()
  ```
- **Environment-dependent**: Load from env-vars at module init, not inside functions.

---

## Shell Script Standards

### Bash (mention-mate.sh)

#### Safety & Robustness
- **Header**: Always include `#!/bin/bash` and set `set -euo pipefail`.
  ```bash
  #!/bin/bash
  set -euo pipefail  # Exit on error, undefined vars, pipe failures
  ```
- **Variable expansion**: Quote all variables to prevent word-splitting: `"$var"`, not `$var`.
- **Conditionals**: Always quote variables: `if [[ -z "$var" ]]`, not `if [ -z $var ]`.

#### Logging Functions
- **Color codes**: Define color variables for readability.
  ```bash
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m'  # No Color
  
  log_ok() { echo -e "${GREEN}✅ $*${NC}"; }
  log_err() { echo -e "${RED}❌ $*${NC}" >&2; }
  log_warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
  log_step() { echo -e "\n${GREEN}[STEP $1]${NC} $2"; }
  ```

#### User Input Validation
- **Regex matching**: Always validate user input before use.
  ```bash
  prompt_with_validation() {
      local prompt="$1" regex="$2" max_attempts=3
      while (( attempts < max_attempts )); do
          read -p "$prompt: " value
          if [[ "$value" =~ $regex ]]; then
              echo "$value"
              return 0
          fi
          ((attempts++))
          log_err "Invalid input. $max_attempts attempts remaining."
      done
      return 1
  }
  ```
- **Integer validation**: Use regex `^[0-9]+$`.
- **Hex validation**: Use regex `^[a-f0-9]{40}$` for API_HASH.
- **Alphanumeric + underscore**: Use regex `^[a-zA-Z0-9_]+$` for username.

#### Atomic File Operations
- **Never overwrite in place**. Write to temp file, then rename.
  ```bash
  tmp_env=$(mktemp)
  cat > "$tmp_env" <<EOF
  TG_API_ID=$api_id
  TG_API_HASH=$api_hash
  EOF
  chmod 600 "$tmp_env"
  mv "$tmp_env" .env  # Atomic rename
  ```

#### Project Root Detection
- **Function**: Walk up directory tree to find docker-compose.yml.
  ```bash
  __locate_project_root() {
      local dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
      while [[ "$dir" != "/" ]]; do
          [[ -f "$dir/docker-compose.yml" ]] && { echo "$dir"; return 0; }
          dir="$(dirname "$dir")"
      done
      log_err "Could not find project root (docker-compose.yml)"
      return 1
  }
  ```

#### Error Handling
- **Check command success**: Always validate critical commands.
  ```bash
  run_command_or_exit() {
      if ! "$@"; then
          log_err "Command failed: $*"
          exit 1
      fi
  }
  
  run_command_or_exit docker --version
  ```

### PowerShell (mention-mate.ps1)

#### Safety & Error Handling
- **Header**: Set error action preference.
  ```powershell
  $ErrorActionPreference = "Stop"
  $ProgressPreference = "SilentlyContinue"
  ```
- **Variable expansion**: Always use `$var` (PowerShell is more lenient, but be explicit).
- **Escape paths**: Use `-Path`, `-LiteralPath` parameters (avoid string concatenation).

#### Logging Functions
- **Color output**: Use `Write-Host -ForegroundColor`.
  ```powershell
  function Log-Ok { Write-Host "✅ $args" -ForegroundColor Green }
  function Log-Err { Write-Host "❌ $args" -ForegroundColor Red }
  function Log-Warn { Write-Host "⚠️  $args" -ForegroundColor Yellow }
  function Log-Step { Write-Host "`n[STEP $($args[0])] $($args[1])" -ForegroundColor Green }
  ```

#### Validation & Input
- **Regex matching**: Use `-match` operator.
  ```powershell
  if ($apiId -match "^\d+$") { ... }
  ```
- **Integer parsing**: Use `[int]::TryParse()` for safe conversion.

#### File Operations
- **Atomic writes**: Use `-Encoding UTF8` and explicit temp file handling.
  ```powershell
  $tmpEnv = New-TemporaryFile
  Set-Content -Path $tmpEnv -Value $envContent -Encoding UTF8
  Move-Item -Path $tmpEnv -Destination ".env" -Force
  icacls ".env" /inheritance:r /grant:r "${env:USERNAME}:F"
  ```

#### Path Handling
- **Project root**: Resolve-Path to avoid string manipulation.
  ```powershell
  $projectRoot = (Split-Path -Parent $PSScriptRoot) | Resolve-Path
  ```

---

## Module Dependency Rules

To maintain clean seams and testability, enforce these module boundaries:

| Module | Allowed Imports | Purpose |
|--------|-----------------|---------|
| `permalink_resolver` | `telethon.tl.types` (only this module), stdlib | Resolve message URLs by chat type |
| `alert_renderer` | stdlib `html` only | Pure formatter; no framework deps |
| `__main__` | `telethon`, `aiohttp`, `.alert_renderer`, `.permalink_resolver` | Orchestration layer |
| `auth` | `telethon`, stdlib | Setup-only login flow |

**Rationale:**
- `permalink_resolver` is the **only** place where `telethon.tl.types` is imported. Future URL schemes (deep-links, invite tokens) go here.
- `alert_renderer` is pure: same input always produces byte-identical output. No side effects, no mocks needed in tests.
- Format changes (emoji, HTML tags, link text) stay in `alert_renderer`.
- `__main__` is thin: imports both helpers + Telethon/aiohttp, coordinates event loop → link → render → send.

---

## Docker Standards

### Dockerfile Best Practices
- **Multi-stage builds**: Separate build-time dependencies from runtime (reduces image size).
- **Non-root user**: Always run as non-root (uid/gid != 0). Example: `RUN useradd -m -r -u 1001 tgbot`.
- **Minimal base image**: Use `-slim` variants (e.g., `python:3.11-slim`) over `-alpine` (avoids libc incompatibility).
- **Layer caching**: Order Dockerfile commands so frequently-changed instructions come last.
  - Avoid: `COPY . .` early, then build. Instead: copy config → install deps → copy source.
- **Labels**: Include OCI annotations (`org.opencontainers.image.*`) for discoverability.
- **Healthcheck**: Define `HEALTHCHECK` directive (Docker Compose can reference it).
- **Permissions**: Chown before dropping to non-root user to avoid permission issues at startup.

### Docker Compose Standards
- **Single service**: Keep single responsibility (one app per compose file; multi-service setups use separate files or orchestration).
- **Named services**: Use descriptive names (`bot`, not `web` or `service`).
- **Environment**: Load from `.env` file (never hardcode secrets).
- **Volumes**: Mount volumes explicitly; document purpose in comments.
- **Healthcheck**: Include health check (duplicates or references Dockerfile; helps orchestration).
- **Resource limits**: Always set `deploy.resources.limits` and `.reservations` (prevents runaway containers).
- **Logging**: Configure log rotation (json-file with max-size, max-file) to prevent disk bloat.
- **Restart policy**: Choose `unless-stopped` (survives daemon restart) or `no` (manual control).

---

## Commit Message Standards

### Format
Follow **Conventional Commits** (https://www.conventionalcommits.org/):
```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- **feat**: New feature.
- **fix**: Bug fix.
- **docs**: Documentation only (README, guides, comments).
- **refactor**: Code restructure without feature or fix (e.g., extract function).
- **test**: Test-related changes (unit tests, integration tests, test fixtures).
- **chore**: Build, CI, dependency updates, tooling.

### Rules
- **Scope** (optional): Component or area (e.g., `wizard`, `daemon`, `alert-handler`).
- **Subject**: Imperative mood ("add", not "added"). Lowercase. Max 50 characters.
- **Body**: Explain *why*, not *what*. Wrap at 72 characters. Link to issues: `Fixes #123`.
- **NO AI references**: Never mention "Claude", "AI", "LLM", or tools used.
- **Example**:
  ```
  feat(wizard): add regex validation for API_HASH
  
  Prevents invalid credentials from being persisted. Regex checks
  for 40 hex characters before allowing write to .env.
  
  Fixes #42
  ```

### `.claude/` Directory
- **Exception**: Do NOT use `chore` or `docs` prefix for changes to `.claude/` files.
- **Reason**: CI filters out `chore` and `docs` commits; `.claude/` changes are infrastructure, not product.
- **Format**: Use `fix`, `feat`, or `refactor` as appropriate.
  ```
  refactor(.claude/skills): extract validation helper into common lib
  ```

---

## Testing Standards

### Current State (v0.1.0)
- **Test scaffold**: 13 tests covering new seams (`permalink_resolver`, `alert_renderer`).
  - Install: `pip install -e ".[dev]"` (pytest>=8 from optional-dependencies in pyproject.toml).
  - Run: `pytest tests/`.
  - Coverage: New modules fully covered; Phase 1 goal: expand to ≥80% full codebase.

### Faking Telethon Types in Tests
- **Pattern**: Use `Cls.__new__(Cls) + setattr` to create real Telethon type instances without invoking `__init__`.
- **Why not MagicMock?** Silent attribute access hides typos (e.g., misspelled `message_id`).
- **Why not dataclass subclassing?** Telethon's `__init__` requires many positional args; inheritance fails.
- **Example**:
  ```python
  channel = Channel.__new__(Channel)
  setattr(channel, 'id', 12345)
  setattr(channel, 'username', 'teamalpha')
  ```

### Phase 1 Plan

#### Unit Tests
- **Framework**: pytest + pytest-asyncio (for async test support).
- **Location**: `tests/unit/` directory.
- **Coverage target**: ≥80% (measured by coverage.py).
- **Test modules**:
  - `test_mention_detection.py`: Verify @mention substring matching (case-insensitive).
  - `test_alert_formatting.py`: Verify HTML escaping, plain-text fallback, link generation.
  - `test_config_loading.py`: Verify env-var parsing, validation, error handling.

#### Integration Tests
- **Framework**: pytest with docker-compose fixtures (or similar orchestration).
- **Location**: `tests/integration/` directory.
- **Scenario**: Full alert pipeline (message injection → detection → formatting → API post).
- **Mock dependencies**: Mock Telegram API responses (getUpdates, sendMessage).

#### Test Patterns
- **Async tests**: Use `@pytest.mark.asyncio` decorator.
  ```python
  @pytest.mark.asyncio
  async def test_send_alert_html_success():
      session = aiohttp.ClientSession()
      await send_alert(session, html_msg, plain_msg, original)
      # assert mock called correctly
  ```
- **Fixtures**: Use pytest fixtures for setup/teardown (session factories, mock clients).
- **Mocking**: Use `unittest.mock` or `pytest-mock` for external API mocks.

#### CI/CD Integration
- **Pre-commit hook**: Run linting (flake8 or ruff) + type checking (mypy).
- **GitHub Actions**: Run full test suite on PR + before merge (enforce ≥80% coverage).

---

## Linting & Code Quality

### Current Tools
- None (Phase 1 will add).

### Planned (Phase 1)
- **Linter**: ruff (fast, zero-config, handles flake8 + isort + pyupgrade rules).
- **Type checker**: mypy or pyright (validate type hints).
- **Formatter**: black or ruff format (consistent style, opinionated).
- **Configuration**: `.flake8`, `pyproject.toml [tool.mypy]`, or `.pre-commit-config.yaml`.

### Style Preferences (Guidance for Phase 1+)
- **Line length**: 100 characters (longer than black's default 88, but still readable).
- **Import sorting**: isort style (stdlib, third-party, local).
- **Trailing commas**: Use in multi-line structures (easier diffs).
- **Function spacing**: 2 blank lines between top-level functions/classes; 1 line inside classes.

---

## Security Standards

### Input Validation
- **Environment variables**: Validate type (int, string) and format (regex for sensitive fields).
  - `TG_API_ID`: Must be integer.
  - `TG_API_HASH`: Must be 40 hex characters.
  - `TG_BOT_TOKEN`: Format `<id>:<35-char secret>` (validated in wizard, not daemon).
  - `TG_MY_USERNAME`: Alphanumeric + underscore, no leading @.
  - `TG_ALERT_CHAT_ID`: Must be integer (negative or positive).

### Data Sanitization
- **User-generated content**: All sender names, group titles, message text escaped via `html.escape()` before inclusion in HTML alert.
- **URLs**: Escape special characters when embedding in HTML href attribute: `html.escape(url, quote=True)`.

### Secrets Management
- **.env file**: gitignored, dockerignored, chmod 600 (POSIX) / ACL-restricted (Windows).
- **Session file** (`data/mentions_session.session`): gitignored, dockerignored, chmod 600.
- **CI/CD secrets**: Use GitHub Secrets (never hardcoded in workflows).
- **Container security**: Run as non-root user (uid 1001); no setuid/setgid binaries; minimal base image.

### Network Security
- **HTTPS only**: Telegram bot API enforced by Telegram (aiohttp POST to api.telegram.org).
- **Timeout enforcement**: Explicit timeout on aiohttp requests (prevent indefinite hangs).
- **Telethon session**: Encrypted on disk; revocable via Telegram Settings → Devices.

---

## Documentation Standards

### Code Comments
- **Purpose**: Explain *why*, not *what*. Code is readable; intent is not.
- **Avoid**: "Increment counter" (obvious from `count += 1`).
- **Prefer**: "Retry loop: skip this sender to avoid self-message notification bug (Telegram issue #12345)".
- **Plan references**: Do NOT reference plan artifacts (phase numbers, finding codes, audit labels). Explain the rationale directly.
  - Bad: `# per F13 advisory-lock fix`
  - Good: `# org-scoped advisory lock serializes concurrent reassigns`

### Docstrings
- **Module docstring**: 1-3 sentences at the top of each .py file.
  ```python
  """Telethon interactive login — run once during setup.
  
  The wizard invokes this as: docker run ... python -m mention_mate.auth
  """
  ```
- **Function docstring** (Phase 1+): Brief description + param types + return type.
  ```python
  async def send_alert(session: aiohttp.ClientSession, html_msg: str, plain_msg: str, original_text: str) -> None:
      """Send mention alert via bot API. Try HTML; fallback to plain text. Never silently drop."""
  ```

### User Documentation
- **Location**: `docs/` directory.
- **Format**: Markdown with clear headings, code blocks, tables.
- **Audience**: End-users (not developers). Assume minimal CLI familiarity.
- **Examples**: Every feature gets a real code example (not pseudocode).
- **Troubleshooting**: Link error codes to fixes with step-by-step instructions.

---

## Naming Conventions Summary

| Category | Style | Examples |
|----------|-------|----------|
| Python modules | snake_case | `__main__.py`, `auth.py`, `alert_handler.py` |
| Python classes | PascalCase (future) | `TelegramHandler`, `AlertFormatter` |
| Python functions | snake_case | `send_alert()`, `handle_new_message()` |
| Python constants | UPPER_SNAKE_CASE | `API_ID`, `BOT_TOKEN`, `MENTION_TOKEN` |
| Shell scripts | kebab-case | `mention-mate.sh`, `mention-mate.ps1` |
| Documentation files | UPPERCASE.md or kebab-case.md | `README.md`, `project-overview-pdr.md` |
| Environment variables | UPPER_SNAKE_CASE | `TG_API_ID`, `TG_BOT_TOKEN` |
| Docker images | kebab-case (registry convention) | `ghcr.io/phamhoang16/mention-mate` |
| Docker services | kebab-case or lowercase | `bot` (in compose) |
| GitHub Actions workflows | kebab-case | `release.yml`, `ci-test.yml` (future) |

---

## Unresolved Questions

1. **Mypy strictness**: Use `strict = true` or allow some lenient mode? Defer pending Phase 1 type annotation PR.
2. **Test framework choice**: pytest vs. unittest? Recommend pytest (more flexible, async support). Confirm in Phase 1 plan.
3. **Linter aggressiveness**: Use ruff with defaults, or customize rules (e.g., ignore E501 line length)? Defer pending CI config PR.
