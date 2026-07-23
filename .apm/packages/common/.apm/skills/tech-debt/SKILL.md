---
name: tech-debt
description: >-
  Discover and classify technical debt from mechanical signals, apply closed-set
  fixes when requested, and publish structured reports under docs/report/tech-debt/.
  Use for scheduled loop scans, ad-hoc surveys from detection JSON, or when the user
  asks to fix safe documentation/dependency debt. Delegate structural work to refactor.
  Preferred via on-loop-tech-debt.yaml.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "2.0.0"
---

## Input

Injected JSON from loop-prompt-generate — see [category-input-schema.md](references/category-input-schema.md). Path allowlist and denylist arrive in the prompt `## Constraints` section (caller `LOOP_ALLOWLIST`, `LOOP_DENYLIST`).

Interactive runs may pass `mode: survey | apply` or use natural language (洗い出し → survey; 直して → apply).

## Operating levels

`level` arrives in injected JSON — see [category-input-schema.md#operating-levels](references/category-input-schema.md#operating-levels).

## Output Specification

Survey and apply use **different** Summary shapes — do not mix. See [common-output-format.md](references/common-output-format.md) and [common-loop-triage-format.md](references/common-loop-triage-format.md).

Loop: survey loads `assets/pr-body-template-survey.md`; apply loads `assets/pr-body-template.md`.

## Execution Scope

### USE FOR:

- Classify mechanical `signals[]` and `hotspots[]` into prioritized debt findings
- Survey: emit Candidates with Delegate hints (`refactor`, `docs-updater`, `self`, `human`)
- Apply: write `report_file` at L2/L3; apply closed-set fixes (`broken_doc_ref`, `stale_doc`, simple `pin_drift`) within allowlist

### DO NOT USE FOR:

- Structural refactors or architecture changes (use refactor)
- CI repair (use ci-sweeper)
- Security remediation beyond reporting
- Edit loop state files (bundled by finalize after verification)

## Reference Files Guide

- [category-debt-taxonomy.md](references/category-debt-taxonomy.md) (always read)
- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-input-schema.md](references/category-input-schema.md) (always read)
- [common-loop-triage-format.md](references/common-loop-triage-format.md) (always read)
- [common-loop-pr-body-contract.md](references/common-loop-pr-body-contract.md) (always read)
- `assets/pr-body-template-survey.md` (always read — loop L1 survey path)
- `assets/pr-body-template.md` (always read — loop L2/L3 apply path)
- Previous report at `previous_report` (always read when path exists)

## Workflow

Every run has **Phase A — Survey** (classify all signals). **Phase B — Apply** runs only when mode is `apply` and level allows edits.

### Mode resolution

| Source         | Default mode | Survey-only triggers                           |
| -------------- | ------------ | ---------------------------------------------- |
| Interactive    | `survey`     | Default unless user asks to fix/apply/直して   |
| Loop `L1`      | `survey`     | Always — no file edits                         |
| Loop `L2`/`L3` | `apply`      | `skip: true` or empty signals/hotspots → no-op |

Explicit JSON `mode`: `survey` | `apply` overrides defaults.

### Phase A — Survey (always)

1. Parse [category-input-schema.md](references/category-input-schema.md). Read `## Constraints` for allowlist. If `skip` or both `signals` and `hotspots` are empty, emit survey no-op; stop.
2. Read `previous_report` when set. Compare per [common-checklist.md](references/common-checklist.md#previous-report-comparison).
3. For each signal/hotspot, read ±30 lines. Classify per [category-debt-taxonomy.md](references/category-debt-taxonomy.md). Assign Delegate per row.
4. At `L1` or `mode: survey`, emit **survey** shape per [common-output-format.md](references/common-output-format.md); load `assets/pr-body-template-survey.md` at synthesis; stop — no file edits.

### Phase B — Apply (`mode: apply`, L2/L3)

1. Write `report_file` within allowlist with full persisted structure (Critical / High-Priority / Watch sections per taxonomy).
2. Apply closed-set fixes only per [category-scope.md](references/category-scope.md).
3. Emit one **apply** shape only: `### Changes`, `### Deferred`; omit `### Candidates` / `### Watch`. Reconcile with `git diff --name-only`.
4. Load `assets/pr-body-template.md` at synthesis.

### Error Handling

| Condition                                 | Severity    | Action                                                          |
| ----------------------------------------- | ----------- | --------------------------------------------------------------- |
| `skip` or empty signals/hotspots          | Info        | Survey no-op; stop                                              |
| Path outside allowlist/denylist           | Recoverable | Classify Watch; do not edit                                     |
| `previous_report` path missing            | Recoverable | Skip comparison; note in Overview                               |
| Cap exceeded (>25 Critical+High-Priority) | Recoverable | Retain Critical first; defer overflow to Watch; note truncation |
