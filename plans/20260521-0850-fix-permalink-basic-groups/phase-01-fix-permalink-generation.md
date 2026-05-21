---
phase: 1
title: Fix permalink generation
status: completed
priority: P1
effort: 30m
dependencies: []
---

# Phase 1: Fix permalink generation

## Overview

Replace the unconditional `t.me/c/{chat.id}/{event.id}` link with type-aware logic. Use `isinstance(chat, Channel)` to gate the link, prefer public-username URLs when available, and substitute a fallback hint for basic groups (`Chat`) and DMs (`User`) where no permalink scheme exists.

## Root cause (verified)

In Telethon 1.33.1 (`pyproject.toml`), `event.get_chat()` returns a typed object whose `.id` is the **bare unsigned** ID for every type:

| Telethon type | What it represents | `.id` shape | Permalink format |
|---|---|---|---|
| `User` | DM | positive (e.g. `123456789`) | none — no message permalink exists |
| `Chat` | basic group | positive (e.g. `123456789`) | **none** — basic groups have no `t.me/c/...` URL |
| `Channel` (`megagroup=True`) | supergroup | positive (e.g. `1234567890`) | `t.me/c/{id}/{msg_id}` works; `t.me/{username}/{msg_id}` if public |
| `Channel` (broadcast) | channel | positive | same as above |

So `str(chat.id).startswith('-100')` at `src/mention_mate/__main__.py:86` is **always False** — that branch is dead code. The link is uniformly `t.me/c/{positive_id}/{msg_id}`, which Telegram resolves correctly for Channels but not for basic groups (`Chat`), producing the "no permission" error the user sees on the groups they created (Telegram's default client creates basic `Chat` groups, not supergroups).

## Requirements

**Functional**
- Mentions in private supergroups → existing behaviour preserved (link works).
- Mentions in public supergroups/channels with a username → use the cleaner `t.me/{username}/{msg_id}` form.
- Mentions in basic groups (`Chat`) → no broken link in the alert. Replace the link block with a clearly-worded fallback so the user knows to navigate manually.
- Mentions in DMs (`User`) → same fallback as basic groups (defensive — the userbot can match a literal `@username` in a DM body, even though it's an unusual case).

**Non-functional**
- One file changed (`src/mention_mate/__main__.py`). No new dependencies. No new env vars. No new modules.
- HTML escaping for `sender_name`, `chat_title`, message `text`, and the link href must remain intact — never regress the safety the `html.escape()` calls already provide.
- The alert template (header line, blockquote, divider style introduced by the recent linter edit) is preserved structurally; only the final link line varies.

## Architecture

Two added imports + a small branch inside `handle_new_message`. No new helpers needed (the inline branch is short enough that pulling it into a function would add indirection without payoff — YAGNI).

```
event.get_chat() ──► chat (typed)
                       │
                       ├─ isinstance(chat, Channel)?
                       │     ├─ chat.username ──► t.me/{username}/{msg_id}
                       │     └─ otherwise     ──► t.me/c/{chat.id}/{msg_id}
                       │
                       └─ else (Chat / User) ──► no link, fallback hint
```

## Related Code Files

- Modify: `src/mention_mate/__main__.py`
  - Line 6: add `Chat`, `Channel` to the Telethon import (via `telethon.tl.types`).
  - Lines 85–88: replace the unconditional link construction + dead `-100` branch with type-aware logic.
  - Lines 98–112: split the link line in both `html_msg` and `plain_msg` into a `link_block_*` variable so the fallback message can substitute in.
- No test files (no `tests/` directory exists in this repo as of 2026-05-21). Verification is manual — see Success Criteria.

## Implementation Steps

1. **Add the type imports.** At the top of `src/mention_mate/__main__.py`, alongside the existing `from telethon import TelegramClient, events`, add:
   ```python
   from telethon.tl.types import Channel
   ```
   `Chat` and `User` don't need to be imported — `isinstance(chat, Channel)` is sufficient since everything else falls through to the "no permalink" branch.

2. **Replace the permalink construction (lines 85–88).** Drop both the unconditional assignment and the dead `-100` branch. New block (after `chat = await event.get_chat()` and the `chat_title` assignment):
   ```python
   # t.me/c/<id>/<msg_id> only works for Channel (supergroups, megagroups,
   # broadcast channels). Basic groups (Chat) and DMs (User) have no message
   # permalink format, so emit a fallback hint instead of a broken link.
   if isinstance(chat, Channel):
       username = getattr(chat, 'username', None)
       if username:
           message_link = f"https://t.me/{username}/{event.id}"
       else:
           message_link = f"https://t.me/c/{chat.id}/{event.id}"
   else:
       message_link = None
   ```

3. **Build link blocks for both formats.** After the existing `link_html = ...` line (which moves down inside an `if` now), produce two variables — one HTML, one plain — that the templates can drop in:
   ```python
   if message_link:
       link_html = html.escape(message_link, quote=True)
       link_block_html  = f'🔗 <a href="{link_html}">Open in Telegram →</a>'
       link_block_plain = f"🔗 {message_link}"
   else:
       link_block_html  = (
           f"💡 <i>Basic group — open Telegram and check "
           f"<b>{chat_html}</b> to find this message.</i>"
       )
       link_block_plain = (
           f"💡 Basic group — open Telegram and check "
           f"{chat_title} to find this message."
       )
   ```

4. **Substitute the link blocks into the templates.** Replace the final line of `html_msg` (`f'🔗 <a href="{link_html}">Open in Telegram →</a>'`) with `f"{link_block_html}"`, and the final line of `plain_msg` (`f"🔗 {message_link}"`) with `f"{link_block_plain}"`. Everything else in the templates — header, divider, blockquote — stays exactly as the recent linter edit left it.

5. **Smoke check the module loads.** Inside the container (or locally with deps installed):
   ```bash
   python -c "import mention_mate.__main__"
   ```
   Just confirms no import or syntax errors. Telethon must be importable for this to pass.

6. **Manual verification (no automated test exists).**
   - In a **supergroup** the user is a member of (current working case): get someone to `@mention` the user. Receive the alert in the bot DM. Tap "Open in Telegram →" → it jumps to the message. ✅ Regression check.
   - In a **basic group** the user created (the broken case): repeat. Alert arrives with the `💡 Basic group …` fallback line instead of a `🔗` link. No "no permission" error possible because there is no clickable link. ✅ Bug fix.
   - In a **public supergroup with a username**, if one is available: confirm the link becomes `t.me/<username>/<msg_id>` rather than `t.me/c/<id>/<msg_id>`. (Optional — only if such a group is reachable for testing.)

## Todo List

- [ ] Import `Channel` from `telethon.tl.types` in `__main__.py`.
- [ ] Replace lines 85–88 with the `isinstance(chat, Channel)` branch (drops the dead `-100` check).
- [ ] Introduce `link_block_html` / `link_block_plain` and use them in the templates.
- [ ] Run `python -c "import mention_mate.__main__"` (or rebuild the Docker image) and confirm clean import.
- [ ] Verify in a real supergroup mention — regression check.
- [ ] Verify in a real basic-group mention — bug fix check; fallback hint appears, no broken link.

## Success Criteria

- [ ] No `-100` substring check remains in the file (dead code removed).
- [ ] Mentions from supergroups still produce a working `🔗 Open in Telegram →` link.
- [ ] Mentions from basic groups produce the `💡 Basic group …` fallback line — no broken link, no "no permission" error possible.
- [ ] Public supergroups/channels with a `username` produce the prettier `t.me/{username}/{msg_id}` form.
- [ ] No regression in HTML escaping (sender, chat title, message body, link href all still pass through `html.escape`).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Telethon type hierarchy differs across versions (e.g. `Channel` not the actual class returned by `get_chat()`) | Low — pinned to `telethon==1.33.1` in `pyproject.toml`, behavior is well-documented for this version | Alert would silently drop into the fallback branch for supergroups too | Smoke test in step 5 surfaces obvious import issues. Manual regression check in supergroup catches behavioral drift. If a future Telethon bump changes the hierarchy, the test plan in Success Criteria catches it. |
| User finds the "Basic group" fallback message confusing | Low | Cosmetic — UX paper cut | Wording is explicit ("open Telegram and check <group>"); not blocking. Can be iterated based on user feedback. |
| Forgetting to update the `html.escape` call after refactoring the link variables | Low if implementation steps are followed in order | Could break HTML rendering or worse, allow injection from a malicious chat title | Step 3 reproduces the existing `html.escape(message_link, quote=True)` verbatim; the chat-title and sender-name escapes upstream are untouched. |
| Public channel with username collision with reserved t.me paths (e.g. `joinchat`, `c`, `addstickers`) | Negligible | Broken link for one corner case | Telegram already prevents these usernames, so `chat.username` is safe to interpolate. |

## Security Considerations

The new branch only injects `chat.username` into a URL. Telegram username rules already restrict it to `[A-Za-z][A-Za-z0-9_]{4,31}` — no URL-encoding required. The link still goes through `html.escape(..., quote=True)` before landing in the HTML payload, so the existing XSS-preventing path is preserved.

No new env vars, no new outbound endpoints, no change to the auth/session flow.

## Next Steps

After merge:
- The alert format change is user-visible. Worth mentioning in `CHANGELOG.md` under the next version's "Fixed" section (e.g. `Fixed: 'Open in Telegram' link is now omitted with a fallback hint for basic groups, where no permalink scheme exists`).
- Consider a small README note (`README.md → Troubleshooting`) along the lines of "Basic groups don't expose direct message permalinks — the alert shows a fallback hint instead. Upgrade the group to a supergroup in Telegram (Settings → Group Type → Public/Private) for clickable links."
