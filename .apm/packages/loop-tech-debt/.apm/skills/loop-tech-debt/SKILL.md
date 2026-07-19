---
name: loop-tech-debt
description: >-
  Discover and classify technical debt from loop-injected mechanical signals,
  then publish a structured report under docs/report/tech-debt/. Use when loop
  automation runs a scheduled or range-based debt scan — not for ad-hoc refactors
  or CI repair (use loop-ci-sweeper). Triggers via caller loop workflow
  (e.g. on-loop-tech-debt.yaml cron); never user-invoked.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.2.2"
---

## Input

Injected JSON from loop-prompt-generate — see [category-input-schema.md](references/category-input-schema.md). Path allowlist and denylist arrive in the prompt `## Constraints` section (caller `LOOP_ALLOWLIST`, `LOOP_DENYLIST`). Operating levels: [category-input-schema.md#operating-levels](references/category-input-schema.md#operating-levels).

## Output Specification

Session summary per [common-output-format.md](references/common-output-format.md).
At `L2`/`L3`, write the full report to `report_file` within [category-scope.md](references/category-scope.md).

## Execution Scope

### USE FOR:

- Classify mechanical `signals[]` and `hotspots[]` into prioritized debt findings
- Produce a dated technical debt report with evidence and recommendations
- At `L2`/`L3`, create or update `docs/report/tech-debt/YYYY-MM-DD.md`

### DO NOT USE FOR:

- Apply code fixes, refactors, or dependency upgrades
- Edit loop state files (bundled by finalize after verification)
- Run detection or manage loop state
- Replace domain review skills; invoke named skills only when caller `## Instructions` lists them

## Reference Files Guide

- [category-debt-taxonomy.md](references/category-debt-taxonomy.md) (always read)
- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-input-schema.md](references/category-input-schema.md) - Read when parsing context.
- Project `AGENTS.md` or steering files (always read)
- Previous report at `previous_report` when present (always read when path exists)

## Workflow

1. Parse [category-input-schema.md](references/category-input-schema.md). Read prompt `## Constraints` for the allowlist. If `skip` or both `signals` and `hotspots` are empty, emit session summary with Outcome `No technical debt signals detected`; stop without creating `report_file`.
2. Read `previous_report` when set and the file exists. Compare per [common-checklist.md](references/common-checklist.md#previous-report-comparison); note resolved, recurring, and regression items in Summary and persisted report.
3. For each `signals[]` / `hotspots[]` entry, read ±30 lines of source. Classify per [category-debt-taxonomy.md](references/category-debt-taxonomy.md) and [common-checklist.md](references/common-checklist.md) (`category`, severity section, optional `nature`).
4. Emit session summary per [common-output-format.md](references/common-output-format.md). Respect level and cap rules in [common-checklist.md](references/common-checklist.md).
