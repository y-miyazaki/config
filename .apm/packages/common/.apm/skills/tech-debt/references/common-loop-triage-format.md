# Common Loop Triage Report Format

Canonical survey/apply output shapes for loop triage skills. PR composition: [common-loop-pr-body-contract.md](common-loop-pr-body-contract.md).

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
| `### Skipped`     | **MUST NOT** appear                                  |
| `## Verification` | **MUST NOT** appear                                  |
| Zero candidates   | Overview explains no-op; omit empty `### Candidates` |

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

| Field   | Value                    |
| ------- | ------------------------ |
| Level   | L1 \| L2 \| L3           |
| Mode    | survey \| apply          |
| Outcome | one-line verifier result |
```

## PR templates

- Survey: `assets/pr-body-template-survey.md` (load at L1)
- Apply: `assets/pr-body-template.md` (load at L2/L3)

## Interactive mode

| User language                           | Resolved mode |
| --------------------------------------- | ------------- |
| 洗い出し, survey, inventory, list, 調査 | `survey`      |
| 直して, apply, fix                      | `apply`       |

Default for loop: L1 → survey; L2/L3 → apply.
