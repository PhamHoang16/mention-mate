---
title: Fix message permalink for basic-group mentions
description: >-
  Detect chat type (Channel vs Chat) before generating the 'Open in Telegram'
  link; basic groups have no permalink format, so the current code emits a
  broken `t.me/c/{id}/{msg_id}` URL that resolves to a random/inaccessible
  channel.
status: completed
priority: P1
branch: master
tags:
  - bug
  - telegram
  - permalink
blockedBy: []
blocks: []
created: '2026-05-21T02:23:46.424Z'
createdBy: 'ck:plan'
source: skill
---

# Fix message permalink for basic-group mentions

## Overview

Alert messages contain a `🔗 Open in Telegram →` link built as `https://t.me/c/{chat.id}/{event.id}`. This URL format is **only valid for `Channel` chats** (supergroups, megagroups, broadcast channels). For `Chat` (basic group) mentions, Telegram tries to interpret the bare ID as a channel ID, lands on an unrelated or inaccessible channel, and shows "you have no permission" — which matches the user-reported symptom.

The fix: detect the chat type from Telethon (`telethon.tl.types.Channel` vs `Chat`) and either:
1. Build a public-username link `t.me/{username}/{msg_id}` if the chat has a username (cleanest, works for everyone).
2. Build a private channel link `t.me/c/{chat.id}/{msg_id}` for private supergroups / channels.
3. For basic groups (`Chat`) and DMs (`User`), omit the link and replace it with a fallback hint, since no permalink scheme exists.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Fix permalink generation](./phase-01-fix-permalink-generation.md) | Completed |

## Dependencies

None. Single-file change in `src/mention_mate/__main__.py`. No tests currently exist; verification is manual against the user's groups (one basic group + one supergroup).

## Out of scope

- Adding a test harness for Telethon event handlers (mocking the Telethon client is non-trivial and outside this bugfix).
- Auto-suggesting "upgrade your basic group to a supergroup" — Telegram supports this in one tap, but documenting it belongs in user docs, not the alert payload.
- Rewriting the alert template structure — the recent linter change to use a header + dividers around the blockquote is preserved as-is.
