# Common Loop Triage Report Format

> **Source of truth:** Portable contract files live in [`portable/`](portable/). Run `bash scripts/self/apm/sync_loop_contract.sh` (or `sync_apm_artifacts.sh loop-contract`) after edits to propagate to skill `references/`.

Platform PR composition: [loop-pr-body-skill-contract.md](loop-pr-body-skill-contract.md). Skill-distributed copies: `references/common-loop-triage-format.md` and `references/common-loop-pr-body-contract.md` in each loop skill under `.apm/packages/common/.apm/skills/`.

## Skills using this format

| Skill        | Survey primary   | Apply primary | Deferred / skip |
| ------------ | ---------------- | ------------- | --------------- |
| refactor     | `### Candidates` | `### Changes` | `### Deferred`  |
| tech-debt    | `### Candidates` | `### Changes` | `### Deferred`  |
| ci-sweeper   | `### Candidates` | `### Changes` | `### Deferred`  |
| docs-updater | `### Candidates` | `### Changes` | `### Deferred`  |
| changelog    | `### Candidates` | `### Changes` | `### Skipped`   |

## Overview contract

Every run emits `## Overview` first. Write 1–2 plain-language sentences (~280 characters max).

| Element   | Include                                                                   |
| --------- | ------------------------------------------------------------------------- |
| Trigger   | Scan scope, workflow/job, or commit range                                 |
| Substance | Dominant categories, named files, or failure types — **not counts alone** |
| Action    | Recorded, fixed, deferred, or no edits                                    |

**Good (survey):** `Debt scan over abc..def found broken links in docs/guide and pin drift in package.json; 12 TODO markers logged as Watch; no edits applied.`

**Bad (survey):** `Debt scan found 18 Watch signals.`

**Good (apply):** `Fixed MD001 in docs/foo.md and wrote docs/report/tech-debt/2026-07-23.md with 2 High documentation findings; deferred one architecture hotspot.`

**Bad (apply):** `Applied 2 of 5 candidates.`

## Survey shape (L1 / `mode: survey`)

No file edits.

```markdown
# <Skill> Result

## Overview

<substance summary; no edits applied when true>

## Summary

### Candidates

| Target | Evidence | Suggested approach | Priority |
| ------ | -------- | ------------------ | -------- |

### Watch

| Target | Evidence | Why not now |
| ------ | -------- | ----------- |
```

### Survey rules

| Rule              | Requirement                                          |
| ----------------- | ---------------------------------------------------- |
| `### Candidates`  | Required when any apply-worthy row exists            |
| `### Watch`       | Optional                                             |
| `### Changes`     | **MUST NOT** appear                                  |
| `### Deferred`    | **MUST NOT** appear                                  |
| `## Verification` | **MUST NOT** appear                                  |
| Zero candidates   | Overview explains no-op; omit empty `### Candidates` |

### Domain column extensions

| Skill        | Extra columns on Candidates                       |
| ------------ | ------------------------------------------------- |
| tech-debt    | `Category`, `Delegate` after `Target`             |
| ci-sweeper   | `Workflow / Job` as Target                        |
| changelog    | `Type` column; Target = commit subject or version |
| docs-updater | Target = doc path                                 |

## Apply shape (L2/L3 / `mode: apply`)

Survey runs internally first; final output uses apply shape only.

```markdown
# <Skill> Result

## Overview

<substance summary of fixes vs deferrals>

## Summary

### Changes

| Target | What was wrong | What changed |
| ------ | -------------- | ------------ |

### Deferred

| Target | Why deferred |
| ------ | ------------ |

## Verification

| Check | Result |
| ----- | ------ |
```

### Apply rules

| Rule              | Requirement                                            |
| ----------------- | ------------------------------------------------------ |
| `### Changes`     | Required when `git diff` is non-empty                  |
| `### Deferred`    | Watch/skip rows plus apply failures; omit when empty   |
| `### Candidates`  | **MUST NOT** appear in final output                    |
| `### Watch`       | **MUST NOT** appear — fold into **Deferred**           |
| `## Verification` | Required when apply phase ran                          |
| Git alignment     | Reconcile with `git diff --name-only` before synthesis |

## Loop session metrics (verifier / logs)

Separate from PR body. Emit after survey or apply work:

```markdown
## Session Metrics

| Field | Value |
| Level | L1 \| L2 \| L3 |
| Mode | survey \| apply |
| … | skill-specific counters |
| Outcome | one-line verifier result |
```

## PR templates

- Survey: `assets/pr-body-template-survey.md` (load at L1)
- Apply: `assets/pr-body-template.md` (load at L2/L3)

`loop-finalize` extracts Overview and Summary; Verification on apply only.

## Interactive mode

| User language                                         | Resolved mode |
| ----------------------------------------------------- | ------------- |
| 洗い出し, survey, inventory, list, 調査               | `survey`      |
| 直して, apply, fix, refactor (default for fix skills) | `apply`       |

Default for loop: L1 → survey; L2/L3 → apply.
