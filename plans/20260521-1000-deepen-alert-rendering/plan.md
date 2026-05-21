---
title: 'Deepen alert rendering: extract permalink resolver + pure renderer'
description: >-
  Pull message-template construction and Telethon-type-aware permalink logic out
  of the async `handle_new_message` event handler in
  `src/mention_mate/__main__.py`. Two thin modules with small interfaces:
  `permalink_resolver.py` (chat → URL|None) isolates the only Telethon-typed
  concern, `alert_renderer.py` (primitives → html/plain) becomes a pure function
  the handler calls.
status: completed
priority: P2
branch: master
tags:
  - refactor
  - architecture
  - testability
blockedBy: []
blocks: []
created: '2026-05-21T04:42:42.691Z'
createdBy: 'ck:plan'
source: skill
---

# Deepen alert rendering: extract permalink resolver + pure renderer

## Overview

The event handler in `src/mention_mate/__main__.py` currently does six things in one async function: filter incoming messages, resolve sender/chat, compute permalink (with Telethon-type discrimination), build HTML + plain templates, dispatch, log. The recent permalink fix added ~30 lines to a function that was already the most complex in the file, and the alert format has been iterated 3 times in the last session alone — the **format-churn lives where the test surface is hardest to reach**.

This plan extracts two small modules:

1. **`permalink_resolver.py`** — single function `resolve_message_link(chat, message_id) -> str | None`. The only place in the codebase that knows about Telethon's `Channel` type and `t.me/c/`, `t.me/{username}/` URL forms. Tiny, but the seam is what lets the renderer stay pure (no Telethon import).
2. **`alert_renderer.py`** — single function `render_alert(*, sender_name, chat_title, message_text, message_link) -> tuple[str, str]`. Pure: four strings (or `None` for `message_link`) in, two strings (HTML + plain) out. No Telethon, no aiohttp, no module globals.

The event handler in `__main__.py` shrinks to orchestration: pull primitives off the Telethon event, call `resolve_message_link`, call `render_alert`, call `send_alert`. Format changes, new icons, expandable blockquote tweaks — all land in `alert_renderer.py` with a tested interface. Permalink-format additions (deep links, t.me/+invite tokens, future Telegram URL schemes) land in `permalink_resolver.py` in isolation.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Extract permalink resolver](./phase-01-extract-permalink-resolver.md) | Completed |
| 2 | [Extract pure alert renderer](./phase-02-extract-pure-alert-renderer.md) | Completed |

## Dependencies

**Plans:** none unfinished. The just-completed plan `20260521-0850-fix-permalink-basic-groups` introduced the very `isinstance(chat, Channel)` block this refactor lifts into its own module — chronologically a follow-up, not a blocking dependency (frontmatter `blockedBy` only tracks unfinished plans).

**Code touchpoints (all in `src/mention_mate/__main__.py`):**

- Lines 7 (`from telethon.tl.types import Channel`) → moves to `permalink_resolver.py`.
- Lines 86–98 (permalink branch) → moves to `permalink_resolver.py`.
- Lines 100–134 (HTML escape + link block + html_msg + plain_msg construction) → moves to `alert_renderer.py`.
- Lines 136–139 (dispatch + success log) → stays in handler.
- `auth.py` is untouched.

**Test infra:** none currently. Phase 1 introduces a `tests/` directory with `pytest` + the first two test modules covering exactly these two new seams. No mocking of Telethon needed for either — both interfaces are designed so they don't require it.

## Out of scope

- **Bot API client (Candidate 3 from the architecture review).** Marginal value (one transport, deep-ish already). Deferred until a second transport actually appears.
- **Config injection (env globals → dataclass).** Standard 12-factor refactor with no urgency; today the renderer is the only thing benefiting from injectability, and Phase 2 reaches it via function args, not config rewiring.
- **Type-narrowing the `getattr(sender, 'first_name', None)` / `getattr(chat, 'title', None)` chains.** Defensive-coding cleanup, not architectural.
- **Format redesign.** This refactor MUST emit byte-identical alerts for every input the handler can currently produce. Future tone/icon/structure changes happen in a separate ticket — the point of the refactor is to make those changes cheap.
- **Test coverage of the existing handler path.** The handler stays thin enough that mocking Telethon for end-to-end is not worth the cost. Coverage focuses on the two new modules.

## Success criteria for the whole plan

- [ ] `src/mention_mate/__main__.py` has no `html.escape` calls and no `t.me/` string literals — both belong elsewhere now.
- [ ] `src/mention_mate/__main__.py` has no `from telethon.tl.types import Channel` — only `permalink_resolver.py` does.
- [ ] `pytest tests/` runs and passes on a clean checkout with `pip install -e .[dev]` (where `dev` adds `pytest`).
- [ ] At least 6 tests across the two new modules: supergroup-with-username, supergroup-without-username, basic-group (Chat), DM (User), HTML escape of `<script>` in sender + chat title, fallback line for `message_link=None`.
- [ ] Manual smoke test: send `@mention` in one supergroup + one basic group. The alerts that arrive are **textually identical** to those produced before the refactor (modulo the no-permalink fallback message, which already shipped in the prior plan).
- [ ] The Docker image still builds, starts, and emits an alert end-to-end.

## Validation Log

### Session 1 — 2026-05-21

**Verification pass:** Light tier (2 phases). 11 claims sampled across `__main__.py` line numbers, `pyproject.toml`, missing `tests/` directory, and unmodified `auth.py`. **All VERIFIED**, 0 FAILED, 0 UNVERIFIED.

**Decisions:**

- **D1 — Output contract.** Byte-identical with **inline expected strings inside the test file** (no separate `tests/golden/*.txt` fixtures). Rationale: removes copy-paste-from-terminal failure mode. Phase 2 updated accordingly. _<!-- Updated: Validation Session 1 - drop tests/golden/, use inline expected strings -->_
- **D2 — Test fakes.** Tiny `@dataclass` fakes for `Channel` / `Chat` / `User`, not `unittest.mock.MagicMock(spec=...)`. Rationale: dataclasses fail loudly on attribute typos and have no third-party magic. Phase 1 updated accordingly. _<!-- Updated: Validation Session 1 - dataclass fakes instead of MagicMock -->_
  - **Implementation amendment (post-cook):** discovered Telethon's `Channel.__init__` requires many positional args, making `@dataclass(...)` subclasses awkward. Used `Channel.__new__(Channel) + setattr` instead — the resulting object IS a real `Channel` for `isinstance()` purposes, every attribute is explicitly named (same typo-safety win as a dataclass), no fake class needed. Same intent, cleaner path. See `tests/test_permalink_resolver.py` docstring + `_fake_channel` helper.
- **D3 — Test dependency placement.** `[project.optional-dependencies].dev = ["pytest>=8"]` in `pyproject.toml`. Rationale: maximum toolchain compatibility (pip, uv, poetry, hatch), production image unaffected. No change from plan-as-written.

### Whole-Plan Consistency Sweep — Session 1

After propagating D1 and D2 into the phase files, re-read `plan.md` + both `phase-*.md` files. Searched for stale references to "MagicMock", "golden fixtures", "tests/golden/", and "tests/golden" terms.

- Phase 1 still references dataclass fakes consistently.
- Phase 2 no longer references `tests/golden/` in any section (Implementation Steps, Related Code Files, Risk Assessment, Todo List, Success Criteria).
- `plan.md` Out-of-scope and Success-criteria sections unchanged — they never named the fixture format. The "At least 6 tests" line uses the post-Phase-1 count and is still correct (6 + 7 = 13).

**Status:** No unresolved contradictions. Plan is ready for implementation.
