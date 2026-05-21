---
phase: 2
title: Extract pure alert renderer
status: completed
priority: P2
effort: 1.5h
dependencies:
  - 1
---

# Phase 2: Extract pure alert renderer

## Overview

Move the HTML + plain-text alert templates (currently lines 100–134 of `__main__.py`) into `src/mention_mate/alert_renderer.py` as a single pure function `render_alert`. After Phase 1, this can take primitives — `sender_name`, `chat_title`, `message_text`, `message_link: str | None` — without importing Telethon. The function returns `(html_msg, plain_msg)`. The handler becomes orchestration only.

## Why this matters

This is where the architecture review identified the highest-value seam. Three signals:

1. **Format churn lives here.** The alert template has been edited 3+ times in the last session (icons, divider style, `<blockquote expandable>`, header line). Today every tweak requires re-reading the entire async handler.
2. **Test surface is hardest to reach.** Verifying a format change end-to-end means restarting the container, mentioning yourself in a real Telegram chat, opening the bot DM. After this phase, format changes become `assert render_alert(...) == (...)`.
3. **Phase 3 expansion is coming.** Roadmap mentions digest mode, action buttons, multi-keyword highlighting. Each adds a branch in the renderer. Adding them inside an async event handler that also does I/O is how a 200-line file becomes a 600-line file.

## Requirements

**Functional**
- Public function:
  ```python
  def render_alert(
      *,
      sender_name: str,
      chat_title: str,
      message_text: str,
      message_link: str | None,
  ) -> tuple[str, str]:
      """Return (html_msg, plain_msg). Pure: no I/O, no globals."""
  ```
- Output MUST be byte-identical to the current `__main__.py` for any given set of inputs. The refactor changes architecture, not the user-visible payload.
- HTML escape is performed inside `render_alert` — callers pass raw strings, the renderer handles safety. Plain-text path uses raw values (Telegram Bot API doesn't interpret markup in plain mode).
- `message_link=None` produces the `💡 Basic group — open Telegram and check <b>{chat_title}</b> to find this message.` fallback (HTML) and its plain-text equivalent. Same wording the current handler emits.

**Non-functional**
- One new module file (`src/mention_mate/alert_renderer.py`), ~50 LOC including docstrings.
- No imports beyond `html` (stdlib). No Telethon, no aiohttp, no `os`.
- Keyword-only args (the leading `*` in the signature). Forces callers to be explicit at the call site — readability over brevity.
- Type-hinted on every parameter and the return.

## Architecture

```
   handle_new_message                     (Telethon-aware orchestration)
       │
       │ pull primitives off event
       ▼
   sender_name, chat_title, message_text  (strings, untrusted)
   message_link = resolve_message_link(chat, event.id)  (Phase 1, str | None)
       │
       ▼
   html_msg, plain_msg = render_alert(...)               (pure, Phase 2)
       │
       ▼
   await send_alert(http_session, html_msg, plain_msg, message_text)   (transport)
```

**Interface depth:** 4 primitives in, 2 strings out. Hides: HTML escaping, link-block vs fallback-block selection, header line, divider style, `<blockquote expandable>` wrapper, anchor-tag construction, plain-text mirror. That's roughly 30 lines of decisions behind 4 keyword args.

**Deletion test:** removing this module would push every one of those 30 lines back into the handler. Complexity concentrates here, doesn't just move — earns its keep.

**Why keyword-only.** Positional `render_alert(sender, chat, text, link)` is shorter but the ordering is meaningless to a future reader who doesn't already know it. `render_alert(sender_name=..., chat_title=..., message_text=..., message_link=...)` self-documents at every call site and resists silent breakage if argument order ever changes.

**Why one function, not a class.** No state, no instance configuration, no need for multiple methods. A class here would be ceremony. If a renderer ever needs configuration (themed icons, i18n, brand colours), it'll become a class then — YAGNI now.

## Related Code Files

- **Create:** `src/mention_mate/alert_renderer.py` — pure rendering module.
- **Modify:** `src/mention_mate/__main__.py`:
  - Remove the `import html` line (it lives in the renderer now; handler doesn't escape anything).
  - Add: `from mention_mate.alert_renderer import render_alert`.
  - Delete lines 100–134 (the entire `# HTML mode: ...` block through the end of `plain_msg = ...`).
  - Replace with a single call: `html_msg, plain_msg = render_alert(sender_name=sender_name, chat_title=chat_title, message_text=text, message_link=message_link)`.
- **Create:** `tests/test_alert_renderer.py` — expected `(html_msg, plain_msg)` outputs live as **inline Python f-string literals inside the test file**. No separate fixture directory. _<!-- Updated: Validation Session 1 - drop tests/golden/, use inline expected strings -->_
- **Untouched:** `permalink_resolver.py` (Phase 1 output), `auth.py`, `__init__.py`, Docker setup, scripts.

## Implementation Steps

1. **Compute the expected outputs from the current code, inline in the test file.** Before touching `__main__.py`, run the **current** template construction (lines 100–134) in a Python REPL with a chosen set of synthetic inputs, capture the resulting `(html_msg, plain_msg)` pair, and paste them as Python f-string literals into the top of `tests/test_alert_renderer.py`. _<!-- Updated: Validation Session 1 - inline expected strings, no fixture directory -->_

   Recipe (run in a `python` shell from the project root, with `pip install -e .` active so `import mention_mate.__main__` works):

   ```python
   import html
   sender_name = "Hoang"
   chat_title = "Backend Team"
   text = "hey @duong check this please"
   message_link = "https://t.me/c/12345/99"
   sender_html = html.escape(sender_name)
   chat_html = html.escape(chat_title)
   text_html = html.escape(text)
   link_html = html.escape(message_link, quote=True)
   link_block_html = f'🔗 <a href="{link_html}">Open in Telegram →</a>'
   link_block_plain = f"🔗 {message_link}"
   html_msg = (
       f"👋 <b>{sender_html}</b> mentioned you in <i>{chat_html}</i>\n"
       f"━━━━━━━━━━━━━━━\n"
       f"<blockquote expandable>{text_html}</blockquote>\n"
       f"━━━━━━━━━━━━━━━\n"
       f"{link_block_html}"
   )
   # repeat for plain_msg, and again for message_link=None case
   print(repr(html_msg))
   ```

   Copy the `repr()`-printed strings (which preserve every space, newline, and Unicode codepoint explicitly) into the test file as `_EXPECTED_HTML_SUPERGROUP = "..."` constants. No filesystem fixtures, no copy-paste between terminal panes.

2. **Create `alert_renderer.py`.** Skeleton:
   ```python
   """Render mention alerts as paired (HTML, plain-text) messages.

   Pure: no I/O, no Telethon, no module globals. Callers pass primitives;
   the module handles HTML escaping and the link/fallback split.
   """
   import html


   _DIVIDER = "━━━━━━━━━━━━━━━"


   def render_alert(
       *,
       sender_name: str,
       chat_title: str,
       message_text: str,
       message_link: str | None,
   ) -> tuple[str, str]:
       """Return (html_msg, plain_msg) ready to send via the Telegram Bot API."""
       sender_html = html.escape(sender_name)
       chat_html = html.escape(chat_title)
       text_html = html.escape(message_text)

       if message_link:
           link_html = html.escape(message_link, quote=True)
           link_block_html = f'🔗 <a href="{link_html}">Open in Telegram →</a>'
           link_block_plain = f"🔗 {message_link}"
       else:
           link_block_html = (
               f"💡 <i>Basic group — open Telegram and check "
               f"<b>{chat_html}</b> to find this message.</i>"
           )
           link_block_plain = (
               f"💡 Basic group — open Telegram and check "
               f"{chat_title} to find this message."
           )

       html_msg = (
           f"👋 <b>{sender_html}</b> mentioned you in <i>{chat_html}</i>\n"
           f"{_DIVIDER}\n"
           f"<blockquote expandable>{text_html}</blockquote>\n"
           f"{_DIVIDER}\n"
           f"{link_block_html}"
       )
       plain_msg = (
           f"👋 {sender_name} mentioned you in {chat_title}\n"
           f"{_DIVIDER}\n"
           f"{message_text}\n"
           f"{_DIVIDER}\n"
           f"{link_block_plain}"
       )
       return html_msg, plain_msg
   ```
   Notice the divider hoisted to a module constant — small DRY win, makes future divider tweaks one-line.

3. **Wire the handler.** In `src/mention_mate/__main__.py`:
   - Remove `import html` from the top of the file.
   - Add `from mention_mate.alert_renderer import render_alert` near the other module imports.
   - Delete lines 100–134 (everything from `# HTML mode: ...` through `plain_msg = (...)`).
   - Insert in their place:
     ```python
     html_msg, plain_msg = render_alert(
         sender_name=sender_name,
         chat_title=chat_title,
         message_text=text,
         message_link=message_link,
     )
     ```
   - The handler is now: filter → resolve chat/sender → resolve permalink → render → dispatch → log. Roughly 30 lines shorter.

4. **Write the test cases.** In `tests/test_alert_renderer.py`:

   | Test name | Input | Asserts |
   |---|---|---|
   | `test_supergroup_with_link_matches_expected` | sender="Hoang", chat="Backend Team", text="hey @duong check this please", link="https://t.me/c/12345/99" | `render_alert(...) == (_EXPECTED_HTML_SUPERGROUP, _EXPECTED_PLAIN_SUPERGROUP)` (inline f-string constants captured in step 1) |
   | `test_basic_group_without_link_matches_expected` | same primitives, link=`None` | `render_alert(...) == (_EXPECTED_HTML_BASIC, _EXPECTED_PLAIN_BASIC)` |
   | `test_html_escape_sender_name` | sender=`"<script>alert(1)</script>"`, link=`"http://x"` | html_msg contains `&lt;script&gt;` and not `<script>` |
   | `test_html_escape_chat_title_in_fallback` | chat=`"</b><b>x"`, link=`None` | html_msg shows `&lt;/b&gt;&lt;b&gt;x` inside the fallback bold span; original brackets do NOT appear |
   | `test_html_escape_message_text` | text=`"5 < 10 & 10 > 5"`, link=`"x"` | html_msg shows `5 &lt; 10 &amp; 10 &gt; 5` |
   | `test_link_href_quote_escape` | link=`'http://x.com/"><script>'` (impossible in practice but defence-in-depth) | the `href="..."` content is escaped (no raw `"`, `>`) |
   | `test_plain_text_uses_raw_strings` | sender=`"<script>"`, text=`"5 < 10"`, link=`"x"` | plain_msg contains `<script>` and `5 < 10` verbatim (plain mode = no parsing, raw is correct) |

5. **Run tests.** `pytest tests/` — Phase 1's six tests + Phase 2's seven tests = 13 green.

6. **Verify the import chain.** `python -c "from mention_mate.__main__ import main"` — confirms the trimmed `__main__.py` still loads cleanly.

7. **Manual end-to-end check.** Rebuild the Docker image: `docker compose build && docker compose up -d`. Trigger one mention in a supergroup and one in a basic group. Both alerts MUST be byte-identical to what you saw before this refactor (the inline `_EXPECTED_*` constants in the test file are the authoritative reference if you need to grep-compare).

## Todo List

- [ ] Capture expected output for supergroup + basic-group cases as inline f-string constants in `tests/test_alert_renderer.py` (via `repr()` in a REPL — see Implementation Step 1).
- [ ] Create `src/mention_mate/alert_renderer.py` with the `render_alert` function.
- [ ] Update `src/mention_mate/__main__.py`: drop `import html` + 30 lines of template logic, add one `render_alert(...)` call.
- [ ] Write 7 tests in `tests/test_alert_renderer.py`.
- [ ] `pytest tests/` — 13 tests pass (6 from Phase 1 + 7 from Phase 2).
- [ ] `python -c "from mention_mate.__main__ import main"` — clean import.
- [ ] Manual supergroup mention → alert byte-identical to pre-refactor.
- [ ] Manual basic-group mention → alert byte-identical to pre-refactor (still emits the `💡 Basic group …` fallback line from prior plan).

## Success Criteria

- [ ] `alert_renderer.py` exists, contains `render_alert(*, ...)`, imports only `html` (stdlib).
- [ ] `__main__.py` no longer contains `html.escape`, no Telegram emoji literals (🔔/👋/🔗/💡), no divider characters, no `<blockquote` or `<b>` strings.
- [ ] `__main__.py` `handle_new_message` shrinks by ~30 lines net.
- [ ] All 13 tests pass; inline expected strings match byte-for-byte.
- [ ] Manual end-to-end run produces alerts identical to pre-refactor output for both chat types.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Inline expected strings captured incorrectly (whitespace, hidden Unicode in divider, emoji width) | Low-Medium — `repr()` in a REPL is more deterministic than copy-paste between terminal panes, but f-string escapes inside the test file are still hand-edited | Tests pass but production alert visibly different | Use `repr()` in the capture step (forces explicit `\n`, `\u`-codes); for any line that comes back surprising, paste it AS the `repr()` output and let Python re-parse it. Code-review the diff with the human eye on whitespace. |
| Format drift snuck in during the user's iteration last session (the `<blockquote expandable>` tweak, divider counts) | Medium — confirmed in this session | Tests freeze a version that's not the latest user-edited one | Run the REPL capture AFTER reading the current state of `__main__.py` lines 100–134 — not from memory or earlier commits. |
| Keyword-only signature breaks somewhere if a caller is added later that forgets the `=` | Low — `__main__.py` is the only caller for the foreseeable future | TypeError at startup, loud failure | Loud is good. The signature choice is deliberate. |
| Inline expected strings couple too tightly to format — every future tweak forces test-file updates | Medium-high — that's literally the point | Friction on format changes | Yes. The friction is "update the inline `_EXPECTED_*` constants per format change". That's the correct contract: prove the change is intentional. If iterative tweaking gets tedious, add `syrupy` later — don't pre-optimize. |
| The hoisted `_DIVIDER` constant creates a temptation to make it configurable | Low | Premature abstraction | Don't accept it. One divider, one constant. Configurability lands the day there's a second use. |

## Security Considerations

The HTML escape chain is preserved exactly: `sender_name`, `chat_title`, `message_text` all go through `html.escape(...)`; `message_link` goes through `html.escape(..., quote=True)` before landing in `href="..."`. No change to the safety posture.

One subtle improvement: by centralising escape calls inside the renderer, future format additions can't *accidentally* skip the escape — the inputs simply aren't available as raw strings outside the `if message_link:` branch. The "escape at the boundary" pattern is enforced by module structure rather than convention.

## Next Steps

After this phase merges, the architecture is at a defensible stopping point. Specifically:

- **Don't** continue into the bot-alerter deepening (Candidate 3 from the architecture review). One transport, one adapter — still premature.
- **Don't** continue into config injection. No tests need it yet.
- **Do** add `CHANGELOG.md` entry under "Internal" / "Refactor" for this version: "Internal: extracted alert rendering into `alert_renderer.py` and permalink resolution into `permalink_resolver.py` for testability."
- **Do** consider a follow-up plan when Phase 3 features land (digest mode, action buttons) — those will exercise the new seam, and the test fixtures will catch regressions.
