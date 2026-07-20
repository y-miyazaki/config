# Documentation Triage Report Format

Use this structure for every run, including no-action exits.

## Session report (verifier / logs)

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

## Session Metrics

| Field             | Value                                                      |
| ----------------- | ---------------------------------------------------------- |
| Level             | <L1\|L2\|L3>                                               |
| Commit range      | <commit_range>                                             |
| Findings assessed | <count>                                                    |
| Files modified    | <count>                                                    |
| Outcome           | <one-line result, e.g. "No documentation impact detected"> |
```

## PR body contract (human-facing)

At synthesis time (after triage and edits), load `assets/pr-body-template.md` and emit **exactly** its `## Overview` and `## Summary` sections. `loop-finalize` extracts these for the PR body.

Pattern reference: [APM triage-panel](https://github.com/microsoft/apm/blob/main/.github/workflows/triage-panel.md) — skill owns the verdict template; platform passthrough only.

| Triage panel                | loop-docs-triage                    |
| --------------------------- | ----------------------------------- |
| `assets/triage-template.md` | `assets/pr-body-template.md`        |
| Synthesized verdict         | `## Overview` + `## Summary` tables |
| Decision table              | `## Run Metadata` (finalize-owned)  |

PR-facing `## Summary` MUST use Markdown tables for Fixes Applied and Deferred (not metadata bullets).

### Overview (skill-specific)

Emit one paragraph under `## Overview` that answers:

| Element | docs-triage content                                                         |
| ------- | --------------------------------------------------------------------------- |
| Trigger | Docs drift scan over `<commit_range>` (or "scheduled scan")                 |
| Problem | What was stale, missing, or broken (nav entry, broken link, version pin, …) |
| Action  | How many files fixed vs deferred; name paths when ≤3                        |

**Good:** `Docs drift scan found 3 stale package references in mkdocs nav; this run updated README and mkdocs.yml and deferred 1 Watch item in a generated directory.`

**Bad:** `Documentation triage loop completed at L2.` / `See Summary below.` / bullet list of metadata

## Rules

- Always emit all session `##` sections; use `None` or `0` when a section has no items.
- `## Session Metrics` MUST use a Field \| Value table (not bullet list).
- Always emit PR `## Overview` and `## Summary` after session report (even on no-action exits).
- At `L1`, list fixes in High-Priority Items but do not edit files.
- At `L2`/`L3`, edit only High-Priority items within the prompt `## Constraints` allowlist (see `category-scope.md`).
- Verifier expects changes to address triage findings with factual consistency and preserved structure.
