# Report Tech Debt Workflow Design

Workflow and domain design for the `loop-tech-debt` (`tech-debt`) loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-tech-debt.yaml` · skill `loop-tech-debt` · `scripts/detect_tech_debt.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Run a full-repository mechanical technical-debt scan, classify findings via the skill taxonomy, and open an L2 merge-gated PR that writes a dated report under `docs/report/tech-debt/`.

### Supported use cases

- Weekly cron scan of `main` for mechanical debt signals (shell, Go, Terraform, workflow, dependency sensors)
- Classify `signals[]` and `hotspots[]` into prioritized findings with evidence
- Write `docs/report/tech-debt/YYYY-MM-DD.md` via L2 review PR
- Compare against `previous_report` for resolved, recurring, and regression items

### Out of scope

- Code fixes, refactors, or dependency upgrades (report-only loop)
- GitHub Issue creation at any level (log + state + report PR only)
- L1 log-only observation phase (skipped — **L2 from start**)
- CVE database lookups or duplicate lint enforcement already covered by CI
- Hook-triggered or user-invoked debt scans
- Loop state and detect script management

### Report loop family

Report loops use the **`loop-report-<domain>`** naming prefix (e.g. `loop-tech-debt`, future `loop-report-errors`). They emit structured artifacts under `docs/report/<domain>/` via merge-gated PRs.

**Action loops** (`loop-docs-triage`, `loop-ci-sweeper`, `loop-refactor`) modify application or documentation source to fix drift or failures. Report loops classify mechanical signals and publish reports only — they do not edit source outside the report allowlist.

| Package            | Role                                              | Trigger                    |
| ------------------ | ------------------------------------------------- | -------------------------- |
| `loop-tech-debt`   | Cron loop: detect signals + skill classify/report | `on-loop-tech-debt.yaml`   |
| `loop-docs-triage` | Action loop: doc drift detect + fix PR            | `on-loop-docs-triage.yaml` |
| `loop-ci-sweeper`  | Action loop: CI failure detect + fix PR           | `on-loop-ci-sweeper.yaml`  |
| `loop-refactor`    | Action loop: H1 structural refactor fix PR        | `on-loop-refactor.yaml`    |

Detect script path: **`loop-tech-debt/scripts/detect_tech_debt.sh`**.

Skill execution boundaries: `loop-tech-debt` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

### Modes

| Mode           | Default | Behavior                                          |
| -------------- | ------- | ------------------------------------------------- |
| `integration`  | on      | Detect on watch branch → report PR to same branch |
| `pull_request` | off     | not supported for this loop                       |

## Caller inputs

Keys are passed in `on-loop-tech-debt.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_verifier_criteria`, `prompt_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

Schedule: **`0 8 * * 1`** (Monday 08:00 UTC, weekly).

| Input / JSON key               | Description                                                                                                                                                                                                               | Dogfood value                                                                                   |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `agent_implementer_max_turns`  | Max implementer agent turns per loop attempt (one Agent→Verify cycle).                                                                                                                                                    | `5`                                                                                             |
| `agent_implementer_model`      | Implementer model ID. Cursor: `agent --list-models`.                                                                                                                                                                      | `cursor-grok-4.5-low`                                                                           |
| `agent_loop_max_attempts`      | Max Agent→Verify retry cycles before finalize records failure.                                                                                                                                                            | `3`                                                                                             |
| `agent_verifier_criteria`      | Verifier APPROVE/REJECT rubric. Report-only edits; no invented paths; cap Critical+High at 25.                                                                                                                            | Inline in caller workflow                                                                       |
| `agent_verifier_max_turns`     | Max verifier agent turns per verification.                                                                                                                                                                                | `3`                                                                                             |
| `agent_verifier_model`         | Verifier model ID. Cursor: `agent --list-models`.                                                                                                                                                                         | `composer-2.5`                                                                                  |
| `allowlist`                    | Comma-separated globs the implementer may modify. Must align with report path scope.                                                                                                                                      | `docs/report/tech-debt/**/*.md`                                                                 |
| `branch_match`                 | Comma-separated integration branch patterns to watch.                                                                                                                                                                     | `main`                                                                                          |
| `branch_state`                 | Branch for `.loop/*` persistence, state migration, and watch fallback.                                                                                                                                                    | `main`                                                                                          |
| `budget_max_runs_per_day`      | Daily run cap keyed by `loop_name`. Caller input; `.loop/loop-budget.json` overrides when present.                                                                                                                        | `2`                                                                                             |
| `budget_max_tokens_per_day`    | Daily aggregated token cap across loops.                                                                                                                                                                                  | `750000`                                                                                        |
| `denylist`                     | Comma-separated globs the implementer must not touch.                                                                                                                                                                     | `**/.env,**/credentials*,**/secrets*,**/migration/*.sql,**/infrastructure/**,src/**,.github/**` |
| `detect_domain_env_json`       | JSON object forwarded to detect script env. Optional `TECH_DEBT_*` keys override report paths; defaults match dogfood layout.                                                                                             | `'{}'`                                                                                          |
| `detect_script`                | Domain detect script path.                                                                                                                                                                                                | `.agents/skills/tech-debt/scripts/detect_tech_debt.sh`                                          |
| `engine`                       | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                                                                                     | `cursor`                                                                                        |
| `environment`                  | GitHub Environment for env-scoped secrets inside the reusable workflow. Leave `default` when repository secrets suffice.                                                                                                  | `default`                                                                                       |
| `finalize_integration`         | Finalize strategy for integration targets: `open_pr` or `push` (L3).                                                                                                                                                      | `open_pr` (platform default; omit in caller)                                                    |
| `infer_files_pattern`          | Extended regex to infer file paths from verifier text.                                                                                                                                                                    | See caller workflow                                                                             |
| `level`                        | Autonomy level (`L1`, `L2`, `L3`). **L2 from start** — no L1 phase.                                                                                                                                                       | `L2`                                                                                            |
| `loop_name`                    | Loop identifier; state file `.loop/state-tech-debt.json`.                                                                                                                                                                 | `tech-debt`                                                                                     |
| `max_targets_per_schedule`     | Max targets per cron tick after priority filters.                                                                                                                                                                         | `1`                                                                                             |
| `no_changes_verdict`           | `APPROVE` or `REJECT` when implementer produces no file diff. **REJECT** when signals present but no report file written.                                                                                                 | `REJECT`                                                                                        |
| `pr_body`                      | Optional static prefix (dogfood: `""`). `loop-finalize` composes agent Overview/Summary + mechanical sections. See [Loop PR Body Readable Design](../../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md). | `""`                                                                                            |
| `pr_enabled` / `pull_requests` | Enumerate open PR heads. tech-debt uses integration branches only.                                                                                                                                                        | `false`                                                                                         |
| `pr_title`                     | PR title when finalize strategy is `open_pr`.                                                                                                                                                                             | `docs(report): technical debt report`                                                           |
| `prompt_instructions`          | Domain instructions: classify signals; write dated report; compare previous report.                                                                                                                                       | Inline in caller workflow                                                                       |
| `skill_name`                   | Skill package to invoke.                                                                                                                                                                                                  | `tech-debt`                                                                                     |

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_tech_debt.sh` with `targets["integration:<branch>"].last_sha`.

Detect script outputs **mechanical signals** (not semantic findings):

| Field             | Role                                                                                                         |
| ----------------- | ------------------------------------------------------------------------------------------------------------ |
| `signals[]`       | Mechanical debt indicators from repo-wide sensors                                                            |
| `hotspots[]`      | Aggregated high-density paths or categories                                                                  |
| `warnings[]`      | Non-blocking sensor or scope warnings                                                                        |
| `skip`            | `true` when no debt signals warrant a run                                                                    |
| `report_file`     | Target path: `<TECH_DEBT_DIR>/<UTC-date>.md` (defaults under `docs/report/tech-debt/`)                       |
| `previous_report` | Latest dated report under `TECH_DEBT_DIR` plus optional `TECH_DEBT_LEGACY_SEARCH_DIRS`; empty string if none |

**Default scope:** full repository (sensors read source for evidence; `docs/report/**` excluded from sensors per skill references).

**Skill** (`loop-tech-debt`) classifies signals into prioritized findings and writes `report_file` at L2.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `finalize` = `open_pr`

No `detect_domain_env_json` keys required — caller passes `{}`.

### Stable filters (detect only)

- Circuit breaker on `targets[key].consecutive_failures`
- Budget (platform)

No infra/env classification — not applicable.

### State fields (per target key)

| Field                  | Role                                                                  |
| ---------------------- | --------------------------------------------------------------------- |
| `last_sha`             | Scan cursor; advances when report PR merges (`on-loop-state-promote`) |
| `pending`              | Written at finalize on `open_pr`; promoted to `last_sha` on merge     |
| `outcome`              | `pr-created`, `rejected`, `no-op`, …                                  |
| `consecutive_failures` | Circuit breaker                                                       |

No `workflow_run_id` / ci ledger.

## Execute

- Worktree from `target.from` on integration branch
- Verifier diff baseline: `to.branch`
- `verifier_context`: detect signal summary (counts, hotspots, warnings). Platform always wires; may be brief

## Finalize

PR body is composed by `loop-finalize` from agent `## Overview` / `## Summary` (skill-owned) plus mechanical sections. Dogfood sets `pr_body: ""`. See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

Always `open_pr` to `to.branch` at L2. L3 `push` rarely appropriate for report loops; if enabled, requires explicit promotion review.

No `domain_persistence_script`.

**Merge-gated cursor:** Same platform rule as all L2 `open_pr` loops — `pending` at finalize, `last_sha` on report PR merge via `on-loop-state-promote.yaml`. See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy).

## Skill

- Read `signals[]`, `hotspots[]`, `warnings[]`, `report_file`, `previous_report` from detect JSON
- Classify per skill `category-debt-taxonomy.md` and `common-checklist.md`
- At **L2**, write full report to `report_file` within allowlist
- Emit session summary always (per `common-output-format.md`)
- Cap **Critical + High** findings at 25 per report
- Do not create GitHub Issues

## Verifier rubric outline

Inline in caller `agent_verifier_criteria`:

- **APPROVE** when diff touches only `docs/report/tech-debt/**/*.md`, report content matches detect signals, paths cited in report exist in the repository, Critical+High count ≤ 25, and no denylist paths modified
- **REJECT** when no report file written despite non-empty signals, invented file paths, allowlist/denylist violations, or semantic claims unsupported by cited evidence

## State delivery

See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) for platform rules.

**Target (dogfood):** merge-gated `pending` + `on-loop-state-promote` — same as changelog and docs-triage.

Persistence: `state-tech-debt.json` on `branch_state` via [finalize inside ci-loop-agent](../loop-caller-workflows-design.md#finalize-inside-ci-loop-agent).

## Related action loops

`loop-refactor` is an **action loop** that applies O1/O2 structural refactors via fix PRs — not a member of the `loop-report-*` family. It may consume report findings as input context but belongs alongside `loop-docs-triage` and `loop-ci-sweeper`, not `loop-tech-debt`. See [Refactor Workflow Design](loop-refactor-workflow-design.md).

## Implementation Checklist

Shared platform contract — see [Multi-Branch Loops Design](../multi-branch-loops-design.md#implementation-phases).

### Platform (all loops)

- [x] `loop-tech-debt/scripts/detect_tech_debt.sh` (facts output)
- [x] `on-loop-tech-debt.yaml` dogfood caller via `ci-loop-caller`
- [x] `branch_match` + per-branch `targets["integration:<branch>"]`
- [x] State migration: flat `last_sha` removed (`targets` map only)
- [x] `target_matrix` through detect → matrix execute/finalize
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.signals` branch)
- [x] Merge-gated state via `on-loop-state-promote.yaml` (`pending` → `last_sha`)
- [x] Readable PR body: agent Overview/Summary + finalize Run Metadata (`render_pr_body.sh`, `loop-notify-pr`)

### Loop-specific

- [x] APM package rename: `loop-tech-debt` → `loop-tech-debt`
- [x] `.loop/loop-budget.json` entry for `tech-debt`

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
