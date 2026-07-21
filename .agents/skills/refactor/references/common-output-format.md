# Refactor Session Report Format

Use this structure for every run, including no-op exits.

## Session report

```markdown
# Refactor Session Report

## Target

- **Path/symbol:** <one target>
- **Evidence:** <user request | duplication_block | oversized_unit | other structure hint>
- **Tier applied:** <O1 local structure | O2 same-package move | none>

## Applied Change

- <minimal diff summary, or "None">

## Characterization / Gates

- **Added or used:** <tests/commands, or "None">
- **Downgrade:** <none | O2→O1 (same-package move → local only) | Watch reason>

## Watch Items

- <deferred deep redesign (O3), unsupported stack, weak gate, or "None">

## Session Metrics

| Field      | Value                                                |
| ---------- | ---------------------------------------------------- |
| Targets    | <0 or 1>                                             |
| Tier       | <O1 local structure \| O2 same-package move \| none> |
| Validation | <commands/skills and pass/fail, or "Not run">        |
| Outcome    | <applied \| no-op \| watch \| reverted>              |
```

## Rules

- Always emit all `##` sections; use `None` or `0` when empty.
- `## Session Metrics` MUST use a Field | Value table.
- Write **Tier applied** and Metrics **Tier** as a plain-language depth label (`O1 local structure`, `O2 same-package move`, or `none`). Bare `O1` / `O2` without the gloss confuses report readers who have not opened category-operations.
- Do not claim validation passed when commands failed or were not run.
- Do not include tech-debt report paths as required inputs or evidence.
