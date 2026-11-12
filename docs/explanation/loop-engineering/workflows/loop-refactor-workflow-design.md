# Refactor Workflow Design

Workflow and domain design for the `refactor` action loop.

| Layer        | Document                                                                                                |
| ------------ | ------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                            |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md)                                      |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                |
| Skill spec   | [Refactor skill & loop design](../../../superpowers/specs/2026-07-21-refactor-skill-and-loop-design.md) |

**Artifacts:** `on-loop-refactor.yaml` · skill `refactor` · `refactor/scripts/detect_refactor.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Detect mechanical structure hints on integration branches and open fix PRs after bounded O1/O2 refactors. Each loop run **surveys all hints** in the detection envelope, then **applies every actionable candidate** in one Agent→Verify cycle.

### Separation from refactor skill

Detect script path: **`refactor/scripts/detect_refactor.sh`** (under `repo-maintenance` package).

Entry skill (`refactor`) handles interactive and loop paths: loop runs use **structural intent only**, survey all `hints[]`, apply every apply candidate, O2 cap. Architecture-improvement language in user prompts is out of scope for this loop.

### Modes

| Mode           | Default | Behavior                                       |
| -------------- | ------- | ---------------------------------------------- |
| `integration`  | on      | Detect on watch branch → fix PR to same branch |
| `pull_request` | off     | not supported for this loop                    |

## Use cases

| Use case                                 | Trigger                                                                                                                                                      | Outcome                                                                                                                                                   | Transition |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| Apply structural refactors from H1 hints | Weekly `schedule` (Sunday 10:00 UTC) or `workflow_dispatch`; detect finds H1 hints (`duplication_block`, `oversized_unit`) in files changed after `last_sha` | One L2 review PR to the watch integration branch that applies every actionable structural refactor from the surveyed hint set, with stack validation (A') | S0 -> S1   |
| Coordinate with peer loops               | Another loop holds the workflow concurrency group                                                                                                            | The run waits in the queue ([workflow concurrency](../multi-branch-loops-design.md#cross-loop-coordination-workflow-concurrency))                         | -          |

## Out of scope

- PR head healing (`detect_pr_enabled` default off)
- Interactive or architecture-improvement intent (O3 proposal path) — use skill `refactor` manually
- Lint/SAST smell scores as primary detect or repair mission
- `tech-debt` report input or Apply under `report-*` names
- Sonar CPD default-on (future caller opt-in for duplication only)

| `refactor` (in `repo-maintenance`) | Interactive / loop structural O1/O2 apply | User or `on-loop-refactor.yaml` |

## State model

The loop uses the shared states `S0`–`S5` from [Loop Workflow Design Template](loop-workflow-design-template.md#scheduled-loop-states) for its one target key, `integration:main` in `.loop/state-refactor.json` on `state_branch`. It adds no loop-specific rows. The values that hold each state in this loop:

| State | Values in this loop                                                                                                                                         |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S0    | Detect returns `skip: false`: at least one H1 hint in the files changed after `last_sha` that match `REFACTOR_SCAN_GLOBS`                                   |
| S1    | The fix PR carries `loop-automation`; `pending` holds `{ sha, pr, … }`; run-log `pr_created`                                                                |
| S2    | `on-loop-state-promote` sets `last_sha` to `pending.sha`, removes `pending`, and sets `outcome` `pr_merged` and `consecutive_failures` `0`                  |
| S3    | `on-loop-state-promote` removes `pending` and sets `outcome` `pr_closed`; `last_sha` and `consecutive_failures` do not change, so the next tick is S0 again |
| S4    | The PR stays open; every tick records run-log `skipped` with `skip_reason` `pending_pr`                                                                     |
| S5    | `consecutive_failures` is 3 or more; every tick records run-log `skipped` with `skip_reason` `circuit_breaker`                                              |

A run that opens no PR (checker `REJECT`, no diff, agent error) leaves the target in S0. Only `rejected` raises `consecutive_failures`; the third one moves the target to S5. Retry limits and resets are in [State delivery](#state-delivery).

## User actions

Each row is one action a person can take on the loop's output, the loop response, and what the person sees next. The Transition column references [State model](#state-model).

| User action                                                                                 | Loop response                                                                                                                                                                    | Values changed                                                                                                                                           | Result and next action                                                                                                         | Transition     |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------- |
| Merge the refactor PR                                                                       | `on-loop-state-promote` (`pull_request_target` `closed`, job gated on `loop-automation`) promotes the pending state                                                              | `last_sha` = `pending.sha`; `pending` removed; `outcome` `pr_merged`; `consecutive_failures` `0`; `open_rejections` `[]`                                 | The refactor lands. The next Sunday tick scans files changed after the new `last_sha`, which include the merged refactor       | S1 -> S2       |
| Close the refactor PR without merging                                                       | `on-loop-state-promote` clears the pending state                                                                                                                                 | `pending` removed; `outcome` `pr_closed`; `last_sha` and `consecutive_failures` unchanged                                                                | The next tick detects the same hints and opens a new refactor PR (see [Unhandled cases](#unhandled-cases))                     | S1 -> S3 -> S0 |
| Delete the loop branch of an open refactor PR                                               | GitHub closes the PR, and `on-loop-state-promote` clears the pending state                                                                                                       | As for closing the PR                                                                                                                                    | As for closing the PR                                                                                                          | S1 -> S3 -> S0       |
| Leave the refactor PR open                                                                  | Each tick runs detect, which finds the open `pending.pr` and skips; `record-skip` appends the run log                                                                            | Run-log `skipped`, `skip_reason` `pending_pr`                                                                                                            | No new PR opens until the PR is merged or closed                                                                               | S1 -> S4       |
| Push commits to the refactor PR branch                                                      | Nothing runs                                                                                                                                                                     | Branch and PR head only; `pending.sha` keeps the detect SHA                                                                                              | Merging promotes `pending.sha`, so the person's commits land with the PR                                                       | -              |
| Push to `main` while a run is queued or running                                             | The run keeps the detect SHA; finalize opens the PR from the agent branch based on that SHA                                                                                      | None beyond the run's own values                                                                                                                         | When the push edits the same files, GitHub shows a conflict on the PR; resolve it on the PR branch                             | -              |
| Comment on, review, or resolve a thread on the refactor PR                                  | Nothing runs in this loop. A `@loop` mention follows the intake of [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md)                                         | None in this loop                                                                                                                                        | Edit the PR by hand, or close it                                                                                               | -              |
| Remove `loop-automation` from the refactor PR                                               | Nothing runs now. When the PR later closes, the `on-loop-state-promote` job `if` refuses it                                                                                      | Label only; `pending` stays and `last_sha` does not advance                                                                                              | Detect treats a closed or merged `pending.pr` as stale and scans the old range again (see [Unhandled cases](#unhandled-cases)) | -              |
| Start `workflow_dispatch` (no inputs)                                                       | Same as a scheduled tick; it waits in the concurrency group `loop-state-main`                                                                                                    | As for a tick: a new PR and `pending`, or run-log `skipped` (`no_changes`, `pending_pr`, `circuit_breaker`, `budget`); only runs that start the agent count toward the budget | The daily cap is `1`, so a dispatch on a day on which a run already started the agent is skipped with `budget`                                         | S0 -> S1       |
| Re-run a failed run from the Actions page                                                   | Detect runs again against the current `main` and the current state                                                                                                               | As for a new tick                                                                                                                                        | As for `workflow_dispatch`                                                                                                     | -              |
| Reset the circuit breaker by a PR to `main` that edits `.loop/state-refactor.json`          | Nothing runs on merge; the next tick reads the new state                                                                                                                         | `consecutive_failures` set to `0` (or the target key removed); `last_sha` kept or moved by hand                                                          | The next tick detects again. Fix the cause of the rejections first                                                             | S5 -> S0       |
| Change `.loop/loop-budget.json` or the caller inputs by PR after a failure                  | Nothing runs on merge. The next tick uses the new values                                                                                                                         | `.loop/loop-budget.json` caps (they override caller `budget_*`); caller inputs                                                                           | Start `workflow_dispatch` to apply them now                                                                                    | -              |
| Do nothing (no changed files with hints)                                                    | Each tick runs detect, which returns `skip: true`                                                                                                                                | Run-log `skipped`, `skip_reason` `no_changes`                                                                                                            | -                                                                                                                              | -              |
| Commits and PRs that the loop or other loops create (state, run log, the refactor PR merge) | Nothing runs on them: the workflow has only `schedule` and `workflow_dispatch` triggers. The next range includes the merged refactor, so detect scans the files it changed again | None                                                                                                                                                     | A hint that remains after the refactor is reported again                                                                       | -              |

Not applicable: 3, 5 — the loop uses no mention token and reads or writes no Issue.

## Unhandled cases

| Case                                                                             | Why nothing follows                                                                                                                                                                                                                                                                                                      | Disposition |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------- |
| A person closes the refactor PR to decline it                                    | `last_sha` stays, so the next tick finds the same hints and opens a refactor PR again. `on-loop-state-promote` does not raise `consecutive_failures` on close (the `pr_closed` count in `write_state.sh` never runs for a close), so the PR comes back every week. The only way to decline is to edit `last_sha` by hand | Follow-up   |
| The circuit breaker stops the loop                                               | Nothing tells a person: the trip shows only as run-log `skipped` (`circuit_breaker`). The 30-day cooldown in `prune_targets.sh` runs only inside a finalize state write, which never happens while the breaker blocks the only target, so the stop lasts until a person edits the state file                             | Follow-up   |
| A person removes `loop-automation` from the refactor PR                          | `on-loop-state-promote` skips the PR, so a merge never advances `last_sha`. Detect treats the closed `pending.pr` as stale and scans the old range again                                                                                                                                                                 | Follow-up   |
| A hint stays after its refactor merges (for example a file still over 400 lines) | The merged commit is in the next range, so the same hint returns. When the maker finds nothing more to apply, `agent_unchanged_verdict: REJECT` records `rejected`, and three such weeks trip the breaker                                                                                                                | Follow-up   |
| A person pushes to `main` during a run and edits the same files                  | The PR shows a conflict that the person resolves; the loop does not rebase                                                                                                                                                                                                                                               | Accepted    |
| A person comments on or reviews the refactor PR                                  | The loop reads no PR comments; the person edits the PR or closes it                                                                                                                                                                                                                                                      | Accepted    |
| CI fails on the refactor PR                                                      | This loop does not watch PR checks; repair belongs to `ci-sweeper` or a person ([Cross-Loop Note](#cross-loop-note))                                                                                                                                                                                                     | Accepted    |

## Failure and recovery

| Failure kind                                 | How it is recorded                                                                                                                           | Who acts   | What they do                                                                             | How the loop resumes                                                                                            |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Detect script fails                          | The `detect` job fails; no state write and no run-log row                                                                                    | Maintainer | Fix the script or the environment                                                        | The next tick retries from the same `last_sha`                                                                  |
| Checker `REJECT`, or the maker makes no diff | Run-log `rejected`; state `outcome` `rejected`, `last_reject_reason`, `consecutive_failures` + 1; `last_sha` unchanged; agent branch deleted | Maintainer | Read the reason; adjust `agent_maker_instructions` or `agent_checker_instructions` by PR | The next tick retries the same range; the third `rejected` in a row moves to S5                                 |
| Agent or push error                          | Run-log `error`; `consecutive_failures` unchanged                                                                                            | Maintainer | Fix the cause                                                                            | The next tick or `workflow_dispatch` retries                                                                    |
| Circuit breaker open                         | Run-log `skipped`, `skip_reason` `circuit_breaker` on every tick                                                                             | Maintainer | Fix the cause, then reset `consecutive_failures` in `.loop/state-refactor.json` by PR    | The next tick after the merge (S5 -> S0)                                                                        |
| Daily budget used up                         | Run-log `skipped`, `skip_reason` `budget`                                                                                                    | Maintainer | Wait, or raise the cap in `.loop/loop-budget.json` by PR                                 | The next tick or `workflow_dispatch`                                                                            |
| State promote fails after a merge            | The `on-loop-state-promote` run fails; `pending` stays with a merged `pending.pr`                                                            | Maintainer | Re-run the failed `on-loop-state-promote` run                                            | Detect treats the stale `pending` as not blocking, but scans from the old `last_sha` until the promote succeeds |

## Caller inputs

Keys are passed in `on-loop-refactor.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_checker_instructions`, `agent_maker_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

Schedule: **`0 10 * * 0`** (Sunday 10:00 UTC, weekly), plus `workflow_dispatch` with no inputs.

| Input / JSON key             | Description                                                                                                       | Dogfood value                                                                                    |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `agent_maker_max_turns`      | Max maker agent turns per loop attempt (one Agent→Verify cycle).                                                  | `100`                                                                                            |
| `agent_maker_model`          | Maker model ID. Cursor: `agent --list-models`.                                                                    | `claude-sonnet-5`                                                                                |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it                                      | `medium`                                                                                         |
| `agent_loop_max_attempts`    | Max Agent→Verify retry cycles before finalize records failure.                                                    | `3`                                                                                              |
| `agent_checker_instructions` | Checker APPROVE/REJECT rubric. Local/same-package structural edits only; no architecture/GoF/cross-package diffs. | Inline in caller workflow                                                                        |
| `agent_checker_max_turns`    | Max checker agent turns per verification.                                                                         | `100`                                                                                            |
| `agent_checker_model`        | Checker model ID. Cursor: `agent --list-models`.                                                                  | `claude-opus-5`                                                                                  |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it                                    | `medium`                                                                                         |
| `agent_edit_allowlist`       | Comma-separated globs the maker may modify. Tight dogfood scope.                                                  | `.apm/packages/**,scripts/**`                                                                    |
| `detect_branch_match`        | Comma-separated integration branch patterns to watch.                                                             | `main`                                                                                           |
| `state_branch`               | Branch for `.loop/*` persistence, and state migration (it no longer doubles as a watch fallback).                 | `main`                                                                                           |
| `budget_max_runs_per_day`    | Daily run cap keyed by `loop_name`.                                                                               | `1`                                                                                              |
| `budget_max_tokens_per_day`  | Daily aggregated token cap across loops.                                                                          | `1000000`                                                                                        |
| `detect_script`              | Domain detect script path.                                                                                        | `.agents/skills/refactor/scripts/detect_refactor.sh`                                             |
| `agent_engine`               | AI engine (`claude`, `copilot`, `codex`, `cursor`).                                                               | `claude`                                                                                         |
| `delivery`                   | Platform delivery after APPROVE (`pr_create` for dogfood).                                                        | `pr_create`                                                                                      |
| `agent_checker_path_pattern` | Extended regex to infer file paths from checker text.                                                             | See caller workflow                                                                              |
| `level`                      | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR.                                                            | `L2`                                                                                             |
| `loop_name`                  | Loop identifier; state file `.loop/state-refactor.json`.                                                          | `refactor`                                                                                       |
| `detect_max_targets`         | Max targets (watch branches) per cron tick; all hints of a target are surveyed in one run.                        | `1`                                                                                              |
| `agent_edit_target`          | Agent artifact type at L2/L3.                                                                                     | `fix`                                                                                            |
| `agent_report_check`         | Deterministic check of the maker report before the checker (`paths`: `### Changes` lists repository paths).       | `paths`                                                                                          |
| `agent_unchanged_verdict`    | `APPROVE` or `REJECT` when maker produces no file diff.                                                           | `REJECT`                                                                                         |
| `pr_body`                    | Optional static prefix (dogfood: `""`).                                                                           | `""`                                                                                             |
| `pr_title`                   | PR title when `delivery` is `pr_create`.                                                                          | `chore(refactor): structural improvement (loop-refactor)`                                        |
| `agent_maker_instructions`   | Domain instructions: invoke `refactor` survey-then-apply-all path; stack validation via A'.                       | Inline in caller workflow                                                                        |
| `detect_pr_enabled`          | Enumerate open PR heads. Refactor loop uses integration branches only.                                            | `false`                                                                                          |
| `agent_maker_skill_name`     | Skill package to invoke.                                                                                          | `refactor`                                                                                       |
| `agent_tool_allowlist`       | Tool permission rules for the maker                                                                               | `git remote get-url`, `validate.sh` of github-actions, go, markdown, and shell-script validation |

### Domain detect environment (`detect_env_json`)

| JSON key / env var              | Description                                                 | Dogfood value                 |
| ------------------------------- | ----------------------------------------------------------- | ----------------------------- |
| `REFACTOR_DUP_MIN_LINES`        | Minimum consecutive non-empty lines for `duplication_block` | `8`                           |
| `REFACTOR_OVERSIZED_FILE_LINES` | File line count threshold for `oversized_unit` (size only)  | `400`                         |
| `REFACTOR_SCAN_GLOBS`           | Comma-separated globs for scan roots                        | `.apm/packages/**,scripts/**` |

The prompt key `agent_edit_allowed` is not a caller input: the platform derives it from `level` (`true` at L2 and L3).

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_refactor.sh` with `targets["integration:<branch>"].last_sha`.

Detect script outputs **facts** (not semantic repair decisions):

| Field          | Role                                                        |
| -------------- | ----------------------------------------------------------- |
| `hints[]`      | Mechanical H1 hints (`duplication_block`, `oversized_unit`) |
| `hint.kind`    | Closed set only                                             |
| `hint.path`    | Primary file path for the hint                              |
| `hint.detail`  | Locator (line range, duplicate peer path, line count)       |
| `commit_range` | Passed through prompt context when scope is `range`         |
| `skip`         | `true` when no hints after allowlist filter                 |

**Skill** (`refactor`) maps **every** `hints[]` entry to survey rows; at L2/L3 applies all candidates marked apply in one run.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `delivery` = `pr_create`

### Stable filters (detect only)

- Circuit breaker on `targets[key].consecutive_failures`
- Budget (platform)
- Prune generated trees, `docs/report/**`, `node_modules/**`, secrets paths

No infra/env classification — not applicable.

### State fields (per target key)

| Field                  | Role                                                                |
| ---------------------- | ------------------------------------------------------------------- |
| `last_sha`             | Scan cursor; advances when fix PR merges (`on-loop-state-promote`)  |
| `pending`              | Written at finalize on `pr_create`; promoted to `last_sha` on merge |
| `outcome`              | `pr_created`, `rejected`, `unchanged`, …                            |
| `consecutive_failures` | Circuit breaker                                                     |

## Execute

- Worktree from `target.from` on integration branch
- Checker diff baseline: `to.branch`
- `verifier_context`: detect hint summary (kind, path, detail)
- **Intent:** always `structural` — O2 cap; no architecture Phase A/B
- Survey all hints; apply every apply candidate; follow `refactor` skill contract via caller `agent_maker_instructions` (A')

## Finalize

PR body is composed by `loop-finalize` from agent `## Overview` / `## Summary` (skill-owned) plus mechanical sections. Dogfood sets `pr_body: ""`. See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

Always `delivery: pr_create` to `to.branch` at L2.

No `finalize_script`.

**Merge-gated cursor:** Same platform rule as all L2 `pr_create` loops — `pending` at finalize, `last_sha` on fix PR merge via `on-loop-state-promote.yaml`.

## State delivery

See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) for platform rules.

**Target (dogfood):** merge-gated `pending` + `on-loop-state-promote` — same as docs-updater.

Persistence: `state-refactor.json` on `state_branch` via [finalize inside ci-loop-agent](../loop-caller-workflows-design.md#finalize-inside-ci-loop-agent).

### Retry limits and circuit breaker

| Value                     | Rule                                                                                                                                                                                                                                       |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `agent_loop_max_attempts` | Agent→Verify cycles inside one run (`3`); the last verdict decides the run outcome                                                                                                                                                         |
| `consecutive_failures`    | `loop-finalize` adds 1 on `rejected`, keeps it on `error`, and sets it to `0` on any other outcome; `on-loop-state-promote` sets it to `0` on merge and leaves it on close                                                                 |
| Circuit breaker           | `loop-detect` skips the target with `skip_reason` `circuit_breaker` when `consecutive_failures` is 3 or more                                                                                                                               |
| Cooldown                  | On a finalize state write, an `integration:*` key whose `outcome` is `rejected` or `pr_closed` and whose `last_run` is older than 30 days gets `consecutive_failures` `0`; no state write happens while the breaker blocks the only target |
| Pending PR                | `loop-detect` skips the target with `skip_reason` `pending_pr` while `pending.pr` is open (or its state cannot be read); a closed or merged `pending.pr` is treated as stale                                                               |
| Concurrency               | Workflow group `loop-state-main` (`cancel-in-progress: false`, `queue: max`), shared with the other scheduled loops and `on-loop-state-promote`                                                                                            |

### Cross-Loop Note

`refactor` is orthogonal to `ci-sweeper` and `tech-debt`. It does not consume tech-debt reports. If CI fails during a refactor PR, `ci-sweeper` owns repair.

## Implementation Checklist

Shared platform: [Multi-Branch — Shared platform checklist](../multi-branch-loops-design.md#shared-platform-checklist-all-loops).

### Loop-specific

- [x] `refactor/scripts/detect_refactor.sh` (H1 facts output)
- [x] `on-loop-refactor.yaml` dogfood caller via `ci-loop-caller`
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.hints` branch)
- [x] `refactor` skill + references
- [x] Bats suite for detect script (TEST-00)

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Refactor skill & loop design](../../../superpowers/specs/2026-07-21-refactor-skill-and-loop-design.md)
- [Specification](../../../reference/specification.md)
