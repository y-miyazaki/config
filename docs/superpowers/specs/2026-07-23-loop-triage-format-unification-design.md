# Loop Triage Format Unification — Design Spec

**Date:** 2026-07-23  
**Status:** Approved for implementation  
**Scope:** `tech-debt`, `ci-sweeper`, `docs-updater`, `changelog`, `refactor` (Overview only), loop platform validation

## Problem

Loop skills use inconsistent session and PR output shapes. `tech-debt` L1 emits a thin session summary while sibling skills emit triage reports. `refactor` already models survey/apply split; other loop skills do not. Overview text often states counts without summarizing **what** was found or changed, forcing reviewers to read Summary tables.

## Goals

1. Unify loop skills on **survey (L1)** and **apply (L2/L3)** output shapes aligned with `refactor`.
2. Align **L1** across skills: full structured report in session/PR narrative; on GHA, logs only (no branch file writes unless skill-specific persistence at L2+).
3. Strengthen **Overview** so humans grasp substance without opening Summary first.
4. Add **tech-debt** survey/apply modes with closed-set apply and delegate hints for other skills.
5. Include **changelog** in the format family where it fits.

## Non-goals

- Splitting skills into report-skill + fix-skill pairs.
- Changing detect scripts or loop workflow YAML in this pass (unless validation requires it).
- Editing generated `.agents/`, `.cursor/`, etc. (regenerated via `apm install`).

## Canonical shapes

Source of truth: `docs/explanation/loop-engineering/common-loop-triage-format.md`.

### Survey (L1 / `mode: survey`)

- `## Overview` — substance summary (see below)
- `## Summary` → `### Candidates` (required when actionable rows exist), optional `### Watch`
- **MUST NOT** emit `### Changes`, `### Deferred`, or `## Verification`
- Loop session adds `## Session Metrics` (verifier/logs only)

### Apply (L2/L3 / `mode: apply`)

- `## Overview` — substance summary of what was fixed vs deferred
- `## Summary` → `### Changes` (required when `git diff` non-empty), optional `### Deferred`
- **MUST NOT** emit `### Candidates` or `### Watch` in final output
- `## Verification` required when edits were attempted

### Changelog domain mapping

| Survey                                        | Apply                           |
| --------------------------------------------- | ------------------------------- |
| `### Candidates` (commits/releases to record) | `### Changes` (CHANGELOG edits) |
| `### Skipped` optional                        | `### Skipped` optional          |

Deferred subsection name stays `Skipped` for changelog (loop contract).

### Tech-debt domain mapping

| Survey                                              | Apply                                          |
| --------------------------------------------------- | ---------------------------------------------- |
| `### Candidates` (+ `Category`, `Delegate` columns) | `### Changes` (report file + closed-set fixes) |
| `### Watch`                                         | folded into `### Deferred`                     |

Persisted `docs/report/tech-debt/YYYY-MM-DD.md` remains the detailed archive at L2/L3; PR Summary uses the canonical apply/survey shape.

## Overview contract (enhanced)

Overview MUST be 1–2 sentences (~280 chars max) answering:

| Element   | Requirement                                                              |
| --------- | ------------------------------------------------------------------------ |
| Trigger   | What ran (scan scope, workflow, commit range)                            |
| Substance | **Name dominant categories, files, or failure types** — not counts alone |
| Action    | What was done (recorded, fixed, deferred, or no edits)                   |

**Passes:** Reviewer knows _what kind of work happened_ without opening Summary.

**Fails:** "Loop completed", counts only ("found 21 items"), or metadata without substance.

### Examples

**Survey — good:**  
`Debt scan over abc..def found broken doc links in docs/guide and pin drift in package.json; 16 marker comments logged as Watch; no edits applied.`

**Survey — bad:**  
`Debt scan found 18 Watch signals; no edits applied.`

**Apply — good:**  
`Fixed markdownlint heading in docs/foo.md and recorded 2 High documentation findings in docs/report/tech-debt/2026-07-23.md; deferred 1 architecture hotspot to refactor.`

**Apply — bad:**  
`Applied 2 of 5 candidates.`

## Operating levels (unified)

| Level | Behavior (all loop triage skills)       |
| ----- | --------------------------------------- |
| L1    | Survey shape; no file edits; GHA logs   |
| L2    | Apply shape; edits + PR                 |
| L3    | Same edits as L2; caller may auto-merge |

`level` remains loop-internal JSON; user-facing docs use survey/apply vocabulary.

## Tech-debt execution

- **Survey:** classify all signals/hotspots; emit Candidates with `Delegate` (`refactor`, `docs-updater`, `self`, `human`, `—`).
- **Apply (closed-set only):** `broken_doc_ref`, `stale_doc`, simple `pin_drift` within allowlist; write `report_file` at L2/L3.
- **Delegate:** structural/code_quality/architecture → `refactor`; security → report only.

## Validation

- `validate_agent_report.sh`: accept survey outputs (`### Candidates`, no `## Verification` when diff empty).
- `agent_output_format_criteria.md`: document survey vs apply rubric.
- tech-debt primary subsection: `Changes` (not `Report`) for apply mode.

## Risks

- Existing tech-debt evals/templates may need version bumps.
- Overview substance rule is judgment-based; mechanical validator checks length/presence only; LLM verifier enforces substance.
