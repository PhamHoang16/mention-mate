# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> VSAF v3 — Agentic AI SDLC Framework. 4 integrated tools. 2-layer review.

---

## Prerequisites

Node.js ≥18, Python ≥3.10, Git, Claude Code subscription. Run `npx vsaf init` (idempotent) to install all tools.

---

## Architecture

VSAF is a meta-framework for AI-driven SDLC — not an application. It has no source code to compile. The 4-layer stack:

| Layer | Tools | Purpose |
|-------|-------|---------|
| Planning | BMAD Method | PRD, SRS, architecture docs, sprint stories |
| Code Intelligence | GitNexus (MCP) | Impact analysis, call graph, blast radius |
| Implementation | Superpowers, Claude Code | Brainstorm, TDD execution, code review |

Key directories: `.claude/` (settings + skills), `.vsaf/_bmad/` (BMAD workspace), `.vsaf/docs/` (artifacts), `.gitnexus/` (knowledge graph index).

---

## Make Commands

```bash
npx vsaf init    # Install all tools (one-time, idempotent)
vsaf index       # Re-index: gitnexus analyze
vsaf review      # 2-layer review coordinator
vsaf status      # Show status of all tools
vsaf clean       # Clean GitNexus index
```

---

## Identity

This project uses the **VSAF v3 (Agentic AI SDLC Framework)**. All development
follows the SRS-first workflow below. No code ships without 2-layer review.

---

## Knowledge Graph (GitNexus MCP backbone)

- Use GitNexus MCP tools for impact analysis **before any code change**.
- Query: "What breaks if I change X?" before touching cross-module code.
- Re-index after every merge: `gitnexus analyze`

---

## SRS-First Workflow

### Step 0: Setup (one-time)
```bash
npx vsaf init
```

### Step 1: Onboard Project
- Run `gitnexus serve` for web UI exploration.
- Use `gitnexus_query` to find execution flows for the area you'll work in.
- Use `/vsaf-onboard` for the structured onboarding sequence.
- Do not modify code on day one.

### Step 2: Planning + Requirement -> PRD -> SRS
```
/vsaf-plan <requirement>    # scope + impact + approach
/vsaf-doc-prd              # write PRD from approved scope
/vsaf-doc-srs              # write SRS from PRD
```
Quick Flow (bug fix) may use a mini-SRS, but impact analysis is still mandatory.

### Step 3: Testcase from SRS
```
/vsaf-test <path/to/srs>
```

### Step 4: Impact Analysis
```
gitnexus_impact({target: "X", direction: "upstream"})   # Blast radius
```
Impact > 3 modules → split PRs.

### Step 5: Implement from SRS + Testcases
```
/vsaf-build <path/to/srs> <path/to/testcases>
```
`vsaf-build` must keep TDD discipline and 1 commit per task.

### Step 6: Review + Ship
```
/superpowers:code-review
vsaf index              # gitnexus analyze
/vsaf-ship
```
```bash
git push origin feature/<name>
```
PR description must include: impact summary (from GitNexus), test results.

### Command naming map

- `/vsaf-onboarding` -> `vsaf-onboard`
- `/vsaf-planning + requirement` -> `vsaf-plan` + `vsaf-doc-prd` + `vsaf-doc-srs`
- `/vsaf-testcase + path/to/srs` -> `vsaf-test <path/to/srs>`
- `/vsaf-implement + path/to/srs + path/to/test_case` -> `vsaf-build <srs> <testcases>`

---

## Tool Commands — Quick Reference

| Action | Command |
|---|---|
| VSAF onboard | `/vsaf-onboard` |
| VSAF plan | `/vsaf-plan <requirement>` |
| VSAF doc PRD | `/vsaf-doc-prd` |
| VSAF doc SRS | `/vsaf-doc-srs` |
| VSAF testcase | `/vsaf-test <path/to/srs>` |
| VSAF implement | `/vsaf-build <srs> <testcases>` |
| VSAF ship | `/vsaf-ship` |
| Superpowers review | `/superpowers:code-review` |
| GitNexus index | `gitnexus analyze` |
| GitNexus web | `gitnexus serve` |
| GitNexus impact | `gitnexus_impact({target: "X", direction: "upstream"})` |

---

## Anti-Patterns

| Do Not | Instead |
|---|---|
| Write code before PRD/SRS/testcase | `/vsaf-plan` + `/vsaf-doc-prd` + `/vsaf-doc-srs` + `/vsaf-test` first |
| Implement without impact gate | `gitnexus_impact` before editing any symbol |
| Push without review | 2-layer: Superpowers code-review + vsaf index |
| Forget to re-index | `vsaf index` after every merge |
| Create PRs > 400 lines | Split into smaller PRs |
| Trust AI output blindly | AI writes → Superpowers reviews → human approves |
| Skip impact analysis | GitNexus BEFORE coding |

---

## Commit Discipline

- 1 commit per task from the plan.
- Each commit message: `<type>: <description>` (feat, fix, refactor, docs, test).
- Tests must pass after every commit.
- If a task fails 3 times, stop and trigger an architectural review.

---

## Security

- Never hardcode credentials. Use environment variables.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **tele** (29 symbols, 32 relationships, 1 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## When Debugging

1. `gitnexus_query({query: "<error or symptom>"})` — find execution flows related to the issue
2. `gitnexus_context({name: "<suspect function>"})` — see all callers, callees, and process participation
3. `READ gitnexus://repo/tele/process/{processName}` — trace the full execution flow step by step
4. For regressions: `gitnexus_detect_changes({scope: "compare", base_ref: "main"})` — see what your branch changed

## When Refactoring

- **Renaming**: MUST use `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` first. Review the preview — graph edits are safe, text_search edits need manual review. Then run with `dry_run: false`.
- **Extracting/Splitting**: MUST run `gitnexus_context({name: "target"})` to see all incoming/outgoing refs, then `gitnexus_impact({target: "target", direction: "upstream"})` to find all external callers before moving code.
- After any refactor: run `gitnexus_detect_changes({scope: "all"})` to verify only expected files changed.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Tools Quick Reference

| Tool | When to use | Command |
|------|-------------|---------|
| `query` | Find code by concept | `gitnexus_query({query: "auth validation"})` |
| `context` | 360-degree view of one symbol | `gitnexus_context({name: "validateUser"})` |
| `impact` | Blast radius before editing | `gitnexus_impact({target: "X", direction: "upstream"})` |
| `detect_changes` | Pre-commit scope check | `gitnexus_detect_changes({scope: "staged"})` |
| `rename` | Safe multi-file rename | `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` |
| `cypher` | Custom graph queries | `gitnexus_cypher({query: "MATCH ..."})` |

## Impact Risk Levels

| Depth | Meaning | Action |
|-------|---------|--------|
| d=1 | WILL BREAK — direct callers/importers | MUST update these |
| d=2 | LIKELY AFFECTED — indirect deps | Should test |
| d=3 | MAY NEED TESTING — transitive | Test if critical path |

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/tele/context` | Codebase overview, check index freshness |
| `gitnexus://repo/tele/clusters` | All functional areas |
| `gitnexus://repo/tele/processes` | All execution flows |
| `gitnexus://repo/tele/process/{name}` | Step-by-step execution trace |

## Self-Check Before Finishing

Before completing any code modification task, verify:
1. `gitnexus_impact` was run for all modified symbols
2. No HIGH/CRITICAL risk warnings were ignored
3. `gitnexus_detect_changes()` confirms changes match expected scope
4. All d=1 (WILL BREAK) dependents were updated

## Keeping the Index Fresh

After committing code changes, the GitNexus index becomes stale. Re-run analyze to update it:

```bash
npx gitnexus analyze
```

If the index previously included embeddings, preserve them by adding `--embeddings`:

```bash
npx gitnexus analyze --embeddings
```

To check whether embeddings exist, inspect `.gitnexus/meta.json` — the `stats.embeddings` field shows the count (0 means no embeddings). **Running analyze without `--embeddings` will delete any previously generated embeddings.**

> Claude Code users: A PostToolUse hook handles this automatically after `git commit` and `git merge`.

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
