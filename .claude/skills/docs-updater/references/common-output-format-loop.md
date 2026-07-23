# Documentation Triage Report Format

Follow survey/apply shapes in [common-loop-triage-format.md](common-loop-triage-format.md). Interactive/hook runs use [common-output-format.md](common-output-format.md).

## Survey-only result (loop `L1`)

No file edits.

```markdown
# docs-updater Result

## Overview

<commit range → dominant doc drift by file/category → no edits applied>

## Summary

### Candidates

| Target           | Evidence                  | Suggested approach       | Priority              |
| ---------------- | ------------------------- | ------------------------ | --------------------- |
| `path/to/doc.md` | <stale/missing reference> | <plain-language fix dir> | high \| medium \| low |

### Watch

| Target | Evidence | Why not now |
| ------ | -------- | ----------- |
```

## Apply result (loop `L2`/`L3`)

```markdown
# docs-updater Result

## Overview

<what doc files were fixed vs deferred — name paths or drift types>

## Summary

### Changes

| Target           | What was wrong            | What changed            |
| ---------------- | ------------------------- | ----------------------- |
| `path/to/doc.md` | <stale/missing reference> | <minimal patch summary> |

### Deferred

| Target | Why deferred |
| ------ | ------------ |

## Verification

| Check                               | Result                 |
| ----------------------------------- | ---------------------- |
| <markdown-validation or link check> | <pass \| fail \| skip> |
```

## Loop session metrics (verifier / logs)

```markdown
## Session Metrics

| Field | Value |
| Level | <L1\|L2\|L3> |
| Mode | <survey\|apply> |
| Commit range | <commit_range> |
| Findings assessed | <count> |
| Files modified | <count> |
| Outcome | <one-line verifier result> |
```

## PR body templates

| Mode   | Level     | Template                            |
| ------ | --------- | ----------------------------------- |
| Survey | `L1`      | `assets/pr-body-template-survey.md` |
| Apply  | `L2`/`L3` | `assets/pr-body-template.md`        |

At synthesis, load the template for the resolved mode. Emit **exactly** `## Overview`, `## Summary`, and `## Verification` (apply only).

See [common-loop-pr-body-contract.md](common-loop-pr-body-contract.md).

## Fixes / Deferred consistency

Reconcile with `git diff --name-only` before synthesis.

## Rules

- At `L1`, survey shape only — do not modify files.
- At `L2`/`L3`, apply shape; edit only within prompt `## Constraints` allowlist.
