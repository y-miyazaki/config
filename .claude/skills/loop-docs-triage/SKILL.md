---
name: loop-docs-triage
description: >-
  Apply documentation fixes based on triage findings provided in prompt context.
  Use when loop automation detects documentation drift from recent commits.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "2.2.0"
---

## Input

Provided via prompt context by the calling workflow: triage findings (JSON), commit range (last_sha..current_sha), operating level (L1/L2/L3).

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

- No findings → report "no items", stop. >20 files → fix first 10, note truncation.
- File outside allowlist or >3 sections affected → skip, classify as Watch.

### Examples

- Trigger: schedule event detects stale API reference in `docs/reference/specification.md`
- Result: triage report with Fix item (update table row) and Watch items (unrelated files skipped).
