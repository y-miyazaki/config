# Refactor Loop Session Report Format

Use when loop JSON (`hints[]`, `level`) is present. Interactive runs use [common-output-format.md](common-output-format.md).

## Session report (verifier / logs)

```markdown
# Refactor Session Report

## Target

- **Hint kind:** <duplication_block | oversized_unit | none>
- **Path:** <hint.path>
- **Detail:** <hint.detail>
- **Technique:** <Fowler name | none>
- **Intent:** structural
- **Tier applied:** <O1 local structure | O2 same-package move | none>

## Applied Change

- <minimal diff summary, or "None">

## Characterization / Gates

- **Added or used:** <tests/commands, or "None">
- **Downgrade:** <none | O2→O1 | Watch reason>

## Watch Items

- <deferred hints, unsupported stack, or "None">

## Session Metrics

| Field          | Value                                                |
| -------------- | ---------------------------------------------------- |
| Level          | <L1\|L2\|L3>                                         |
| Commit range   | <commit_range or "n/a">                              |
| Hints assessed | <count>                                              |
| Intent         | structural                                           |
| Tier           | <O1 local structure \| O2 same-package move \| none> |
| Validation     | <commands/skills and pass/fail, or "Not run">        |
| Outcome        | <applied \| no-op \| watch \| reverted>              |
```

## PR body contract (human-facing)

At synthesis time, load `assets/pr-body-template.md` and emit **exactly** its `## Overview` and `## Summary` sections. `loop-finalize` extracts these for the PR body.

## Rules

- Always emit all session `##` sections; use `None` or `0` when empty.
- `## Session Metrics` MUST use a Field \| Value table (not bullet list).
- Always emit PR `## Overview` and `## Summary` after session report (even on no-action exits).
- At `L1`, describe intended change but do not edit files.
- At `L2`/`L3`, edit only within prompt `## Constraints` allowlist.
- Never claim validation passed when commands failed or were not run.
