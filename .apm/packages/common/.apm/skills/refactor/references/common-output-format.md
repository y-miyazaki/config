# Refactor Session Report Format

Use this structure for every run, including no-op and proposal exits.

## Session report

```markdown
# Refactor Session Report

## Target

- **Path/symbol:** <one target>
- **Intent:** <structural | architecture-improvement>
- **Evidence:** <user request | duplication_block | oversized_unit | other structure hint>
- **Technique:** <Fowler name from category-techniques.md | none>
- **Tier applied:** <O1 local structure | O2 same-package move | none>

## Architecture Proposal

- <problem, candidates, phased plan, risks — or "None" (structural intent or Phase B apply)>

## Applied Change

- <minimal diff summary, or "None">

## Characterization / Gates

- **Added or used:** <tests/commands, or "None">
- **Downgrade:** <none | O2→O1 (same-package move → local only) | Watch reason>

## Watch Items

- <deferred work, unsupported stack, weak gate, or "None">

## Session Metrics

| Field      | Value                                                            |
| ---------- | ---------------------------------------------------------------- |
| Targets    | <0 or 1>                                                         |
| Intent     | <structural \| architecture-improvement>                         |
| Tier       | <O1 local structure \| O2 same-package move \| none>             |
| Validation | <commands/skills and pass/fail, or "Not run" (proposal Phase A)> |
| Outcome    | <applied \| proposal \| no-op \| watch \| reverted>              |
```

## Rules

- Always emit all `##` sections; use `None` or `0` when empty.
- `## Session Metrics` MUST use a Field | Value table.
- Write **Tier applied** and Metrics **Tier** as a plain-language depth label (`O1 local structure`, `O2 same-package move`, or `none`). Bare `O1` / `O2` without the gloss confuses report readers who have not opened category-operations.
- Architecture Phase A: **Architecture Proposal** filled; **Applied Change** = `None`; **Validation** = `Not run`; Outcome = `proposal`.
- Architecture Phase B: record approved slice in **Evidence** or **Architecture Proposal**; run structural apply path.
- Do not claim validation passed when commands failed or were not run.
- Do not include tech-debt report paths as required inputs or evidence.

