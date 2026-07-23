---
name: ci-sweeper
description: >-
  Triage failing CI on integration branches and/or PR heads, classify failures,
  apply minimal fixes when actionable. Use when loop automation detects failed
  workflow runs or when explicitly invoked with detection JSON. Preferred entry
  via on-loop-ci-sweeper.yaml.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.5.0"
---

## Input

Injected JSON from loop-prompt-generate — see [category-input-schema.md](references/category-input-schema.md).

## Operating levels

`level` arrives in injected JSON — see [category-input-schema.md](references/category-input-schema.md#operating-levels).

## Output Specification

Triage report per [common-output-format.md](references/common-output-format.md). Survey at `L1`; apply at `L2`/`L3` within [category-scope.md](references/category-scope.md). See [common-loop-triage-format.md](references/common-loop-triage-format.md).

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
- [category-input-schema.md](references/category-input-schema.md) (always read)
- [category-run-ledger.md](references/category-run-ledger.md) (always read)
- [category-validation-commands.md](references/category-validation-commands.md) (always read)
- [common-loop-triage-format.md](references/common-loop-triage-format.md) (always read)
- [common-loop-pr-body-contract.md](references/common-loop-pr-body-contract.md) (always read)
- `assets/pr-body-template-survey.md` (always read — loop L1 survey path)
- `assets/pr-body-template.md` (always read — loop L2/L3 apply path)

## Workflow

Every run has **Phase A — Survey** (classify failures). **Phase B — Apply** runs only when mode is `apply` and level allows edits.

### Mode resolution

| Source           | Default mode | Survey-only triggers                           |
| ---------------- | ------------ | ---------------------------------------------- |
| Interactive      | `apply`      | User asks to survey, list, or triage only      |
| Loop `L1`        | `survey`     | Always — no file edits                         |
| Loop `L2` / `L3` | `apply`      | `skip: true` or no actionable failures → no-op |

Explicit JSON `mode`: `survey` \| `apply` overrides defaults. See [category-input-schema.md](references/category-input-schema.md).

1. Parse [category-input-schema.md](references/category-input-schema.md). If `skip` or no actionable `failures`, emit survey no-op; stop.
2. Classify every item in `failures[]` per [common-checklist.md](references/common-checklist.md). Note `ignored[]` in Overview when non-empty.
3. At `L1`, emit survey shape with Candidates; load `assets/pr-body-template-survey.md` at synthesis; stop — no file edits.
4. At `L2`/`L3`, fix the first `regression` only when more than three failures are present; defer the rest within [category-scope.md](references/category-scope.md).
5. When infra/env/flake or >5 files are required, classify as Watch with no edits.
6. Run validation per [category-validation-commands.md](references/category-validation-commands.md); record outcome in Session Metrics.
7. Emit apply shape per [common-output-format.md](references/common-output-format.md); reconcile Changes / Deferred with `git diff --name-only`; load `assets/pr-body-template.md` at synthesis.

### Error Handling

| Condition                            | Severity    | Action                                                |
| ------------------------------------ | ----------- | ----------------------------------------------------- |
| `skip` or no actionable `failures`   | Info        | Outcome `no actionable failures`; stop                |
| Infra/env/flake or >5 files required | Recoverable | Classify Watch; no edits                              |
| Validation tooling missing           | Recoverable | Defer Watch unless fixing one line from `log_excerpt` |
| Path outside allowlist               | Recoverable | Watch or defer; do not edit                           |
