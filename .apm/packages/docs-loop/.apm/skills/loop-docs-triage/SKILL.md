---
name: loop-docs-triage
description: >-
  Automated loop skill: apply documentation fixes based on triage findings
  injected by scheduled GitHub Actions workflows. Use when loop automation
  detects documentation drift from recent commits — not for manual/hook-triggered
  sync (use docs-updater for that). Triggers via on-loop-docs-triage.yaml cron,
  never invoked directly by users.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "2.3.0"
---

## Input

Provided via prompt context by the calling workflow (loop-prompt-generate action).

Required fields in the injected JSON:

```json
{
  "commit_range": "abc1234..def5678",
  "level": "L2",
  "findings": [
    {
      "file": "docs/reference/specification.md",
      "reason": "references deleted workflow ci-build.yaml",
      "source_commit": "def5678"
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `commit_range` | string | SHA range that triggered detection |
| `level` | enum | Operating level: `L1` (report only), `L2` (edit + PR), `L3` (edit + auto-merge) |
| `findings` | array | Detected documentation drift items |
| `findings[].file` | string | Path to affected documentation file |
| `findings[].reason` | string | Why the file is stale |
| `findings[].source_commit` | string | Commit that caused the drift |

## Output Specification

Structured markdown triage report with four sections:
- 1. High-Priority Items (Fixed) — file, reason, applied edit
- 2. Watch Items (Deferred) — file, reason, why deferred
- 3. Noise / Ignore — file, reason
- 4. Summary — commit range, files assessed/modified count

At L2+, documentation files are edited directly.

## Execution Scope

### USE FOR:

- Edit docs to fix stale references and missing content
- Produce a prioritized triage report

### DO NOT USE FOR:

- Create new documentation from scratch
- Modify non-documentation files
- Run detection or manage state (workflow handles these)

### Path Allowlist

`docs/**/*.md`, `README.md`, `mkdocs.yml` (nav only)

### Path Denylist

`**/.env`, `**/credentials*`, `**/secrets*`, `**/migration/*.sql`, `**/infrastructure/**`

## Reference Files Guide

- Project `AGENTS.md` or steering files (always read)
- `mkdocs.yml` for nav structure (always read)

## Workflow

1. Parse triage findings from prompt context.
2. If no actionable items, output "No documentation impact detected" and stop.
3. Classify each affected doc: High-Priority (stale ref, missing docs) or Watch (minor drift, needs human judgment).
4. Fix High-Priority items within allowlist. Skip denylist paths as Watch.
5. Scope guard: >3 sections in one doc → stop for that file, recommend manual review.
6. Output triage report per Output Specification.

### Error Handling

- No findings → report "no items", stop.
- >20 files → fix first 10, note truncation (token budget constraint: single agent session targets ≤120k tokens).
- File outside allowlist or >3 sections affected → skip, classify as Watch.

### Examples

- Trigger: schedule event detects stale API reference in `docs/reference/specification.md`
- Result: triage report with Fix item (update table row) and Watch items (unrelated files skipped).
