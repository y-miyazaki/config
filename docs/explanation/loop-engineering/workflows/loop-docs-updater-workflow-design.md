# Docs Updater Workflow Design

Workflow and domain design for the docs-updater loop (`on-loop-docs-updater.yaml`).

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-docs-updater.yaml` · skill `docs-updater` · `docs-updater/scripts/detect_changes.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Detect documentation drift from code changes on integration branches and open fix PRs after the docs-updater skill runs.

### docs-updater dual paths

| Path               | Trigger                     | Input                                                                    |
| ------------------ | --------------------------- | ------------------------------------------------------------------------ |
| Interactive / hook | Pre-commit, user-invoked    | `scripts/detect_changes.sh` JSON (mechanical facts)                      |
| Loop               | `on-loop-docs-updater.yaml` | Same detect script facts in prompt; skill builds `findings[]` in Execute |

Both paths share `docs-updater/scripts/detect_changes.sh` for mechanical facts only. The **entry skill** (Execute) builds semantic `findings[]` — detect and the caller do not emit semantic classifications.

### Detect scope axis (normative)

Normative cross-skill definition: [Detect scope axis and interactive discovery](../../../superpowers/specs/2026-08-10-detect-scope-axis-and-interactive-discovery-design.md).

| Path                  | `--scope`             | Notes                                                                                       |
| --------------------- | --------------------- | ------------------------------------------------------------------------------------------- |
| Loop (state cursor)   | `range --since <sha>` | Unchanged — detect limits to `<since>..HEAD` changes                                        |
| git hook / pre-commit | `staged`              | Index diff only; untracked files are not visible until added                                |
| Interactive free-form | `all`                 | **Breaking (2026-08-10):** full candidate-doc enumeration — not `git diff HEAD` + untracked |

Loop callers must not rely on `--scope all` for worktree sync; use `staged` (hook) or `range` (automation).

#### Detect → findings pipeline (loop domain)

1. **Detect script** emits mechanical facts: `changed_files`, `deleted_files`, `renamed_files`, `affected_docs`, `commit_range`, `skip`.
2. **Execute agent** (docs-updater on the automation path) maps facts into `findings[]` with `file`, `reason`, and `source_commit`, then classifies and patches per skill checklists.
3. Field semantics and `## Constraints` edit gate: [common-loop-triage-format.md](../common-loop-triage-format.md) and skill `references/category-input-schema.md` / `category-automation-envelope.md` (automation path only).

### Modes

| Mode           | Default | Behavior                                       |
| -------------- | ------- | ---------------------------------------------- |
| `integration`  | on      | Detect on watch branch → fix PR to same branch |
| `pull_request` | off     | not supported for this loop                    |

## Use cases

| Use case                                      | Trigger                                                                                                                                             | Outcome                                                                                                                                                                                          | Transition |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| Fix documentation drift after code changes    | Weekly `schedule` (Monday 09:00 UTC) or `workflow_dispatch`; the range after `last_sha` has a non-Markdown change, or a Markdown deletion or rename | Semantic review of git-diff facts (`changed_files`, `affected_docs`, …), then a fix of high-priority stale references or missing doc content in one L2 review PR to the watch integration branch | S0 -> S1   |
| Coordinate with peer loops on the same branch | Several loops target the same integration branch                                                                                                    | The run waits in the queue ([workflow concurrency](../multi-branch-loops-design.md#cross-loop-coordination-workflow-concurrency))                                                                | -          |

## Out of scope

- PR head healing (`detect_pr_enabled` default off)
- Creating documentation from scratch; non-documentation file edits
- Loop state and detect script management

## State model

The loop uses the shared states `S0`–`S5` from [Loop Workflow Design Template](loop-workflow-design-template.md#scheduled-loop-states) for its one target key, `integration:main` in `.loop/state-docs-updater.json` on `state_branch`. It adds no loop-specific rows. The values that hold each state in this loop:

| State | Values in this loop                                                                                                                                                                                    |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| S0    | Detect returns `skip: false`: `affected_docs` is not empty for the range after `last_sha`                                                                                                              |
| S1    | The fix PR carries `loop-automation`; `pending` holds `{ sha, pr, … }`; run-log `pr_created`                                                                                                           |
| S2    | `on-loop-state-promote` sets `last_sha` to `pending.sha`, removes `pending`, and sets `outcome` `pr_merged` and `consecutive_failures` `0`                                                             |
| S3    | `on-loop-state-promote` removes `pending` and sets `outcome` `pr_closed`; `last_sha` does not change and `consecutive_failures` rises by 1 (a close counts as a failure), so the next tick is S0 again |
| S4    | The PR stays open; every tick records run-log `skipped` with `skip_reason` `pending_pr`                                                                                                                |
| S5    | `consecutive_failures` is 3 or more and `last_run` is under 30 days old; each tick within 30 days of `last_run` records run-log `skipped` with `skip_reason` `circuit_breaker`                         |

A run that opens no PR (checker `REJECT`, no diff, agent error) leaves the target in S0. Only `rejected` raises `consecutive_failures`; the third one moves the target to S5. Retry limits and resets are in [State delivery](#state-delivery).

## User actions

Each row is one action a person can take on the loop's output, the loop response, and what the person sees next. The Transition column references [State model](#state-model).

| User action                                                                             | Loop response                                                                                                                                                                                                                                                                                                        | Values changed                                                                                                                                                                | Result and next action                                                                                                             | Transition     |
| --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| Merge the docs PR                                                                       | `on-loop-state-promote` (`pull_request_target` `closed`, job gated on `loop-automation`) promotes the pending state                                                                                                                                                                                                  | `last_sha` = `pending.sha`; `pending` removed; `outcome` `pr_merged`; `consecutive_failures` `0`; `open_rejections` `[]`                                                      | The docs fix lands. The next Monday tick scans the range after the new `last_sha`                                                  | S1 -> S2 -> S0 |
| Close the docs PR without merging                                                       | `on-loop-state-promote` clears the pending state                                                                                                                                                                                                                                                                     | `pending` removed; `outcome` `pr_closed`; `last_sha` and `consecutive_failures` unchanged                                                                                     | The next tick detects the same range and opens a new docs PR (see [Unhandled cases](#unhandled-cases))                             | S1 -> S3 -> S0 |
| Delete the loop branch of an open docs PR                                               | GitHub closes the PR, and `on-loop-state-promote` clears the pending state                                                                                                                                                                                                                                           | As for closing the PR                                                                                                                                                         | As for closing the PR                                                                                                              | S1 -> S3 -> S0 |
| Leave the docs PR open                                                                  | Each tick runs detect, which finds the open `pending.pr` and skips; `record-skip` appends the run log                                                                                                                                                                                                                | Run-log `skipped`, `skip_reason` `pending_pr`                                                                                                                                 | No new PR opens until the PR is merged or closed                                                                                   | S1 -> S4       |
| Push commits to the docs PR branch                                                      | Nothing runs                                                                                                                                                                                                                                                                                                         | Branch and PR head only; `pending.sha` keeps the detect SHA                                                                                                                   | Merging promotes `pending.sha`, so the person's commits land with the PR                                                           | -              |
| Push to `main` while a run is queued or running                                         | The run keeps the detect SHA; finalize opens the PR from the agent branch based on that SHA                                                                                                                                                                                                                          | None beyond the run's own values                                                                                                                                              | When the push edits the same docs, GitHub shows a conflict on the PR; resolve it on the PR branch                                  | -              |
| Comment on, review, or resolve a thread on the docs PR                                  | Nothing runs in this loop. A `@loop` mention follows the intake of [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md)                                                                                                                                                                             | None in this loop                                                                                                                                                             | Edit the PR by hand, or close it                                                                                                   | -              |
| Remove `loop-automation` from the docs PR                                               | Nothing runs now. When the PR later closes, the `on-loop-state-promote` job `if` refuses it                                                                                                                                                                                                                          | Label only; `pending` stays and `last_sha` does not advance                                                                                                                   | Detect treats a closed or merged `pending.pr` as stale and scans the old range again (see [Unhandled cases](#unhandled-cases))     | -              |
| Start `workflow_dispatch` (no inputs)                                                   | Same as a scheduled tick; it waits in the concurrency group `loop-state-main`                                                                                                                                                                                                                                        | As for a tick: a new PR and `pending`, or run-log `skipped` (`no_changes`, `pending_pr`, `circuit_breaker`, `budget`); only runs that start the agent count toward the budget | Read the run log when no PR opens                                                                                                  | S0 -> S1       |
| Re-run a failed run from the Actions page                                               | Detect runs again against the current `main` and the current state                                                                                                                                                                                                                                                   | As for a new tick                                                                                                                                                             | As for `workflow_dispatch`                                                                                                         | -              |
| Reset the circuit breaker by a PR to `main` that edits `.loop/state-docs-updater.json`  | Nothing runs on merge; the next tick reads the new state                                                                                                                                                                                                                                                             | `consecutive_failures` set to `0` (or the target key removed); `last_sha` kept or moved by hand                                                                               | The next tick detects again. Fix the cause of the rejections first                                                                 | S5 -> S0       |
| Change `.loop/loop-budget.json` or the caller inputs by PR after a failure              | Nothing runs on merge. The next tick uses the new values                                                                                                                                                                                                                                                             | `.loop/loop-budget.json` caps (they override caller `budget_*`); caller inputs                                                                                                | Start `workflow_dispatch` to apply them now                                                                                        | -              |
| Do nothing (only Markdown edits, no deletion or rename)                                 | Each tick runs detect, which returns `skip: true`                                                                                                                                                                                                                                                                    | Run-log `skipped`, `skip_reason` `no_changes`                                                                                                                                 | -                                                                                                                                  | -              |
| Commits and PRs that the loop or other loops create (state, run log, the docs PR merge) | No event starts the workflow (only `schedule` and `workflow_dispatch`). Detect drops paths under `.loop/` (dot directories other than `.apm` and `.github`), so state and run-log commits never make the range relevant. The loop's own `mkdocs.yml` edit is a non-Markdown change, so detect does not skip after it | None                                                                                                                                                                          | After a merged `mkdocs.yml` edit, the next tick runs the agent even when no code changed (see [Unhandled cases](#unhandled-cases)) | -              |

Not applicable: 3, 5 — the loop uses no mention token and reads or writes no Issue.

## Unhandled cases

| Case                                                                                                                                            | Why nothing follows                                                                                                                                                                                                                                                                                                                                                     | Disposition |
| ----------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| The range holds only non-Markdown changes that need no doc update (for example `scripts/**`, `.github/**`, or the loop's own `mkdocs.yml` edit) | Detect counts any non-Markdown file outside an excluded dot directory as a relevant change and then lists every doc that matches the globs, so most weekly ranges run the agent. A run with nothing to fix is `REJECT` (no diff) and counts toward the breaker. The dogfood state has been at `consecutive_failures` 3 since 2026-10-19 with `No file changes produced` | Follow-up   |
| A person closes the docs PR to decline it                                                                                                       | `last_sha` stays, so the next tick detects the same range and opens a docs PR again. `on-loop-state-promote` raises `consecutive_failures` by 1 on close, so the PR comes back each week until three closes open the circuit breaker (it then stops for 30 days). To decline it for good, edit `last_sha` by hand                                                       | Limitation  |
| The circuit breaker stops the loop                                                                                                              | Recovers on its own: once `last_run` is older than 30 days, detect lets one run through (`admission_circuit_breaker_open` in `admission.sh`); a `rejected` result reopens the breaker for another 30 days, any other result closes it. No notification: the trip shows only as run-log `skipped` (`circuit_breaker`)                                                    | Limitation  |
| A person removes `loop-automation` from the docs PR                                                                                             | `on-loop-state-promote` skips the PR, so it does not promote `pending`. Detect treats a MERGED `pending.pr` as promoted for the run (`last_sha` becomes `pending.sha`, in memory only), so the merged range is not scanned again. A PR closed without merge leaves `pending` stale and the range is scanned again                                                       | Limitation  |
| A person pushes to `main` during a run and edits the same docs                                                                                  | The PR shows a conflict that the person resolves; the loop does not rebase                                                                                                                                                                                                                                                                                              | Accepted    |
| A person comments on or reviews the docs PR                                                                                                     | The loop reads no PR comments; the person edits the PR or closes it                                                                                                                                                                                                                                                                                                     | Accepted    |

## Failure and recovery

| Failure kind                                 | How it is recorded                                                                                                                           | Who acts   | What they do                                                                              | How the loop resumes                                                                                            |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Detect script fails                          | The `detect` job fails; no state write and no run-log row                                                                                    | Maintainer | Fix the script or the environment                                                         | The next tick retries from the same `last_sha`                                                                  |
| Checker `REJECT`, or the maker makes no diff | Run-log `rejected`; state `outcome` `rejected`, `last_reject_reason`, `consecutive_failures` + 1; `last_sha` unchanged; agent branch deleted | Maintainer | Read the reason; adjust `agent_maker_instructions` or `agent_checker_instructions` by PR  | The next tick retries the same range; the third `rejected` in a row moves to S5                                 |
| Agent or push error                          | Run-log `error`; `consecutive_failures` unchanged                                                                                            | Maintainer | Fix the cause                                                                             | The next tick or `workflow_dispatch` retries                                                                    |
| Circuit breaker open                         | Run-log `skipped`, `skip_reason` `circuit_breaker` on every tick until 30 days after `last_run`                                              | Maintainer | Fix the cause, then reset `consecutive_failures` in `.loop/state-docs-updater.json` by PR | The next tick after the merge (S5 -> S0)                                                                        |
| Daily budget used up                         | Run-log `skipped`, `skip_reason` `budget`                                                                                                    | Maintainer | Wait, or raise the cap in `.loop/loop-budget.json` by PR                                  | The next tick or `workflow_dispatch`                                                                            |
| State promote fails after a merge            | The `on-loop-state-promote` run fails; `pending` stays with a merged `pending.pr`                                                            | Maintainer | Re-run the failed `on-loop-state-promote` run                                             | Detect treats the stale `pending` as not blocking, but scans from the old `last_sha` until the promote succeeds |

## Caller inputs

Keys are passed in `on-loop-docs-updater.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_checker_instructions`, `agent_maker_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

Schedule: **`0 9 * * 1`** (Monday 09:00 UTC, weekly), plus `workflow_dispatch` with no inputs.

| Input / JSON key             | Description                                                                                                                                                                                                               | Dogfood value                                                             |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `agent_maker_max_turns`      | Max maker agent turns per loop attempt (one Agent→Verify cycle).                                                                                                                                                          | `100`                                                                     |
| `agent_maker_model`          | Maker model ID. Cursor: `agent --list-models`.                                                                                                                                                                            | `claude-sonnet-5`                                                         |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                              | `medium`                                                                  |
| `agent_loop_max_attempts`    | Max Agent→Verify retry cycles before finalize records failure.                                                                                                                                                            | `3`                                                                       |
| `agent_checker_instructions` | Checker APPROVE/REJECT rubric. Doc-only edits; factual consistency; no sensitive data.                                                                                                                                    | Inline in caller workflow                                                 |
| `agent_checker_max_turns`    | Max checker agent turns per verification.                                                                                                                                                                                 | `100`                                                                     |
| `agent_checker_model`        | Checker model ID. Cursor: `agent --list-models`.                                                                                                                                                                          | `claude-opus-5`                                                           |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                            | `medium`                                                                  |
| `agent_edit_allowlist`       | Comma-separated globs the maker may modify. Must align with docs-updater scope.                                                                                                                                           | `docs/**/*.md,README.md,mkdocs.yml`                                       |
| `detect_branch_match`        | Comma-separated integration branch patterns to watch for doc drift.                                                                                                                                                       | `main`                                                                    |
| `state_branch`               | Branch for `.loop/*` persistence, and state migration (it no longer doubles as a watch fallback).                                                                                                                         | `main`                                                                    |
| `budget_max_runs_per_day`    | Daily run cap keyed by `loop_name`. Caller input; `.loop/loop-budget.json` overrides when present.                                                                                                                        | `1`                                                                       |
| `budget_max_tokens_per_day`  | Daily aggregated token cap across loops.                                                                                                                                                                                  | `1000000`                                                                 |
| `detect_script`              | Domain detect script path (shared with docs-updater hook path).                                                                                                                                                           | `.agents/skills/docs-updater/scripts/detect_changes.sh`                   |
| `agent_engine`               | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                                                                                     | `claude`                                                                  |
| `delivery`                   | Platform delivery after APPROVE (`pr_create` for dogfood).                                                                                                                                                                | `pr_create`                                                               |
| `agent_checker_path_pattern` | Extended regex to infer file paths from checker text.                                                                                                                                                                     | See caller workflow                                                       |
| `level`                      | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR.                                                                                                                                                                    | `L2`                                                                      |
| `loop_name`                  | Loop identifier; state file `.loop/state-docs-updater.json`.                                                                                                                                                              | `docs-updater`                                                            |
| `detect_max_targets`         | Max targets per cron tick after priority filters.                                                                                                                                                                         | `3`                                                                       |
| `agent_edit_target`          | Agent artifact type at L2/L3.                                                                                                                                                                                             | `fix`                                                                     |
| `agent_report_check`         | Deterministic check of the maker report before the checker (`paths`: `### Changes` lists repository paths).                                                                                                               | `paths`                                                                   |
| `agent_unchanged_verdict`    | `APPROVE` or `REJECT` when maker produces no file diff.                                                                                                                                                                   | `REJECT`                                                                  |
| `pr_body`                    | Optional static prefix (dogfood: `""`). `loop-finalize` composes agent Overview/Summary + mechanical sections. See [Loop PR Body Readable Design](../../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md). | `""`                                                                      |
| `pr_title`                   | PR title when `delivery` is `pr_create`.                                                                                                                                                                                  | `chore(docs-updater): automated documentation update (loop-docs-updater)` |
| `agent_maker_instructions`   | Domain instructions: run docs-updater automation path; address documented findings.                                                                                                                                       | Inline in caller workflow                                                 |
| `detect_pr_enabled`          | Enumerate open PR heads. docs-updater uses integration branches only.                                                                                                                                                     | `false`                                                                   |
| `agent_maker_skill_name`     | Skill package to invoke.                                                                                                                                                                                                  | `docs-updater`                                                            |
| `agent_tool_allowlist`       | Tool permission rules for the maker                                                                                                                                                                                       | `git remote get-url`                                                      |

### Domain detect environment (`detect_env_json`)

| JSON key                   | Description                                          | Dogfood value            |
| -------------------------- | ---------------------------------------------------- | ------------------------ |
| `DOCS_UPDATER_DOC_GLOBS`   | Comma-separated doc file globs for git-diff analysis | `docs/**/*.md,README.md` |
| `DOCS_UPDATER_EXTRA_FILES` | Additional non-glob paths                            | `mkdocs.yml`             |

When `DOCS_UPDATER_DOC_GLOBS` is unset, detect falls back to a repository-wide `*.md` find with standard `repo_paths` pruning (excludes `.agents/`, generated trees, etc.). Production callers should set globs explicitly; the fallback is mainly for local runs and tests.

#### Hook / manual (appendix)

Not a loop caller; configure via environment when invoking `detect_changes.sh` outside defaults.

| Env var                    | Description                 | Default      |
| -------------------------- | --------------------------- | ------------ |
| `DOCS_UPDATER_DOCS_ROOT`   | Documentation tree root     | `docs`       |
| `DOCS_UPDATER_SITE_CONFIG` | Site navigation config path | `mkdocs.yml` |

The prompt key `agent_edit_allowed` is not a caller input: the platform derives it from `level` (`true` at L2 and L3).

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_changes.sh` with `targets["integration:<branch>"].last_sha`.

Detect script outputs **facts** (not semantic findings):

| Field                                             | Role                                 |
| ------------------------------------------------- | ------------------------------------ |
| `changed_files`, `deleted_files`, `renamed_files` | Git diff summary                     |
| `affected_docs`                                   | Candidate doc paths for agent review |
| `commit_range`                                    | Passed through prompt context        |
| `skip`                                            | `true` when `affected_docs` is empty |

`affected_docs` is empty only when the range has no non-Markdown change and no Markdown deletion or rename. Paths under dot directories other than `.apm` and `.github` (for example `.loop/` state and run-log commits) are dropped first. Any remaining such change, for example under `scripts/**` or `.github/**`, lists every doc that matches `DOCS_UPDATER_DOC_GLOBS` plus `DOCS_UPDATER_EXTRA_FILES`.

**Skill** (`docs-updater` automation path) builds `findings[]` with semantic `reason` from these facts.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `delivery` = `pr_create`

**Do not** use ci-sweeper workflow-run / `gh run list` detect.

### Stable filters (detect only)

- Circuit breaker on `targets[key].consecutive_failures`
- Budget (platform)

No infra/env classification — not applicable.

### State fields (per target key)

| Field                  | Role                                                                |
| ---------------------- | ------------------------------------------------------------------- |
| `last_sha`             | Scan cursor; advances when fix PR merges (`on-loop-state-promote`)  |
| `pending`              | Written at finalize on `pr_create`; promoted to `last_sha` on merge |
| `outcome`              | `pr_created`, `rejected`, `unchanged`, …                            |
| `consecutive_failures` | Circuit breaker                                                     |

No `workflow_run_id` / ci ledger.

## Execute

- Worktree from `target.from` on integration branch
- Checker diff baseline: `to.branch`
- `verifier_context`: detect fact summary (changed files, affected docs). Platform always wires; may be brief

## Finalize

PR body is composed by `loop-finalize` from agent `## Overview` / `## Summary` (skill-owned) plus mechanical sections. Dogfood sets `pr_body: ""`. See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

Always `delivery: pr_create` to `to.branch` at L2. Other deliveries (`pr_push`) are not used by this loop.

No `finalize_script`.

**Merge-gated cursor:** Same platform rule as all L2 `pr_create` loops — `pending` at finalize, `last_sha` on fix PR merge via `on-loop-state-promote.yaml`. See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy).

## State delivery

See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) for platform rules.

**Target (dogfood):** merge-gated `pending` + `on-loop-state-promote` — same as changelog.

Persistence: `state-docs-updater.json` on `state_branch` via [finalize inside ci-loop-agent](../loop-caller-workflows-design.md#finalize-inside-ci-loop-agent).

### Retry limits and circuit breaker

| Value                     | Rule                                                                                                                                                                                                                                       |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `agent_loop_max_attempts` | Agent→Verify cycles inside one run (`3`); the last verdict decides the run outcome                                                                                                                                                         |
| `consecutive_failures`    | `loop-finalize` adds 1 on `rejected`, keeps it on `error`, and sets it to `0` on any other outcome; `on-loop-state-promote` sets it to `0` on merge and leaves it on close                                                                 |
| Circuit breaker           | `loop-detect` skips the target with `skip_reason` `circuit_breaker` when `consecutive_failures` is 3 or more and `last_run` is less than 30 days old                                                                                       |
| Cooldown                  | On a finalize state write, an `integration:*` key whose `outcome` is `rejected` or `pr_closed` and whose `last_run` is older than 30 days gets `consecutive_failures` `0`; no state write happens while the breaker blocks the only target |
| Pending PR                | `loop-detect` skips the target with `skip_reason` `pending_pr` while `pending.pr` is open (or its state cannot be read); a closed or merged `pending.pr` is treated as stale                                                               |
| Concurrency               | Workflow group `loop-state-main` (`cancel-in-progress: false`, `queue: max`), shared with the other scheduled loops and `on-loop-state-promote`                                                                                            |

### Cross-Loop Note

If `ci-sweeper` and docs-updater both target `integration:main`, [workflow concurrency](../multi-branch-loops-design.md#cross-loop-coordination-workflow-concurrency) and separate concurrency groups apply. CI failure on `main` is ci-sweeper priority; doc-only drift is docs-updater.

## Implementation Checklist

Shared platform: [Multi-Branch — Shared platform checklist](../multi-branch-loops-design.md#shared-platform-checklist-all-loops).

### Loop-specific

- [x] `docs-updater/scripts/detect_changes.sh` (facts output)
- [x] `on-loop-docs-updater.yaml` dogfood caller via `ci-loop-caller`
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.affected_docs` branch)
- [x] `docs-updater` skill automation path + references
- [x] Bats suite for detect script (TEST-00)

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
