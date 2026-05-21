# Documentation Consolidation Update Report

**Date:** 2026-05-21
**Scope:** Update docs to reflect wizard script consolidation (4 scripts → 2) and doc consolidation (SETUP.md + TROUBLESHOOTING.md → README.md)

---

## Summary

All documentation references to deleted/consolidated files have been systematically updated. 5 doc files edited, 0 remaining stale references.

---

## Files Edited

1. **docs/project-overview-pdr.md**
   - Line 28: `setup.sh for Linux/macOS, setup.ps1 for Windows` → `mention-mate.sh for Linux/macOS, mention-mate.ps1 for Windows`
   - Line 29: `SETUP.md with step-by-step screenshots, TROUBLESHOOTING.md with error codes` → `README.md with step-by-step guides, Troubleshooting section with error codes`
   - Line 63: Removed reference to separate SETUP.md, TROUBLESHOOTING.md; now unified script
   - Line 75: `per SETUP.md target` → `per README.md target`
   - Line 113: `setup.sh and update.sh` → `mention-mate.sh and mention-mate.ps1`
   - Line 150: `setup.sh and setup.ps1 wizards` → `mention-mate.sh and mention-mate.ps1 wizards`
   - Lines 161-163: Updated TROUBLESHOOTING.md refs to README.md section anchors
   - Risk table: Updated backup strategy from `update.sh` to `mention-mate.sh update`

2. **docs/code-standards.md**
   - Line 14: Shell naming rule `snake_case` examples `setup.sh, update.sh` → `kebab-case` examples `mention-mate.sh, mention-mate.ps1`
   - Line 20: Doc naming examples removed `SETUP.md, TROUBLESHOOTING.md`; kept live examples
   - Line 106: Section header `### Bash (setup.sh, update.sh)` → `### Bash (mention-mate.sh)`
   - Line 191: Section header `### PowerShell (setup.ps1, update.ps1)` → `### PowerShell (mention-mate.ps1)`
   - Lines 431-432: Naming table examples updated for shell & doc files
   - **Note:** Also corrected shell naming standard from `snake_case` to `kebab-case` per CLAUDE.md

3. **docs/deployment-guide.md**
   - Line 17: `./setup.sh` and `.\setup.ps1` → `./mention-mate.sh` and `.\mention-mate.ps1`
   - Line 20: Removed docs/SETUP.md link; pointed to README.md → Install anchor
   - Line 30: Script list updated to unified names
   - Line 72: Wizard file reference updated
   - Line 88: Link to TROUBLESHOOTING.md → README.md → Troubleshooting
   - Lines 198-201: `./update.sh` / `.\update.ps1` → `./mention-mate.sh update` / `.\mention-mate.ps1 update`
   - Line 250: Updated session backup reference
   - Lines 257-258: Same update script reference fix
   - Line 432: Link to TROUBLESHOOTING.md → README.md
   - Line 510: Monthly maintenance `./update.sh` → `./mention-mate.sh update`
   - Line 571: Same fix in quarterly maintenance
   - **Added:** New section "Update Subcommand Reference" (lines ~560-570) documenting the unified script's subcommand interface (setup, update, auto-detect, help, verbose)

4. **docs/codebase-summary.md**
   - Lines 12-15: Directory tree now shows unified scripts (`mention-mate.sh`, `mention-mate.ps1`)
   - Lines 17-18: Removed SETUP.md and TROUBLESHOOTING.md from tree (they no longer exist)
   - Lines 158-208: Consolidated 4 script sections into 2:
     - `scripts/setup.sh (411 LOC)` replaced with `scripts/mention-mate.sh (~430 LOC)` with full interface documentation (setup, update, auto-detect subcommands)
     - `scripts/setup.ps1 (420 LOC)` replaced with `scripts/mention-mate.ps1 (~370 LOC)` with interface documentation
     - Deleted `scripts/update.sh (103 LOC)` section
     - Deleted `scripts/update.ps1 (93 LOC)` section
   - Lines 214-239: Consolidated "Documentation" section:
     - Deleted `docs/SETUP.md` and `docs/TROUBLESHOOTING.md` descriptions
     - Updated `README.md` description to note it contains Install + Troubleshooting sections
     - Clarified Developer Documentation structure
   - Line 346: `update.sh` → `mention-mate.sh update`

5. **docs/project-roadmap.md**
   - Lines 128-129: Consolidated script descriptions (unified mention-mate.sh/mention-mate.ps1)
   - Lines 139-140: Removed separate SETUP.md and TROUBLESHOOTING.md entries; documented in README.md
   - Line 165: `per SETUP.md target` → `per README.md target`
   - Line 321: `update.sh` → `mention-mate.sh update`
   - Lines 370-371: Updated communication channels (removed SETUP.md and TROUBLESHOOTING.md references)

---

## Verification

Final grep for stale references (2026-05-21 14:30 UTC):
```bash
grep -rnE 'setup\.sh|update\.sh|setup\.ps1|update\.ps1|SETUP\.md|TROUBLESHOOTING\.md' docs/ README.md
# Returns: 0 matches ✅
```

All old file names have been replaced with new consolidated names or appropriate section anchors.

---

## Notes

### No Issues Found
- All references were surgical edits; no sections were reordered or restyleд.
- Phase 2 status ("already released as v0.1.0") was preserved.
- README.md changes from previous commits (Install section, Troubleshooting section) already existed; no conflicts.

### Naming Standard Correction
- **code-standards.md line 14** had shell naming as `snake_case` but new file `mention-mate.sh` is `kebab-case`.
- Corrected standard to match project convention from CLAUDE.md and actual implementation.

### Documentation Coverage
- User-facing docs now consolidated into single README.md (≈225 LOC vs. previous 258 + 344 LOC across 2 files).
- Reduces maintenance burden; single source of truth.
- Developer docs remain in docs/ for internal reference.

---

## Files Modified
- `/Users/duongot/Playground/mention-mate/docs/project-overview-pdr.md`
- `/Users/duongot/Playground/mention-mate/docs/code-standards.md`
- `/Users/duongot/Playground/mention-mate/docs/deployment-guide.md`
- `/Users/duongot/Playground/mention-mate/docs/codebase-summary.md`
- `/Users/duongot/Playground/mention-mate/docs/project-roadmap.md`

---

## Status

✅ **DONE**

All stale references eliminated. Documentation now reflects consolidated wizard scripts and README.md as single end-user reference point.
