# CI Sweeper Triage Report Format

Follow survey/apply shapes in [common-loop-triage-format.md](common-loop-triage-format.md).

## Survey-only result (loop `L1`)

No file edits. **Do not emit `### Changes`, `### Deferred`, or `## Verification`.**

```markdown
# CI Sweeper Result

## Overview

<which workflow/job failed → root cause by name → no edits applied>

## Summary

### Candidates

| Target                 | Evidence           | Suggested approach       | Priority              |
| ---------------------- | ------------------ | ------------------------ | --------------------- |
| `<workflow>` / `<job>` | <from log_excerpt> | <plain-language fix dir> | high \| medium \| low |

### Watch

| Target                 | Evidence | Why not now             |
| ---------------------- | -------- | ----------------------- |
| `<workflow>` / `<job>` | <reason> | flake \| infra \| human |
```

## Apply result (loop `L2`/`L3`)

```markdown
# CI Sweeper Result

## Overview

<which failures were fixed vs deferred — name workflow/job and cause>

## Summary

### Changes

| Target                 | What was wrong | What changed          |
| ---------------------- | -------------- | --------------------- |
| `<workflow>` / `<job>` | <root cause>   | <minimal fix summary> |

### Deferred

| Target                 | Why deferred            |
| ---------------------- | ----------------------- |
| `<workflow>` / `<job>` | <plain-language reason> |

## Verification

| Check         | Result                            |
| ------------- | --------------------------------- |
| <command run> | <pass \| fail \| skip \| blocked> |
```

## Loop session metrics (verifier / logs)

```markdown
## Session Metrics

| Field | Value |
| Level | <L1\|L2\|L3> |
| Mode | <survey\|apply> |
| Failures assessed | <count> |
| Fixes applied | <count> |
| Validation | <commands run and pass/fail, or "Not run"> |
| Outcome | <one-line result> |
```

## PR body contract (human-facing)

At synthesis time, load `assets/pr-body-template-survey.md` (L1) or `assets/pr-body-template.md` (L2/L3).

`loop-finalize` adds `## Failure context` from detect and `## Run Metadata`.

See [common-loop-pr-body-contract.md](common-loop-pr-body-contract.md).

### Overview (skill-specific)

| Element   | ci-sweeper content                                                       |
| --------- | ------------------------------------------------------------------------ |
| Trigger   | Which workflow/job failed (name, not URL)                                |
| Substance | Root cause in plain language — name the lint rule, file, or failure type |
| Action    | What was fixed or deferred                                               |

**Good:** `CI failed on markdownlint MD001 in docs/foo.md; fixed heading style in one file.`

**Bad:** `CI sweeper addressed actionable failures.`

## Fixes / Deferred consistency

Reconcile with `git diff --name-only` before synthesis. See [common-loop-triage-format.md](common-loop-triage-format.md).

## Rules

- Pick one shape per run — survey or apply.
- At `L1`, survey shape only — list candidates but do not edit files.
- At `L2`/`L3`, apply shape; edit source files only for `regression` failures within allowlist.
- Do not claim validation passed when commands failed or were not run.
