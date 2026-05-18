# Codex Instructions

This file provides guidance to OpenAI Codex CLI when working with code in this repository.

> VSAF v3 — Agentic AI SDLC Framework. 3 integrated tools. 2-layer review.

---

## Prerequisites

Node.js ≥18, Git. Run `npx vsaf init` (idempotent) to install all tools.

---

## Architecture

VSAF is a meta-framework for AI-driven SDLC — not an application. It has no source code to compile. The 3-tool stack:

| Layer | Tools | Purpose |
|-------|-------|---------|
| Planning | BMAD Method | PRD, SRS, architecture docs, sprint stories |
| Code Intelligence | GitNexus | Impact analysis, call graph, blast radius |
| Implementation | Superpowers, Codex | Brainstorm, TDD execution, code review |

Key directories: `.codex/` (skills + instructions), `.vsaf/_bmad/` (BMAD workspace), `.vsaf/docs/` (artifacts), `.gitnexus/` (knowledge graph index).

---

## Commands

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

## Knowledge Graph (GitNexus backbone)

- Run impact analysis before any code change: `gitnexus impact <symbol>`
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
- Use `/vsaf-onboard` for the structured onboarding sequence.
- Do not modify code on day one.

### Step 2: Planning + Requirement → PRD → SRS
```
/vsaf-plan <requirement>    # scope + impact + approach
/vsaf-doc-prd               # write PRD from approved scope
/vsaf-doc-srs               # write SRS from PRD
```

### Step 3: Testcase from SRS
```
/vsaf-test <path/to/srs>
```

### Step 4: Impact Analysis
```
gitnexus impact <symbol> --direction upstream   # Blast radius
```
Impact > 3 modules → split PRs.

### Step 5: Implement from SRS + Testcases
```
/vsaf-build <path/to/srs> <path/to/testcases>
```
TDD discipline: 1 commit per task.

### Step 6: Review + Ship
```
/bmad-code-review
vsaf index
/vsaf-ship
```
```bash
git push origin feature/<name>
```

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
| GitNexus index | `gitnexus analyze` |
| GitNexus web | `gitnexus serve` |

---

## Anti-Patterns

| Do Not | Instead |
|---|---|
| Write code before PRD/SRS/testcase | `/vsaf-plan` → `/vsaf-doc-prd` → `/vsaf-doc-srs` → `/vsaf-test` |
| Implement without impact gate | `gitnexus impact` before editing any symbol |
| Push without review | 2-layer: code-review + vsaf index |
| Forget to re-index | `vsaf index` after every merge |
| Create PRs > 400 lines | Split into smaller PRs |
| Trust AI output blindly | AI writes → review → human approves |

---

## Commit Discipline

- 1 commit per task from the plan.
- Each commit message: `<type>: <description>` (feat, fix, refactor, docs, test).
- Tests must pass after every commit.

---

## Security

- Never hardcode credentials. Use environment variables.
