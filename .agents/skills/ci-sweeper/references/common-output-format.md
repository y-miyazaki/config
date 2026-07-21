# CI Sweeper Triage Report Format

Use this structure for every run, including no-action exits.

## Session report (verifier / logs)

```markdown
# CI Sweeper Triage Report

## Actionable Fixes

- **Workflow:** <workflow_name> / **Job:** <job_name>
- **Root cause:** <from log_excerpt>
- **Fix applied:** <minimal change summary, or "None">

## Watch Items

- **Workflow:** <workflow_name> / **Job:** <job_name>
- **Type:** <flake|infra|env|needs-human>
- **Reason:** <why deferred>

## Ignored

- <duplicate, excluded, or ledger-skipped failures, or "None">

## Session Metrics

| Field             | Value                                                       |
| ----------------- | ----------------------------------------------------------- |
| Level             | <L1\|L2\|L3>                                                |
| Failures assessed | <count>                                                     |
| Fixes applied     | <count>                                                     |
| Validation        | <commands run and pass/fail, or "Not run">                  |
| Outcome           | <one-line result, e.g. "CI green / no actionable failures"> |
```

## PR body contract (human-facing)

At synthesis time, load `assets/pr-body-template.md` and emit `## Overview` and `## Summary`.

`## Failure context` (workflow, run URL, job, type, reason) is **platform-owned** from detect — do not duplicate full failure blocks in Overview.

Pattern reference: [APM triage-panel](https://github.com/microsoft/apm/blob/main/.github/workflows/triage-panel.md).

| Section                      | Owner                                  |
| ---------------------------- | -------------------------------------- |
| `## Failure context`         | `loop-finalize` (detect JSON)          |
| `## Overview` / `## Summary` | Agent via `assets/pr-body-template.md` |
| `## Run Metadata`            | `loop-finalize`                        |

### Overview (skill-specific)

Emit one paragraph under `## Overview` that answers:

| Element | ci-sweeper content                                                           |
| ------- | ---------------------------------------------------------------------------- |
| Trigger | Which workflow/job failed (name, not URL — URLs are in `## Failure context`) |
| Problem | Root cause in plain language from `log_excerpt`                              |
| Action  | What was fixed, validated, or deferred                                       |

**Good:** `CI failed on markdownlint MD001 in docs/foo.md; fixed heading style in 1 file and re-ran markdownlint-cli2 clean.`

**Bad:** `CI sweeper addressed actionable failures.` / repeating run URL / raw log paste

## Rules

- Always emit all session `##` sections; use `None` or `0` when a section has no items.
- `## Session Metrics` MUST use a Field \| Value table (not bullet list).
- Always emit PR `## Overview` and `## Summary` after session report.
- At `L1`, list fixes in Actionable Fixes but do not edit files.
- At `L2`/`L3`, edit source files only for `regression` failures within the allowlist.
- Do not claim validation passed when commands failed or were not run.
