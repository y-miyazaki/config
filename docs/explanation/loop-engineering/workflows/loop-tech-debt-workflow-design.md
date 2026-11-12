# Report Tech Debt Workflow Design

Workflow and domain design for the `tech-debt` loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-tech-debt.yaml` · skill `tech-debt` · `tech-debt/scripts/detect_tech_debt.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Run a full-repository mechanical technical-debt scan, classify findings via the skill taxonomy, and open an L2 merge-gated PR that writes a dated report under `docs/report/tech-debt/`.

### Report loop family

Report loops emit structured artifacts under `docs/report/<domain>/` via merge-gated PRs (dogfood: `loop_name: tech-debt`, skill `tech-debt`).

**Action loops** (`docs-updater`, `ci-sweeper`, `refactor`) modify application or documentation source to fix drift or failures. Report loops classify mechanical signals and publish reports only — they do not edit source outside the report allowlist.

| Loop           | Skill          | Role                                              | Trigger                     |
| -------------- | -------------- | ------------------------------------------------- | --------------------------- |
| `tech-debt`    | `tech-debt`    | Cron loop: detect signals + skill classify/report | `on-loop-tech-debt.yaml`    |
| `docs-updater` | `docs-updater` | Action loop: doc drift detect + fix PR            | `on-loop-docs-updater.yaml` |
| `ci-sweeper`   | `ci-sweeper`   | Action loop: CI failure detect + fix PR           | `on-loop-ci-sweeper.yaml`   |
| `refactor`     | `refactor`     | Action loop: H1 structural refactor fix PR        | `on-loop-refactor.yaml`     |

Detect script path: **`tech-debt/scripts/detect_tech_debt.sh`** (under `repo-maintenance` package).

Skill execution boundaries: `tech-debt` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

### Related action loops

`refactor` is an **action loop** that applies O1/O2 structural refactors via fix PRs — not a report-only loop. It may consume report findings as input context but belongs alongside docs-updater and ci-sweeper, not tech-debt. See [Refactor Workflow Design](loop-refactor-workflow-design.md).

### Modes

| Mode           | Default | Behavior                                          |
| -------------- | ------- | ------------------------------------------------- |
| `integration`  | on      | Detect on watch branch → report PR to same branch |
| `pull_request` | off     | not supported for this loop                       |

## Use cases

| Use case                         | Trigger                                                                                                                                                                        | Outcome                                                                                                                                               | Transition |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| Weekly technical-debt report     | Weekly `schedule` (Monday 08:00 UTC) or `workflow_dispatch`; the repository-wide sensors (shell, Go, Terraform, workflow, dependency) return mechanical debt signals on `main` | `signals[]` and `hotspots[]` classified into prioritized findings with evidence, written to `docs/report/tech-debt/YYYY-MM-DD.md` in one L2 review PR | S0 -> S1   |
| Compare with the previous report | Detect returns a non-empty `previous_report`                                                                                                                                   | The report lists resolved, recurring, and regression items                                                                                            | S0 -> S1   |

## Out of scope

- Code fixes, refactors, or dependency upgrades (report loop; the only edits besides the report are the closed-set fixes `broken_doc_ref`, `stale_doc`, and simple `pin_drift` on allowlisted documentation or manifest paths)
- GitHub Issue creation at any level (log + state + report PR only)
- L1 log-only observation phase (skipped — **L2 from start**)
- CVE database lookups or duplicate lint enforcement already covered by CI
- Hook-triggered or user-invoked debt scans
- Loop state and detect script management

## State model

The loop uses the shared states `S0`–`S5` from [Loop Workflow Design Template](loop-workflow-design-template.md#scheduled-loop-states) for its one target key, `integration:main` in `.loop/state-tech-debt.json` on `state_branch`. The output is a report, so a merge records findings without resolving them; one row differs from the template:

| ID  | State                                 | Trigger                                                                       | Next state                                                                     |
| --- | ------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| S2a | Report merged (signals still present) | A person merges the report PR; `on-loop-state-promote` promotes `pending.sha` | S0 on the next tick: detect scans the full repository again, not the new range |

The values that hold each state in this loop:

| State | Values in this loop                                                                                                                                                                     |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S0    | Detect returns `skip: false`: the repository-wide sensors return signals on `main`, whatever `last_sha` is                                                                              |
| S1    | The report PR carries `loop-automation`; `pending` holds `{ sha, pr, … }`; run-log `pr_created`                                                                                         |
| S2a   | `on-loop-state-promote` sets `last_sha` to `pending.sha`, removes `pending`, and sets `outcome` `pr_merged` and `consecutive_failures` `0`; the merged report becomes `previous_report` |
| S3    | `on-loop-state-promote` removes `pending` and sets `outcome` `pr_closed`; `last_sha` does not change and `consecutive_failures` rises by 1 (a close counts as a failure)                |
| S4    | The PR stays open; every tick records run-log `skipped` with `skip_reason` `pending_pr`                                                                                                 |
| S5    | `consecutive_failures` is 3 or more and `last_run` is under 30 days old; each tick within 30 days of `last_run` records run-log `skipped` with `skip_reason` `circuit_breaker`          |

The loop never reaches S2 (target resolved): signals leave the report only when a person or another loop fixes them. A run that opens no PR (checker `REJECT`, no report written, agent error) leaves the target in S0. Only `rejected` raises `consecutive_failures`; the third one moves the target to S5. Retry limits and resets are in [State delivery](#state-delivery).

## User actions

Each row is one action a person can take on the loop's output, the loop response, and what the person sees next. The Transition column references [State model](#state-model).

| User action                                                                                    | Loop response                                                                                                                                                                                                                                 | Values changed                                                                                                                                                                          | Result and next action                                                                                               | Transition      |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | --------------- |
| Merge the report PR                                                                            | `on-loop-state-promote` (`pull_request_target` `closed`, job gated on `loop-automation`) promotes the pending state                                                                                                                           | `last_sha` = `pending.sha`; `pending` removed; `outcome` `pr_merged`; `consecutive_failures` `0`; `open_rejections` `[]`                                                                | The dated report lands under `docs/report/tech-debt/`. Act on its findings; the next Monday tick writes a new report | S1 -> S2a -> S0 |
| Close the report PR without merging                                                            | `on-loop-state-promote` clears the pending state                                                                                                                                                                                              | `pending` removed; `outcome` `pr_closed`; `last_sha` and `consecutive_failures` unchanged                                                                                               | No report lands; `previous_report` stays the last merged one. The next tick writes a new dated report                | S1 -> S3 -> S0  |
| Delete the loop branch of an open report PR                                                    | GitHub closes the PR, and `on-loop-state-promote` clears the pending state                                                                                                                                                                    | As for closing the PR                                                                                                                                                                   | As for closing the PR                                                                                                | S1 -> S3 -> S0  |
| Leave the report PR open                                                                       | Each tick runs detect, which finds the open `pending.pr` and skips; `record-skip` appends the run log                                                                                                                                         | Run-log `skipped`, `skip_reason` `pending_pr`                                                                                                                                           | No new report opens until the PR is merged or closed                                                                 | S1 -> S4        |
| Push commits to the report PR branch                                                           | Nothing runs                                                                                                                                                                                                                                  | Branch and PR head only; `pending.sha` keeps the detect SHA                                                                                                                             | Merging promotes `pending.sha`, so the person's commits land with the PR                                             | -               |
| Push to `main` while a run is queued or running                                                | The run keeps the detect SHA; the report describes the repository at that SHA                                                                                                                                                                 | None beyond the run's own values                                                                                                                                                        | The next report picks the push up                                                                                    | -               |
| Comment on, review, or resolve a thread on the report PR                                       | Nothing runs in this loop. A `@loop` mention follows the intake of [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md)                                                                                                      | None in this loop                                                                                                                                                                       | Edit the PR by hand, or close it                                                                                     | -               |
| Remove `loop-automation` from the report PR                                                    | Nothing runs now. When the PR later closes, the `on-loop-state-promote` job `if` refuses it                                                                                                                                                   | Label only; `pending` stays and `last_sha` does not advance                                                                                                                             | Detect treats a closed or merged `pending.pr` as stale and runs as usual; `last_sha` is only a label for this loop   | -               |
| Start `workflow_dispatch` (no inputs)                                                          | Same as a scheduled tick; it waits in the concurrency group `loop-state-main`                                                                                                                                                                 | As for a tick: a new PR and `pending`, or run-log `skipped` (`no_changes`, `pending_pr`, `circuit_breaker`, `budget`); only runs that start the agent count toward the budget           | The daily cap is `2`                                                                                                 | S0 -> S1        |
| Re-run a failed run from the Actions page                                                      | Detect runs again against the current `main` and the current state                                                                                                                                                                            | As for a new tick                                                                                                                                                                       | As for `workflow_dispatch`                                                                                           | -               |
| Reset the circuit breaker by a PR to `main` that edits `.loop/state-tech-debt.json`            | Nothing runs on merge; the next tick reads the new state                                                                                                                                                                                      | `consecutive_failures` set to `0` (or the target key removed)                                                                                                                           | The next tick detects again. Fix the cause of the rejections first                                                   | S5 -> S0        |
| Change `.loop/loop-budget.json`, `detect_env_json`, or the caller inputs by PR after a failure | Nothing runs on merge. The next tick uses the new values                                                                                                                                                                                      | `.loop/loop-budget.json` caps (they override caller `budget_*`); caller inputs; report location (`TECH_DEBT_DIR`, aligned with `agent_edit_allowlist` and `agent_checker_path_pattern`) | Start `workflow_dispatch` to apply them now                                                                          | -               |
| Do nothing (no debt signals)                                                                   | Each tick runs detect, which returns `skip: true`                                                                                                                                                                                             | Run-log `skipped`, `skip_reason` `no_changes`                                                                                                                                           | -                                                                                                                    | -               |
| Commits and PRs that the loop or other loops create (state, run log, the report PR merge)      | Nothing runs: the workflow has only `schedule` and `workflow_dispatch` triggers, and the sensors skip the report tree (`REPO_PATHS_EXTRA_PRUNES` defaults to the parent of `TECH_DEBT_DIR`, `docs/report`), so a merged report adds no signal | None                                                                                                                                                                                    | -                                                                                                                    | -               |

Not applicable: 3, 5 — the loop uses no mention token and reads or writes no Issue (it never creates Issues).

## Unhandled cases

| Case                                                  | Why nothing follows                                                                                                                                                                                                                                                                                            | Disposition |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| The circuit breaker stops the loop                    | Recovers on its own: once `last_run` is older than 30 days, detect lets one run through (`target_circuit_breaker_open` in `guards.sh`); a `rejected` result reopens the breaker for another 30 days, any other result closes it. No notification: the trip shows only as run-log `skipped` (`circuit_breaker`) | Limitation  |
| A person closes the report PR to decline it           | A weekly report is the intended output, so the next tick writes a new one; closing declines only that week's report                                                                                                                                                                                            | Accepted    |
| A person removes `loop-automation` from the report PR | `on-loop-state-promote` skips the PR and `pending` stays. Detect treats a closed or merged `pending.pr` as stale, and the full scan ignores `last_sha`, so the next tick runs as usual                                                                                                                         | Accepted    |
| A person acts on the findings (fixes or files Issues) | The loop does not track findings between reports; the next report shows a fixed item as resolved by comparing with `previous_report`                                                                                                                                                                           | Accepted    |
| A person pushes to `main` during a run                | The report describes the detect SHA; the next report covers the push                                                                                                                                                                                                                                           | Accepted    |
| A person comments on or reviews the report PR         | The loop reads no PR comments; the person edits the PR or closes it                                                                                                                                                                                                                                            | Accepted    |

## Failure and recovery

| Failure kind                                        | How it is recorded                                                                                                     | Who acts   | What they do                                                                             | How the loop resumes                                                           |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Detect script fails                                 | The `detect` job fails; no state write and no run-log row                                                              | Maintainer | Fix the script, a sensor, or the environment                                             | The next tick runs the full scan again                                         |
| Checker `REJECT`, or no report file despite signals | Run-log `rejected`; state `outcome` `rejected`, `last_reject_reason`, `consecutive_failures` + 1; agent branch deleted | Maintainer | Read the reason; adjust `agent_maker_instructions` or `agent_checker_instructions` by PR | The next tick retries; the third `rejected` in a row moves to S5               |
| Agent or push error                                 | Run-log `error`; `consecutive_failures` unchanged                                                                      | Maintainer | Fix the cause                                                                            | The next tick or `workflow_dispatch` retries                                   |
| Circuit breaker open                                | Run-log `skipped`, `skip_reason` `circuit_breaker` on every tick until 30 days after `last_run`                        | Maintainer | Fix the cause, then reset `consecutive_failures` in `.loop/state-tech-debt.json` by PR   | The next tick after the merge (S5 -> S0)                                       |
| Daily budget used up                                | Run-log `skipped`, `skip_reason` `budget`                                                                              | Maintainer | Wait, or raise the cap in `.loop/loop-budget.json` by PR                                 | The next tick or `workflow_dispatch`                                           |
| State promote fails after a merge                   | The `on-loop-state-promote` run fails; `pending` stays with a merged `pending.pr`                                      | Maintainer | Re-run the failed `on-loop-state-promote` run                                            | Detect treats the stale `pending` as not blocking; the next tick runs as usual |

## Caller inputs

Keys are passed in `on-loop-tech-debt.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_checker_instructions`, `agent_maker_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

Schedule: **`0 8 * * 1`** (Monday 08:00 UTC, weekly).

| Input / JSON key             | Description                                                                                                                                                                                                               | Dogfood value                                                    |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `agent_maker_max_turns`      | Max maker agent turns per loop attempt (one Agent→Verify cycle).                                                                                                                                                          | `100`                                                            |
| `agent_maker_model`          | Maker model ID. Cursor: `agent --list-models`.                                                                                                                                                                            | `claude-sonnet-5`                                                |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                              | `medium`                                                         |
| `agent_loop_max_attempts`    | Max Agent→Verify retry cycles before finalize records failure.                                                                                                                                                            | `3`                                                              |
| `agent_checker_instructions` | Checker APPROVE/REJECT rubric. Allowlisted paths only; closed-set fixes (`broken_doc_ref`, `stale_doc`, `pin_drift`) on docs/manifests; no invented paths; cap Critical+High at 25.                                       | Inline in caller workflow                                        |
| `agent_checker_max_turns`    | Max checker agent turns per verification.                                                                                                                                                                                 | `100`                                                            |
| `agent_checker_model`        | Checker model ID. Cursor: `agent --list-models`.                                                                                                                                                                          | `claude-opus-5`                                                  |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                            | `medium`                                                         |
| `agent_edit_allowlist`       | Comma-separated globs the maker may modify. Report path plus optional secondary closed-set fix paths (`docs/**/*.md`, `package.json`, `go.mod`).                                                                          | `docs/report/tech-debt/**/*.md,docs/**/*.md,package.json,go.mod` |
| `detect_branch_match`        | Comma-separated integration branch patterns to watch.                                                                                                                                                                     | `main`                                                           |
| `state_branch`               | Branch for `.loop/*` persistence, and state migration (it no longer doubles as a watch fallback).                                                                                                                         | `main`                                                           |
| `budget_max_runs_per_day`    | Daily run cap keyed by `loop_name`. Caller input; `.loop/loop-budget.json` overrides when present.                                                                                                                        | `2`                                                              |
| `budget_max_tokens_per_day`  | Daily aggregated token cap across loops.                                                                                                                                                                                  | `1000000`                                                        |
| `agent_edit_denylist`        | Comma-separated globs the maker must not touch.                                                                                                                                                                           | `**/.env,**/credentials*,**/secrets*,src/**,.github/**`          |
| `detect_script`              | Domain detect script path.                                                                                                                                                                                                | `.agents/skills/tech-debt/scripts/detect_tech_debt.sh`           |
| `agent_engine`               | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                                                                                     | `claude`                                                         |
| `environment`                | GitHub Environment for env-scoped secrets inside the reusable workflow. Leave `default` when repository secrets suffice.                                                                                                  | `default`                                                        |
| `delivery`                   | Platform delivery after APPROVE (`pr_create` for dogfood).                                                                                                                                                                | `pr_create`                                                      |
| `agent_checker_path_pattern` | Extended regex to infer file paths from checker text.                                                                                                                                                                     | See caller workflow                                              |
| `level`                      | Autonomy level (`L1`, `L2`, `L3`). **L2 from start** — no L1 phase.                                                                                                                                                       | `L2`                                                             |
| `loop_name`                  | Loop identifier; state file `.loop/state-tech-debt.json`.                                                                                                                                                                 | `tech-debt`                                                      |
| `detect_max_targets`         | Max targets per cron tick after priority filters.                                                                                                                                                                         | `1`                                                              |
| `agent_unchanged_verdict`    | `APPROVE` or `REJECT` when maker produces no file diff. **REJECT** when signals present but no report file written.                                                                                                       | `REJECT`                                                         |
| `pr_body`                    | Optional static prefix (dogfood: `""`). `loop-finalize` composes agent Overview/Summary + mechanical sections. See [Loop PR Body Readable Design](../../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md). | `""`                                                             |
| `detect_pr_enabled`          | Enumerate open PR heads. tech-debt uses integration branches only.                                                                                                                                                        | `false`                                                          |
| `pr_title`                   | PR title when `delivery` is `pr_create`.                                                                                                                                                                                  | `docs(tech-debt): technical debt report (loop-tech-debt)`        |
| `agent_maker_instructions`   | Domain instructions: classify signals; write dated report; compare previous report.                                                                                                                                       | Inline in caller workflow                                        |
| `agent_maker_skill_name`     | Skill package to invoke.                                                                                                                                                                                                  | `tech-debt`                                                      |
| `agent_tool_allowlist`       | Tool permission rules for the maker                                                                                                                                                                                       | `git remote get-url`                                             |
| `agent_edit_target`          | Agent artifact when `agent_edit_allowed` is true (`report` for this loop).                                                                                                                                                | `report`                                                         |
| `agent_report_check`         | Deterministic check of the maker report before the checker (`paths`: `### Changes` lists repository paths).                                                                                                               | `paths`                                                          |

The prompt key `agent_edit_allowed` is not a caller input: the platform derives it from `level` (`true` at L2 and L3). `on-loop-tech-debt.yaml` does not set `environment`, so the caller default `default` applies.

### Domain detect environment (`detect_env_json`)

Dogfood passes `{}` — defaults match the layout below. Override paths when changing report location (align `agent_edit_allowlist` / `agent_checker_path_pattern`).

```yaml
detect_env_json: >-
  {"TECH_DEBT_DIR":"docs/report/tech-debt"}
```

| JSON key / env var             | Description                                                | Dogfood value           |
| ------------------------------ | ---------------------------------------------------------- | ----------------------- |
| `TECH_DEBT_DIR`                | Report output directory                                    | `docs/report/tech-debt` |
| `TECH_DEBT_LEGACY_SEARCH_DIRS` | Comma-separated prior-report search roots                  | `docs/report/tech-debt` |
| `TECH_DEBT_DATE_FORMAT`        | UTC `strftime` for report basename                         | `%Y-%m-%d`              |
| `TECH_DEBT_FILE_EXTENSION`     | Report filename extension (include dot)                    | `.md`                   |
| `TECH_DEBT_PREVIOUS_GLOB`      | Glob for prior reports under search dirs                   | `????-??-??.md`         |
| `REPO_PATHS_EXTRA_PRUNES`      | Optional extra detect prune roots (default: report parent) | unset                   |

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_tech_debt.sh` with `targets["integration:<branch>"].last_sha`.

Detect script outputs **mechanical signals** (not semantic findings):

| Field               | Role                                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------ |
| `signals[]`         | Mechanical debt indicators from repo-wide sensors                                                            |
| `hotspots[]`        | Aggregated high-density paths or categories                                                                  |
| `warnings[]`        | Non-blocking sensor or scope warnings                                                                        |
| `skip`              | `true` when no debt signals warrant a run                                                                    |
| `agent_report_file` | Target path: `<TECH_DEBT_DIR>/<UTC-date>.md` (defaults under `docs/report/tech-debt/`)                       |
| `previous_report`   | Latest dated report under `TECH_DEBT_DIR` plus optional `TECH_DEBT_LEGACY_SEARCH_DIRS`; empty string if none |

**Default scope:** full repository (sensors read source for evidence; `docs/report/**` excluded from sensors per skill references). `loop-detect` passes `--scope range --since <last_sha>`, but the script uses the range only as the `commit_range` label: every tick scans the full repository.

**Skill** (`tech-debt`) classifies signals into prioritized findings and writes `agent_report_file` at L2.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `delivery` = `pr_create`

### Stable filters (detect only)

- Circuit breaker on `targets[key].consecutive_failures`
- Budget (platform)

No infra/env classification — not applicable.

### State fields (per target key)

| Field                  | Role                                                                  |
| ---------------------- | --------------------------------------------------------------------- |
| `last_sha`             | Scan cursor; advances when report PR merges (`on-loop-state-promote`) |
| `pending`              | Written at finalize on `pr_create`; promoted to `last_sha` on merge   |
| `outcome`              | `pr_created`, `rejected`, `unchanged`, …                              |
| `consecutive_failures` | Circuit breaker                                                       |

No `workflow_run_id` / ci ledger.

## Execute

- Worktree from `target.from` on integration branch
- Checker diff baseline: `to.branch`
- `verifier_context`: detect signal summary (counts, hotspots, warnings). Platform always wires; may be brief

### Skill

- Read `signals[]`, `hotspots[]`, `warnings[]`, `agent_report_file`, `previous_report` from detect JSON
- Classify per skill `category-debt-taxonomy.md` and `common-checklist.md`
- At **L2**, write full report to `agent_report_file` within allowlist
- Emit session summary always (per `common-output-format.md`)
- Cap **Critical + High** findings at 25 per report
- Do not create GitHub Issues

### Checker rubric outline

Inline in caller `agent_checker_instructions` (must match `on-loop-tech-debt.yaml`):

- **APPROVE** when all of the following hold:
  1. Changes stay under the allowlist (`docs/report/tech-debt/**/*.md`, `docs/**/*.md`, `package.json`, `go.mod`)
  2. Report content matches the provided detect signals and hotspots
  3. File paths cited in the report exist in the repository
  4. Critical + High findings count is at most 25
  5. No denylist paths were modified
  6. Closed-set fixes (`broken_doc_ref`, `stale_doc`, simple `pin_drift`) only on allowlisted documentation or manifest paths
- **REJECT** when any of the following hold: no report file written despite non-empty signals; invented or non-existent paths in the report; changes outside the allowlist or denylist modifications; semantic claims unsupported by cited evidence; structural or security debt edited instead of reported

## Finalize

PR body is composed by `loop-finalize` from agent `## Overview` / `## Summary` (skill-owned) plus mechanical sections. Dogfood sets `pr_body: ""`. See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

Always `delivery: pr_create` to `to.branch` at L2. Other deliveries (`pr_push`) are not used by this loop.

No `finalize_script`.

**Merge-gated cursor:** Same platform rule as all L2 `pr_create` loops — `pending` at finalize, `last_sha` on report PR merge via `on-loop-state-promote.yaml`. See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy).

## State delivery

See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) for platform rules.

**Target (dogfood):** merge-gated `pending` + `on-loop-state-promote` — same as changelog and docs-updater.

Persistence: `state-tech-debt.json` on `state_branch` via [finalize inside ci-loop-agent](../loop-caller-workflows-design.md#finalize-inside-ci-loop-agent).

### Retry limits and circuit breaker

| Value                     | Rule                                                                                                                                                                                                                                       |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `agent_loop_max_attempts` | Agent→Verify cycles inside one run (`3`); the last verdict decides the run outcome                                                                                                                                                         |
| `consecutive_failures`    | `loop-finalize` adds 1 on `rejected`, keeps it on `error`, and sets it to `0` on any other outcome; `on-loop-state-promote` sets it to `0` on merge and leaves it on close                                                                 |
| Circuit breaker           | `loop-detect` skips the target with `skip_reason` `circuit_breaker` when `consecutive_failures` is 3 or more and `last_run` is less than 30 days old                                                                                       |
| Cooldown                  | On a finalize state write, an `integration:*` key whose `outcome` is `rejected` or `pr_closed` and whose `last_run` is older than 30 days gets `consecutive_failures` `0`; no state write happens while the breaker blocks the only target |
| Pending PR                | `loop-detect` skips the target with `skip_reason` `pending_pr` while `pending.pr` is open (or its state cannot be read); a closed or merged `pending.pr` is treated as stale                                                               |
| Concurrency               | Workflow group `loop-state-main` (`cancel-in-progress: false`, `queue: max`), shared with the other scheduled loops and `on-loop-state-promote`                                                                                            |

## Implementation Checklist

Shared platform: [Multi-Branch — Shared platform checklist](../multi-branch-loops-design.md#shared-platform-checklist-all-loops).

### Loop-specific

- [x] `tech-debt/scripts/detect_tech_debt.sh` (facts output)
- [x] `on-loop-tech-debt.yaml` dogfood caller via `ci-loop-caller`
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.signals` branch)
- [x] Skill consolidated into `repo-maintenance`: `tech-debt` (was `loop-tech-debt` / `loop-report-tech-debt`)
- [x] `.loop/loop-budget.json` entry for `tech-debt`

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
