# CI Sweeper Triage Report Format

Use this structure for every run, including no-action exits.

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

## Summary

- **Level:** <L1|L2|L3>
- **Failures assessed:** <count>
- **Fixes applied:** <count>
- **Validation:** <commands run and pass/fail, or "Not run">
- **Outcome:** <one-line result, e.g. "CI green / no actionable failures">
```

## Rules

- Always emit all four `##` sections; use `None` or `0` when a section has no items.
- At `L1`, list fixes in Actionable Fixes but do not edit files.
- At `L2`/`L3`, edit source files only for `regression` failures within the allowlist.
- Do not claim validation passed when commands failed or were not run.
