---
phase: 1
title: Extract permalink resolver
status: completed
priority: P2
effort: 1h
dependencies: []
---

# Phase 1: Extract permalink resolver

## Overview

Lift the `isinstance(chat, Channel)` discriminator + URL construction out of `handle_new_message` into a single-purpose module `src/mention_mate/permalink_resolver.py`. This is the **only place** in the codebase that imports from `telethon.tl.types`. Phase 2's renderer depends on this seam — it lets the renderer accept a plain `str | None` and stay Telethon-free.

## Why this phase first

The renderer (Phase 2) is the big payoff, but it can only stay pure if it doesn't receive a Telethon-typed `chat` object. Phase 1 establishes that decoupling — it's the smaller, lower-risk change that unlocks the larger one. Order matters: doing Phase 2 first would force the renderer to either import Telethon (defeating the point) or accept already-resolved primitives that don't exist yet (defeating Phase 2 testability).

## Requirements

**Functional**
- Public function `resolve_message_link(chat, message_id: int) -> str | None`.
  - For `Channel` (megagroup, supergroup, broadcast) with truthy `username`: returns `https://t.me/{username}/{message_id}`.
  - For `Channel` without `username` (or empty string): returns `https://t.me/c/{chat.id}/{message_id}`.
  - For any other type (`Chat`, `User`, or `None`): returns `None`.
- Behaviour MUST match the current `__main__.py` lines 86–98 byte-for-byte for every observable case.

**Non-functional**
- One new file (`src/mention_mate/permalink_resolver.py`), ~25 lines.
- The `from telethon.tl.types import Channel` import lives **only** in this module after the refactor.
- Module is pure — no I/O, no async, no logging, no globals.
- Type-hinted (`Channel | None` accepted for the `chat` parameter via `typing.Any` or a `Protocol` — see Architecture for the trade-off).

## Architecture

```
                    handle_new_message
                        │
                        ▼
       chat = await event.get_chat()
                        │
                        ▼
       message_link = resolve_message_link(chat, event.id)   ◄── new seam
                        │
                        ▼
       (Phase 2: render_alert(..., message_link=message_link))
```

**Interface depth:** small. Two params in, `str | None` out. Hides: the Telethon type check, two URL forms, the empty-string username corner case, the "no permalink for Chat/User" rule. Future Telegram URL schemes (deep-links, invite tokens) land here without touching the handler.

**Typing trade-off.** Two options:

1. **Pragmatic:** `def resolve_message_link(chat: object, message_id: int) -> str | None`. `isinstance(chat, Channel)` narrows inside. Lets callers pass anything (matches how `event.get_chat()` returns a union type at the Telethon API surface). **Pick this** — it's what the existing handler already does implicitly, and the seam doesn't need to advertise the input type.
2. **Strict:** `def resolve_message_link(chat: Channel | Chat | User | None, ...) -> str | None`. Pulls in two more Telethon imports the module doesn't otherwise need. Defeats the "only this module touches `telethon.tl.types`" goal.

We pick option 1.

## Related Code Files

- **Create:** `src/mention_mate/permalink_resolver.py` — new module.
- **Modify:** `src/mention_mate/__main__.py`:
  - Remove line 7: `from telethon.tl.types import Channel`.
  - Add new import: `from mention_mate.permalink_resolver import resolve_message_link`.
  - Replace lines 86–98 with a single call: `message_link = resolve_message_link(chat, event.id)`.
- **Create:** `tests/__init__.py` (empty), `tests/test_permalink_resolver.py` — first test file in the repo.
- **Modify:** `pyproject.toml` — add `[project.optional-dependencies]` block with `dev = ["pytest>=8"]`. Don't add to base `dependencies` (production image stays slim).
- **Untouched:** `auth.py`, `__init__.py`, scripts, Docker setup.

## Implementation Steps

1. **Scaffold the module.** Create `src/mention_mate/permalink_resolver.py` with one function and one import. Pseudocode:
   ```python
   """Resolve a Telegram message permalink for a chat object.

   Centralises Telethon's t.me URL discrimination so the rest of the
   codebase can stay free of telethon.tl.types imports.
   """
   from telethon.tl.types import Channel


   def resolve_message_link(chat, message_id: int) -> str | None:
       """Return a t.me link for the message, or None if no scheme exists.

       Channel (supergroup / megagroup / broadcast channel) → t.me URL.
       Chat (basic group) and User (DM) → None; Telegram has no permalink
       format for those.
       """
       if not isinstance(chat, Channel):
           return None
       username = getattr(chat, "username", None)
       if username:
           return f"https://t.me/{username}/{message_id}"
       return f"https://t.me/c/{chat.id}/{message_id}"
   ```
   Add `"""Module purpose"""` docstring at the top. Function docstring states the contract.

2. **Wire the handler.** In `src/mention_mate/__main__.py`:
   - Remove the `from telethon.tl.types import Channel` import on line 7.
   - Near the other module imports (after `from telethon import TelegramClient, events`), add: `from mention_mate.permalink_resolver import resolve_message_link`.
   - Replace lines 86–98 (the `if isinstance(chat, Channel):` branch) with:
     ```python
     message_link = resolve_message_link(chat, event.id)
     ```
   - Keep the `# t.me/c/...` comment block above it OR (preferred) move that explanatory comment into `permalink_resolver.py`'s module docstring — the "why" belongs with the code, not at the call site.

3. **Add `tests/` scaffolding.** Create `tests/__init__.py` (empty file) and `tests/test_permalink_resolver.py`.

4. **Write the test cases.** Use **tiny `@dataclass` fakes**, one per Telethon type the resolver might encounter. `resolve_message_link` only does `isinstance(chat, Channel)` + attribute access on `.username` and `.id`, so a 3-line dataclass per type is faithful AND fails loudly on attribute-name typos (unlike `MagicMock`, which would silently return a new `MagicMock` for any attribute).

   <!-- Updated: Validation Session 1 - dataclass fakes instead of MagicMock -->

   Test scaffolding (top of `tests/test_permalink_resolver.py`):

   ```python
   from dataclasses import dataclass
   from telethon.tl.types import Channel, Chat, User
   from mention_mate.permalink_resolver import resolve_message_link

   # Tiny fakes — dataclasses that share the relevant attributes with the real
   # Telethon types so isinstance(...) + attribute access behave correctly.
   @dataclass
   class FakeChannel(Channel):  # subclass so isinstance(fake, Channel) is True
       id: int = 0
       username: str | None = None

   @dataclass
   class FakeChat(Chat):
       id: int = 0

   @dataclass
   class FakeUser(User):
       id: int = 0
   ```

   If subclassing Telethon types proves awkward (their `__init__` may demand additional args), fall back to bare `dataclass` + monkey-patching `isinstance` in tests via `pytest.MonkeyPatch` — but try subclassing first.

   Cases to cover:

   | Test name | Input | Expected output |
   |---|---|---|
   | `test_supergroup_with_username` | `FakeChannel(id=12345, username="ai_team")`, `message_id=99` | `"https://t.me/ai_team/99"` |
   | `test_supergroup_without_username` | `FakeChannel(id=12345, username=None)`, `message_id=99` | `"https://t.me/c/12345/99"` |
   | `test_supergroup_empty_string_username` | `FakeChannel(id=12345, username="")`, `message_id=99` | `"https://t.me/c/12345/99"` (empty string is falsy → bare-ID branch) |
   | `test_basic_group_returns_none` | `FakeChat(id=12345)`, `message_id=99` | `None` |
   | `test_dm_returns_none` | `FakeUser(id=42)`, `message_id=99` | `None` |
   | `test_none_chat_returns_none` | `chat=None`, `message_id=99` | `None` |

5. **Add pytest as a dev dep.** In `pyproject.toml`, add (alongside the existing `[project]` block):
   ```toml
   [project.optional-dependencies]
   dev = ["pytest>=8"]
   ```
   Run locally with: `pip install -e ".[dev]" && pytest tests/`.

6. **Run the test suite.** All six tests pass. Re-run the syntax check `python -c "from mention_mate.permalink_resolver import resolve_message_link"` to ensure the module is importable.

7. **Manual smoke test.** Rebuild the Docker image (or run the daemon locally) and trigger one mention in a real supergroup. Confirm the alert link is unchanged from the pre-refactor output. This is a regression check — Phase 1 alone has zero user-visible diff.

## Todo List

- [ ] Create `src/mention_mate/permalink_resolver.py` with the `resolve_message_link` function.
- [ ] Update `src/mention_mate/__main__.py` to import + call the new function; remove the Telethon `Channel` import.
- [ ] Create `tests/__init__.py` + `tests/test_permalink_resolver.py` with the six cases above.
- [ ] Add `pytest` under `[project.optional-dependencies].dev` in `pyproject.toml`.
- [ ] `pip install -e ".[dev]" && pytest tests/` — all green.
- [ ] Run `python -c "from mention_mate.__main__ import main"` to confirm clean import chain.
- [ ] Manual mention in a real supergroup → confirm link unchanged.

## Success Criteria

- [ ] `permalink_resolver.py` exists, ~25 LOC, owns the only `telethon.tl.types` import in the codebase.
- [ ] `__main__.py` no longer imports `Channel`, no longer contains `t.me/` string literals, and the permalink section is one line.
- [ ] `pytest tests/test_permalink_resolver.py` passes with six tests covering all branches.
- [ ] Manual supergroup mention produces an identical alert link to pre-refactor output.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `FakeChannel(Channel)` subclass fails to instantiate because the real `Channel.__init__` demands extra kwargs | Medium — Telethon's TL types have many required fields | Phase 1 tests can't run | Try subclass-with-dataclass first; if it fails, fall back to bare `@dataclass` + register the fake via `Channel.register(FakeChannel)` (virtual subclass) or `pytest.MonkeyPatch.setattr` on `isinstance`. Either path keeps the dataclass-attribute-safety win. |
| `Channel` import path differs in future Telethon versions | Low — pinned to `telethon==1.33.1` | ImportError at startup | Fail loudly via the existing module-import smoke check. Future Telethon upgrade should re-run the test suite. |
| Wider blast radius if I accidentally edit unrelated handler logic | Low — change is mechanical | Regression in dispatch / logging | The diff for `__main__.py` should be: ~13 lines removed, ~1 line added, plus import swap. Anything beyond that = scope creep, revert. |

## Security Considerations

No new inputs, no new outbound calls. The `chat.username` interpolation safety analysis from the prior plan (Telegram enforces `[A-Za-z][A-Za-z0-9_]{4,31}`, output passes through `html.escape(..., quote=True)` downstream) is preserved unchanged — the URL is constructed in the same shape, just from a different file.

## Next Steps

After this phase merges:
- Phase 2 picks up — the renderer can now declare `message_link: str | None` and stay Telethon-free.
- No CHANGELOG / README entry for Phase 1 alone (internal refactor, zero user-visible diff). One combined entry at end of Phase 2.
