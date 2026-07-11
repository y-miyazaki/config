# Documentation Triage Report Format

Use this structure for every run, including no-action exits.

```markdown
# Documentation Triage Report

## High-Priority Items (Fixed)

- **File:** <path>
- **Reason:** <from findings>
- **Fix applied:** <minimal change summary, or "None">

## Watch Items (Deferred)

- **File:** <path>
- **Reason:** <why deferred>

## Noise / Ignore

- <out-of-scope, duplicate, or excluded items, or "None">

## Summary

- **Level:** <L1|L2|L3>
- **Commit range:** <commit_range>
- **Findings assessed:** <count>
- **Files modified:** <count>
- **Outcome:** <one-line result, e.g. "No documentation impact detected">
```

## Rules

- Always emit all four `##` sections; use `None` or `0` when a section has no items.
- At `L1`, list fixes in High-Priority Items but do not edit files.
- At `L2`/`L3`, edit only High-Priority items within the prompt `## Constraints` allowlist (see `category-scope.md`).
- Verifier expects changes to address triage findings with factual consistency and preserved structure.
