---
name: loop-docs-triage
description: >-
  Apply documentation fixes from loop-injected triage findings. Use when loop
  automation detects documentation drift — not hook-triggered sync (use docs-updater).
  Triggers via caller loop workflow (e.g. on-loop-docs-triage.yaml cron); never user-invoked.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "2.5.0"
---

## Input

Injected JSON from loop-prompt-generate — see [category-input-schema.md](references/category-input-schema.md). Path allowlist and denylist arrive in the prompt `## Constraints` section (caller `LOOP_ALLOWLIST`, `LOOP_DENYLIST`).

## Output Specification

Triage report per [common-output-format.md](references/common-output-format.md).
At `L2`/`L3`, edit High-Priority items within the active allowlist ([category-scope.md](references/category-scope.md)).

## Execution Scope

### USE FOR:

- Fix stale references and missing documentation content
- Produce prioritized triage report

### DO NOT USE FOR:

- Create documentation from scratch
- Modify non-documentation files
- Run detection or manage loop state

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-input-schema.md](references/category-input-schema.md) - Read when parsing context.
- Project `AGENTS.md` or steering files (always read)
- Site or nav config within the allowlist when present (e.g. `mkdocs.yml`)

## Workflow

1. Parse [category-input-schema.md](references/category-input-schema.md). Read prompt `## Constraints` for the active allowlist. If `skip` or no actionable `findings`, emit report with Summary `No documentation impact detected`; stop.
2. Classify per [common-checklist.md](references/common-checklist.md); fix High-Priority items from `findings`.
3. At `L2`/`L3`, edit only paths allowed by `## Constraints` and [category-scope.md](references/category-scope.md).
4. Output per [common-output-format.md](references/common-output-format.md).
