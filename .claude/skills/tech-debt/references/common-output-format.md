# Technical Debt Result Format

Follow survey/apply shapes in [common-loop-triage-format.md](common-loop-triage-format.md). Category and severity rules: [category-debt-taxonomy.md](category-debt-taxonomy.md).

Loop PR bodies: load survey or apply template at synthesis. Platform contract: [common-loop-pr-body-contract.md](common-loop-pr-body-contract.md).

## Survey-only result (`mode: survey`, loop `L1`)

No file edits. **Do not write `report_file`.** **Do not emit `### Changes`, `### Deferred`, or `## Verification`.**

```markdown
# Technical Debt Result

## Overview

<scan scope → dominant categories/files found → no edits applied; name substance, not counts only>

## Summary

### Candidates

| Target      | Category   | Evidence            | Suggested approach         | Delegate                                       | Priority              |
| ----------- | ---------- | ------------------- | -------------------------- | ---------------------------------------------- | --------------------- |
| `path:line` | <category> | <snippet or metric> | <plain-language direction> | self \| refactor \| docs-updater \| human \| — | high \| medium \| low |

### Watch

| Target | Evidence | Why not now |
| ------ | -------- | ----------- |
```

### Survey — section rules

| Section           | Rule                                                                 |
| ----------------- | -------------------------------------------------------------------- |
| Overview          | Name dominant debt categories or files; state **no edits** when true |
| `### Candidates`  | **Required** when Critical/High apply-worthy rows exist              |
| `### Watch`       | Optional; lower urgency or delegate-only items                       |
| `### Changes`     | **MUST NOT** appear in survey-only output                            |
| `## Verification` | **MUST NOT** appear                                                  |

**Delegate:** `self` = closed-set apply candidate; `refactor` = structural; `docs-updater` = doc drift; `human` = security or judgment; `—` = report-only.

## Apply result (`mode: apply`, loop `L2`/`L3`)

Survey runs internally first; final output uses apply shape. Write `report_file` at L2/L3 within allowlist.

```markdown
# Technical Debt Result

## Overview

<scope → what was recorded/fixed by category or file → deferrals; name substance>

## Summary

### Changes

| Target                                | What was wrong | What changed                    |
| ------------------------------------- | -------------- | ------------------------------- |
| `docs/report/tech-debt/YYYY-MM-DD.md` | <finding gap>  | <report recorded>               |
| `path/to/file`                        | <debt fact>    | <minimal closed-set fix if any> |

### Deferred

| Target | Why deferred |
| ------ | ------------ |

## Verification

| Check          | Result                 |
| -------------- | ---------------------- |
| Detect sensors | <pass \| fail \| skip> |
```

### Apply — section rules

| Section          | Rule                                                                 |
| ---------------- | -------------------------------------------------------------------- |
| Overview         | State what was **recorded** and **fixed** by name (categories/files) |
| `### Changes`    | **Required** when `git diff` non-empty; include `report_file` row    |
| `### Deferred`   | Fold Watch + non-applied candidates; omit when empty                 |
| `### Candidates` | **MUST NOT** appear in final apply output                            |

Reconcile with `git diff --name-only` before synthesis.

## Loop session metrics (verifier / logs)

```markdown
## Session Metrics

| Field | Value |
| Level | <L1\|L2\|L3> |
| Mode | <survey\|apply> |
| Commit range | <commit_range> |
| Signals assessed | <count> |
| Hotspots assessed | <count> |
| Report file | <report_file or "None"> |
| Outcome | <one-line result> |
```

## Persisted report file (L2/L3 only)

Write `report_file` (`docs/report/tech-debt/YYYY-MM-DD.md`) with extended tables (Resolved Since Previous, Report Outcome). PR Summary uses apply/survey shape only — not a copy of the full persisted file.

```markdown
# Technical Debt Report — YYYY-MM-DD

## Scope

- **Commit range:** <commit_range>
- **Previous report:** <previous_report or "None">
- **Signals:** <count>
- **Hotspots:** <count>

## Critical

| Path | Category | Nature | Kind | Evidence | Recommendation |
| ---- | -------- | ------ | ---- | -------- | -------------- |

## High-Priority

| Path | Category | Nature | Kind | Evidence | Recommendation |

## Watch

| Path | Category | Reason |

## Resolved Since Previous

- <item or "None">

## Report Outcome

- **Findings (Critical + High):** <count>
- **Watch:** <count>
- **Truncated:** <yes/no>
- **Outcome:** <one-line>
```

## Rules

- Pick **one** result shape per run — survey-only **or** apply.
- Cap Critical + High-Priority at 25 combined; defer overflow to Watch with truncation note.
- Every finding row must include `Category` from the taxonomy.
- At `L1`, emit survey shape + Session Metrics — do not write `report_file`.
- At `L2`/`L3`, emit apply shape, write `report_file`, apply closed-set fixes only per [category-scope.md](category-scope.md).
