---
name: loop-ci-sweeper
description: >-
  Triage failing CI on integration branches and/or PR heads, classify failures,
  apply minimal fixes when actionable. Use when loop automation detects failed
  workflow runs — not for manual debugging. Triggers via on-loop-ci-sweeper.yaml;
  never user-invoked.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.4.0"
---

## Input

Injected JSON from loop-prompt-generate — see [category-input-schema.md](references/category-input-schema.md).

## Output Specification

Triage report per [common-output-format.md](references/common-output-format.md).
At `L2`/`L3`, edit actionable `regression` failures within [category-scope.md](references/category-scope.md).

## Execution Scope

### USE FOR:

- Classify CI failures; apply minimal lint/workflow/shell/doc fixes
- Run validation after edits

### DO NOT USE FOR:

- Infra outages, secrets, or runner capacity issues (classify as Watch)
- Refactors >5 files or auth/payment/credential paths
- Merge PRs or push to default branch

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-input-schema.md](references/category-input-schema.md) - Read when parsing context.
- [category-run-ledger.md](references/category-run-ledger.md) - Read when ledger or REJECT retry policy applies.
- [category-validation-commands.md](references/category-validation-commands.md) - Read for post-edit validation.

## Workflow

1. Parse [category-input-schema.md](references/category-input-schema.md). If `skip` or no actionable `failures`, emit all four report sections; set Summary **Outcome** to `no actionable failures`; stop.
2. Classify every item in `failures[]` per [common-checklist.md](references/common-checklist.md). Use detect `failure_type` as a hint only — reclassify when `log_excerpt` contradicts it. List `ignored[]` entries under `## Ignored`.
3. For `regression` at `L2`/`L3`, fix the first regression only when more than three failures are present; defer the rest as Watch. Edit only within [category-scope.md](references/category-scope.md) allowlist.
4. When infra/env/flake or >5 files are required, classify as Watch with no edits. Set Summary **Outcome** to `watch` (or `deferred`) so finalize records `outcome: watch`.
5. Run validation per [category-validation-commands.md](references/category-validation-commands.md) and caller `## Instructions` stack routing; record outcome in Summary. If validation tooling is missing, defer as Watch unless fixing a single reported line from `log_excerpt`.
6. Output per [common-output-format.md](references/common-output-format.md).
