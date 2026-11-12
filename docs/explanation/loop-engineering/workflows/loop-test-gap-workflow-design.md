# Test Gap Workflow Design

Workflow and domain design for the `test-gap` loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-test-gap.yaml` · skill `test-gap` · `test-gap/scripts/detect_test_gap.sh` · `test-gap/scripts/update_test_gap_ledger.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Decisions, rejected alternatives, and open questions: [Loop `test-gap` 設計: テスト不足を埋める改善ループ](../../../superpowers/specs/2026-10-11-loop-test-gap-design.md) (written in Japanese).

## Purpose

Select one under-tested target, add tests for it within the allowlist, and open an L2 merge-gated PR. Missing tests do not fail CI, so no other loop detects them. The agent explores and selects the target; the detect script reports facts only.

Behaviors to know:

- Detect never skips (`skip` is always `false`), so every tick that passes the pending PR, circuit breaker, and budget gates reaches the maker. A tick that finds nothing to test ends `rejected` and counts toward the circuit breaker.
- The ledger, not the state file, keeps a target from being selected again: a test path stays excluded for 30 days after a run that records it, whatever happens to the PR.

### Modes

| Mode           | Default | Behavior                                                 |
| -------------- | ------- | -------------------------------------------------------- |
| `integration`  | on      | Detect on watch branch → test PR to same branch          |
| `pull_request` | off     | Not supported for this loop (`detect_pr_enabled: false`) |

### Observation trigger

`test-gap` has no failure sensor. Its trigger is state-based: schedule, targets absent from the [ledger](#ledger), and git churn. See [Selection Criteria](../loop-engineering-design.md#selection-criteria) item 5.

## Use cases

| Use case             | Trigger                                                                                                                                                                                                                                                           | Outcome                                                             | Transition |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ---------- |
| Weekly test addition | Weekly scheduled run on `main` (Monday 10:00 UTC)                                                                                                                                                                                                                 | Tests for exactly one target (`detect_max_targets: 1`) in one L2 PR | S0 -> S1   |
| Manual run           | `workflow_dispatch`                                                                                                                                                                                                                                               | As for the weekly run                                               | S0 -> S1   |
| Phase 1 scope        | Phase 1 scope for this repository: shell scripts with paired Bats suites under `test/bats/`. The skill itself has no language adapters and discovers the stack from the repository, but the caller instructions and the Checker rubric restrict this loop to Bats | Only `.bats` files and Bats support files under `test/bats/` change | S0 -> S1   |

## Out of scope

- Running the tests inside the loop job (see [Verification and CI failure handling](#verification-and-ci-failure-handling))
- Editing or deleting existing tests, or editing production code (a suspected production bug goes under `### Deferred` in the PR body)
- GitHub Issue creation
- L1 log-only observation phase (**L2 from start**)
- Mutation testing and coverage-threshold enforcement
- Go tests: Go needs a CI caller that runs Go tests first; this repository has none, so Go is not enabled (`agent_checker_path_pattern` excludes `go`)

## State model

The loop uses the shared states `S0`–`S5` from [Loop Workflow Design Template](loop-workflow-design-template.md#scheduled-loop-states) for its one target key, `integration:main` in `.loop/state-test-gap.json` on `state_branch`. No loop-specific row is needed; the [ledger](#ledger) adds per-path exclusion inside S0.

The values that hold each state in this loop:

| State | Values in this loop                                                                                                                                                            |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| S0    | No open `pending.pr`, `consecutive_failures` below 3, and budget left; detect always returns `skip: false`                                                                     |
| S1    | The test PR carries `loop-automation`; `pending` holds `{ sha, pr, … }`; run-log `pr_created`; ledger entries for the changed test paths with `outcome` `pr_created`           |
| S2    | `on-loop-state-promote` sets `last_sha` to `pending.sha`, removes `pending`, and sets `outcome` `pr_merged`, `consecutive_failures` `0`, and `open_rejections` `[]`            |
| S3    | `on-loop-state-promote` removes `pending` and sets `outcome` `pr_closed`; `last_sha` and `consecutive_failures` do not change; the ledger keeps the test paths for 30 days     |
| S4    | The PR stays open; every tick records run-log `skipped` with `skip_reason` `pending_pr`                                                                                        |
| S5    | `consecutive_failures` is 3 or more and `last_run` is under 30 days old; each tick within 30 days of `last_run` records run-log `skipped` with `skip_reason` `circuit_breaker` |

A run that opens no PR (checker `REJECT`, no diff, agent error) leaves the target in S0. Only `rejected` raises `consecutive_failures`; the third one moves the target to S5. Retry limits and resets are in [Failure handling and the circuit breaker](#failure-handling-and-the-circuit-breaker).

## User actions

Each row is one action a person can take on the loop's output, the loop response, and what the person sees next. The Transition column references [State model](#state-model).

| User action                                                                                                      | Loop response                                                                                                                            | Values changed                                                                                                                                                                   | Result and next action                                                                                                   | Transition     |
| ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | -------------- |
| Merge the test PR                                                                                                | `on-loop-state-promote` (`pull_request_target` `closed`, job gated on `loop-automation`) promotes the pending state                      | `last_sha` = `pending.sha`; `pending` removed; `outcome` `pr_merged`; `consecutive_failures` `0`; `open_rejections` `[]`                                                         | The tests land. The next tick selects another target                                                                     | S1 -> S2 -> S0 |
| Close the test PR without merging (for example after a failing CI)                                               | `on-loop-state-promote` clears the pending state                                                                                         | `pending` removed; `outcome` `pr_closed`; `last_sha` and `consecutive_failures` unchanged; ledger entries stay                                                                   | The closed target stays excluded for 30 days unless a new reason is shown. The next tick selects another target          | S1 -> S3 -> S0 |
| Delete the loop branch of an open test PR                                                                        | GitHub closes the PR, and `on-loop-state-promote` clears the pending state                                                               | As for closing the PR                                                                                                                                                            | As for closing the PR                                                                                                    | S1 -> S3 -> S0 |
| Leave the test PR open                                                                                           | Each tick finds the open `pending.pr` and skips; `record-skip` appends the run log                                                       | Run-log `skipped`, `skip_reason` `pending_pr`                                                                                                                                    | No new test PR opens until the PR is merged or closed                                                                    | S1 -> S4       |
| Push commits to the test PR branch (for example to fix a failing test)                                           | Nothing runs in this loop; CI runs on the PR                                                                                             | Branch and PR head only; `pending.sha` keeps the detect SHA                                                                                                                      | Merging promotes `pending.sha`, so the person's commits land with the PR                                                 | -              |
| Push to `main` while a run is queued or running                                                                  | The run keeps the detect SHA                                                                                                             | None beyond the run's own values                                                                                                                                                 | The next tick sees the push                                                                                              | -              |
| Comment on, review, or resolve a thread on the test PR                                                           | Nothing runs in this loop. A `@loop` mention follows the intake of [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md) | None in this loop                                                                                                                                                                | Edit the PR by hand, or close it                                                                                         | -              |
| Remove `loop-automation` from the test PR                                                                        | Nothing runs now. When the PR later closes, the `on-loop-state-promote` job `if` refuses it                                              | Label only; `pending` stays and `last_sha` does not advance                                                                                                                      | Detect treats a closed or merged `pending.pr` as stale and runs as usual; the churn range keeps the old `last_sha`       | -              |
| Start `workflow_dispatch` (no inputs)                                                                            | Same as a scheduled tick; it waits in the concurrency group `loop-state-main`                                                            | As for a tick: a new PR, `pending`, and ledger entries, or run-log `skipped` (`pending_pr`, `circuit_breaker`, `budget`); only runs that start the agent count toward the budget | The daily cap is `2`                                                                                                     | S0 -> S1       |
| Re-run a failed run from the Actions page                                                                        | Detect runs again against the current `main` and the current state                                                                       | As for a new tick                                                                                                                                                                | As for `workflow_dispatch`                                                                                               | -              |
| Reset the circuit breaker by a PR to `main` that edits `.loop/state-test-gap.json`                               | Nothing runs on merge; the next tick reads the new state                                                                                 | `consecutive_failures` set to `0` (or the target key removed)                                                                                                                    | The next tick runs the maker again. Fix the cause of the rejections first                                                | S5 -> S0       |
| Remove a path from `.loop/state-test-gap-ledger.json` by PR                                                      | Nothing runs on merge; the next detect no longer lists the path in `ledger.processed[]` and `verifier_context`                           | Ledger entry removed                                                                                                                                                             | The target can be selected again without a new reason                                                                    | -              |
| Change `detect_env_json` (churn keys only), `.loop/loop-budget.json`, or the caller inputs by PR after a failure | Nothing runs on merge. The next tick uses the new values                                                                                 | `TEST_GAP_CHURN_*`; caller inputs; a `test-gap` entry in `.loop/loop-budget.json` would override the caller `budget_*` (none exists today)                                       | Start `workflow_dispatch` to apply them now. Keep `TEST_GAP_LEDGER_FILE` and `TEST_GAP_RETENTION_DAYS` at their defaults | -              |
| Do nothing while no under-tested target is left                                                                  | Each tick reaches the maker, which writes no test, so the verdict is `REJECT`                                                            | Run-log `rejected`; `consecutive_failures` + 1                                                                                                                                   | After three such ticks the loop stops; reset the counter when new code needs tests                                       | S0 -> S5       |
| Commits and PRs that the loop or other loops create (state, ledger, run log, the test PR merge)                  | Nothing runs: the workflow has only `schedule` and `workflow_dispatch` triggers. `ci-sweeper` excludes the bot-authored test PR          | None                                                                                                                                                                             | -                                                                                                                        | -              |

Not applicable: 3, 5 — the loop uses no mention token and reads or writes no Issue (it never creates Issues).

## Unhandled cases

| Case                                                                                   | Why nothing follows                                                                                                                                                                                                                                                                                            | Disposition |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| The circuit breaker stops the loop                                                     | Recovers on its own: once `last_run` is older than 30 days, detect lets one run through (`target_circuit_breaker_open` in `guards.sh`); a `rejected` result reopens the breaker for another 30 days, any other result closes it. No notification: the trip shows only as run-log `skipped` (`circuit_breaker`) | Limitation  |
| No under-tested target is left, or every candidate is in the ledger                    | Detect never skips, so the maker runs and produces no diff; `agent_unchanged_verdict` `REJECT` turns "nothing to do" into a failure that trips the circuit breaker in three ticks                                                                                                                              | Follow-up   |
| A state push races with another writer of `main`                                       | With `finalize_commit_paths` set, `write_state.sh` does not retry a push race; it opens a state PR, which needs a manual merge when it conflicts                                                                                                                                                               | Follow-up   |
| CI fails on a test PR                                                                  | The loop does not run the tests and `ci-sweeper` does not watch bot-authored PRs; a person fixes or closes the PR (see [Verification and CI failure handling](#verification-and-ci-failure-handling))                                                                                                          | Accepted    |
| A person closes the test PR to decline it                                              | Closing does not count toward the breaker. The ledger keeps the target out for 30 days, so the next tick selects another target                                                                                                                                                                                | Accepted    |
| A person removes `loop-automation` from the test PR                                    | `on-loop-state-promote` skips the PR and `pending` stays. Detect treats a closed or merged `pending.pr` as stale, so the next tick runs; only the churn range keeps the old `last_sha`                                                                                                                         | Accepted    |
| A person sets `TEST_GAP_LEDGER_FILE` or `TEST_GAP_RETENTION_DAYS` in `detect_env_json` | `loop-finalize` passes no detect environment to `finalize_script`, so detect and finalize would use different values; nothing rejects the override                                                                                                                                                             | Limitation  |
| A person comments on or reviews the test PR                                            | The loop reads no PR comments; the person edits the PR or closes it                                                                                                                                                                                                                                            | Accepted    |

## Failure and recovery

| Failure kind                              | How it is recorded                                                                                                                                          | Who acts   | What they do                                                                             | How the loop resumes                                                           |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Detect script fails                       | The script prints `status: error` and exits 1; the `detect` job fails; no state write and no run-log row                                                    | Maintainer | Fix the script or the environment                                                        | The next tick                                                                  |
| Checker `REJECT`, or no test file written | Run-log `rejected`; state `outcome` `rejected`, `last_reject_reason`, `consecutive_failures` + 1; ledger `rejected` for changed paths; agent branch deleted | Maintainer | Read the reason; adjust `agent_maker_instructions` or `agent_checker_instructions` by PR | The next tick selects again; the third `rejected` in a row moves to S5         |
| Agent or push error                       | Run-log `error`; `consecutive_failures` unchanged; no ledger entry                                                                                          | Maintainer | Fix the cause                                                                            | The next tick or `workflow_dispatch` retries                                   |
| Ledger update problem                     | `update_test_gap_ledger.sh` exits 0 and writes a warning on stderr; the ledger is not updated                                                               | Maintainer | Read the finalize log; fix the ledger file by PR                                         | The next tick; the target may be selected again                                |
| Circuit breaker open                      | Run-log `skipped`, `skip_reason` `circuit_breaker` on every tick until 30 days after `last_run`                                                             | Maintainer | Fix the cause, then reset `consecutive_failures` in `.loop/state-test-gap.json` by PR    | The next tick after the merge (S5 -> S0)                                       |
| Daily budget used up                      | Run-log `skipped`, `skip_reason` `budget`                                                                                                                   | Maintainer | Wait, or add a `test-gap` entry to `.loop/loop-budget.json` by PR                        | The next tick or `workflow_dispatch`                                           |
| State promote fails after a merge         | The `on-loop-state-promote` run fails; `pending` stays with a merged `pending.pr`                                                                           | Maintainer | Re-run the failed `on-loop-state-promote` run                                            | Detect treats the stale `pending` as not blocking; the next tick runs as usual |

## Caller inputs

Keys are passed in `on-loop-test-gap.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_checker_instructions`, `agent_maker_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

Schedule: **`0 10 * * 1`**, `timezone: Etc/UTC` (Monday 10:00 UTC, weekly), plus `workflow_dispatch`. The caller uses the shared `loop-state-main` concurrency group with `queue: max`.

| Input / JSON key             | Description                                                                                                                                             | Dogfood value                                               |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `finalize_commit_paths`      | Extra paths `loop-finalize` commits with the state update. Carries the ledger file.                                                                     | `.loop/state-test-gap-ledger.json`                          |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it.                                                                         | `medium`                                                    |
| `agent_checker_instructions` | Checker APPROVE/REJECT rubric (static criteria only; see [Checker criteria](#checker-criteria)).                                                        | Inline in caller workflow                                   |
| `agent_checker_max_turns`    | Max checker agent turns per verification.                                                                                                               | `100`                                                       |
| `agent_checker_model`        | Checker model ID.                                                                                                                                       | `claude-opus-5`                                             |
| `agent_checker_skill_name`   | Checker skill package. Not set; the caller default applies.                                                                                             | `loop-verifier` (default)                                   |
| `agent_loop_max_attempts`    | Max Agent→Verify retry cycles before finalize records failure.                                                                                          | `3`                                                         |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it.                                                                           | `medium`                                                    |
| `agent_maker_instructions`   | Domain instructions: Phase 1 shell/Bats only, select one target, add tests, no production edits, no claim of running the tests.                         | Inline in caller workflow                                   |
| `agent_maker_max_turns`      | Max maker agent turns per loop attempt (one Agent→Verify cycle).                                                                                        | `100`                                                       |
| `agent_maker_model`          | Maker model ID.                                                                                                                                         | `claude-sonnet-5`                                           |
| `agent_maker_skill_name`     | Skill package to invoke.                                                                                                                                | `test-gap`                                                  |
| `agent_report_check`         | Deterministic check of the maker report before the checker (`paths`: `### Changes` lists repository paths).                                             | `paths`                                                     |
| `agent_tool_allowlist`       | Tool permission rules for the maker                                                                                                                     | `git remote get-url`                                        |
| `agent_edit_allowlist`       | Comma-separated globs the maker may modify. Tests only. The Checker rubric narrows this to `test/bats/**` (see [Checker criteria](#checker-criteria)).  | `test/**`                                                   |
| `detect_branch_match`        | Comma-separated integration branch patterns to watch.                                                                                                   | `main`                                                      |
| `state_branch`               | Branch for `.loop/*` persistence, and state migration (it no longer doubles as a watch fallback).                                                       | `main`                                                      |
| `budget_max_runs_per_day`    | Daily run cap keyed by `loop_name`. `.loop/loop-budget.json` has no `test-gap` entry, so the caller value applies.                                      | `2`                                                         |
| `budget_max_tokens_per_day`  | Daily aggregated token cap across loops.                                                                                                                | `1000000`                                                   |
| `delivery`                   | Platform delivery after APPROVE.                                                                                                                        | `pr_create`                                                 |
| `detect_env_json`            | JSON object of `TEST_GAP_*` env vars passed to the detect script. See [Domain detect environment](#domain-detect-environment-detect_env_json). Not set. | `{}` (default)                                              |
| `detect_script`              | Domain detect script path.                                                                                                                              | `.agents/skills/test-gap/scripts/detect_test_gap.sh`        |
| `finalize_script`            | Script `loop-finalize` runs to update the ledger.                                                                                                       | `.agents/skills/test-gap/scripts/update_test_gap_ledger.sh` |
| `agent_engine`               | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                   | `claude`                                                    |
| `environment`                | GitHub Environment for env-scoped secrets inside the reusable workflow. Leave `default` when repository secrets suffice. Not set.                       | `default` (default)                                         |
| `agent_checker_path_pattern` | Extended regex to infer file paths from checker text.                                                                                                   | `test/[^[:space:],)]+\.(bats\|sh\|json\|ya?ml)`             |
| `level`                      | Autonomy level (`L1`, `L2`, `L3`). **L2 from start**.                                                                                                   | `L2`                                                        |
| `loop_name`                  | Loop identifier; state file `.loop/state-test-gap.json`.                                                                                                | `test-gap`                                                  |
| `detect_max_targets`         | Max targets per cron tick after priority filters.                                                                                                       | `1`                                                         |
| `agent_unchanged_verdict`    | `APPROVE` or `REJECT` when the maker produces no file diff.                                                                                             | `REJECT`                                                    |
| `pr_body`                    | Optional static prefix. `loop-finalize` composes agent Overview/Summary + mechanical sections. Not set.                                                 | `""` (default)                                              |
| `detect_pr_enabled`          | Enumerate open PR heads. `test-gap` uses integration branches only. Not set.                                                                            | `false` (default)                                           |
| `pr_title`                   | PR title when `delivery` is `pr_create`.                                                                                                                | `test: add missing tests (loop-test-gap)`                   |
| `agent_edit_target`          | Agent artifact when `agent_edit_allowed` is true.                                                                                                       | `fix`                                                       |

The prompt key `agent_edit_allowed` is not a caller input: the platform derives it from `level` (`true` at L2 and L3).

No `agent_edit_denylist` is passed: the platform default (`DEFAULT_EXECUTE_DENYLIST`) applies, as in `on-loop-ci-sweeper.yaml`. Consumer repositories set `agent_edit_allowlist` to match their own test layout; the reusable workflows embed no consumer paths.

### Domain detect environment (`detect_env_json`)

Dogfood passes `{}`; the defaults below apply. `detect_env_json` reaches the **detect script only**.

| JSON key / env var        | Description                                                                                                                            | Default                            |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `TEST_GAP_CHURN_MIN`      | Minimum commit touches per path for a churn hotspot                                                                                    | `3`                                |
| `TEST_GAP_CHURN_TOP`      | Maximum churn hotspots to emit                                                                                                         | `20`                               |
| `TEST_GAP_CHURN_WINDOW`   | `git log --since` window for churn hotspots                                                                                            | `90.days`                          |
| `TEST_GAP_LEDGER_FILE`    | Ledger path, repository-relative (detect only; must stay at the default, see below)                                                    | `.loop/state-test-gap-ledger.json` |
| `TEST_GAP_RETENTION_DAYS` | Days a ledger entry stays visible (detect only; must stay at the default, see below). A non-numeric value warns and falls back to `30` | `30`                               |

**Finalize side.** `loop-finalize` passes only `EXECUTE_BRANCH`, `LOOP_NAME`, `OUTCOME`, `STATE_FILE`, `TARGET_JSON`, and `VERDICT` to `finalize_script`; `detect_env_json` does not reach it. `update_test_gap_ledger.sh` therefore always uses the defaults for the ledger file and the retention window, and `TEST_GAP_LEDGER_FILE` and `TEST_GAP_RETENTION_DAYS` overrides must not be set in `detect_env_json`: detect would then read a different file or window than finalize writes. The base branch for the diff is resolved as `TEST_GAP_BASE_BRANCH` when set, else `.to.branch` of `TARGET_JSON` (the integration branch under watch, for example `master` or `trunk`), else `main`.

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_test_gap.sh --scope range --since <last_sha>`, so the churn log covers `last_sha..HEAD` inside `TEST_GAP_CHURN_WINDOW`; `last_sha` falls back to `HEAD~10` when the state has none. Run by hand, the script defaults to `--scope all`; `--scope range --since <ref>` echoes `since` and `commit_range` and limits the churn log to that range.

The script is a thin, language-agnostic detect. It emits facts and **never decides that tests are missing**; `skip` is always `false`, so every scheduled run reaches the maker.

| Field              | Role                                                                                                                         |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `status`           | `ok`, or `error` on a fatal error (the script then exits 1 with `skip: true`)                                                |
| `scope`            | Echo of the requested scope                                                                                                  |
| `since`            | Echo of `--since`                                                                                                            |
| `commit_range`     | Commit range for `--scope range`                                                                                             |
| `skip`             | Always `false`                                                                                                               |
| `hotspots[]`       | Git churn objects `{path, kind: "churn", count, window}`                                                                     |
| `ledger`           | `{file, processed[]}`; `processed[]` holds `{path, attempts, outcome, processed_at}` for entries inside the retention window |
| `warnings[]`       | Non-blocking sensor or ledger warnings (for example a corrupt ledger file)                                                   |
| `verifier_context` | Markdown listing recently processed ledger paths for the Checker; empty string when the ledger has no recent entries         |

### Why `verifier_context` is emitted

`build_verifier_context_from_result` returns the explicit `.verifier_context` from the detect result first. Without it, a detect result that has no `failures` or `commits` yields an empty context and the Checker could not see the ledger. The explicit field is what makes Checker criterion 5 (ledger re-selection) checkable. The text ends with the rule that a target whose test path is listed must not be selected again unless a new reason is stated.

### Stable filters (platform)

- Circuit breaker on `targets[key].consecutive_failures`
- Budget (platform)
- A pending test PR blocks the next detect for the same target (`pending` block)

### State fields (per target key)

| Field                  | Role                                                                    |
| ---------------------- | ----------------------------------------------------------------------- |
| `last_sha`             | Scan cursor; advances when the test PR merges (`on-loop-state-promote`) |
| `pending`              | Written at finalize on `pr_create`; promoted to `last_sha` on merge     |
| `outcome`              | `pr_created`, `rejected`, `unchanged`, …                                |
| `consecutive_failures` | Circuit breaker                                                         |

## Execute

- Worktree from `target.from` on the integration branch
- Checker diff baseline: `to.branch`
- `verifier_context`: the ledger summary from detect (see [Why `verifier_context` is emitted](#why-verifier_context-is-emitted))

### Skill

The `test-gap` skill (`SKILL.md`) reads `hotspots[]`, `ledger`, and `warnings[]` from the detect JSON. The maker:

1. Discovers the stack and test layout from the repository
2. Selects exactly one target, skipping a target whose paired test file path appears in `ledger.processed[]` (a second new test file for the same target also counts) unless a new reason is stated in the PR body or an Open Rejections item from a previous run applies
3. Adds tests that assert observable behavior (return values, side effects, error paths)
4. Names the target, the reason, the command CI will run, and the expected result in the PR body, without claiming the tests were run

Language-specific guidance comes from the caller's `agent_maker_instructions` (Phase 1: shell scripts, the `shell-script-validation` skill, and Bats pairing), not from the skill, which keeps the skill portable. A caller may restrict the stack and the caller instructions win over the skill's stack discovery. In interactive mode there is no `Allowed paths`; the skill uses the repository's existing test directories.

### Checker criteria

The Checker cannot run tests, cannot see CI, and does not receive the Maker's report or PR body. Its prompt contains the rubric, the diff stat, `verifier_context`, and the checked-out branch. The rubric therefore contains **static criteria only**, each decidable from the diff and `verifier_context`. Inline in caller `agent_checker_instructions` (must match `on-loop-test-gap.yaml`):

- **APPROVE** when all of the following hold:
  1. Changes are limited to Bats test files and Bats support files under `test/bats/` and touch no denylist path
  2. No existing test is deleted, skipped, commented out, or loosened
  3. Each added test asserts observable behavior of the target; no test can pass regardless of the implementation
  4. The added tests correspond to a target that actually lacked tests (a missing unit or a missing paired suite)
  5. The added or changed test files do not belong to a target whose paired test path is listed in the ledger section of the verifier context, unless the diff itself shows a new reason (for example the production file changed since)
  6. Added test files contain no comment or string claiming the tests were run or passed
- **REJECT** when any of the following hold: an added test does not verify the target's behavior; a production file or denylist path is modified; an existing test is removed, skipped, or weakened; a target whose paired test path is listed in the ledger is selected again with no new reason shown by the diff; an added test file claims the tests were run or passed; any added or changed file lies outside `test/bats/**` or is not a `.bats` or Bats support file (Phase 1 is shell/Bats only); no test file was written

**Not enforced by the Checker.** PR-body honesty (no claim that the tests ran, the stated CI command and expected result, the new-reason statement for a re-selected target) is enforced by the Maker instructions and the skill's honesty rules (HON-01), and by human PR review, because the Checker does not receive the Maker's report.

**Report format check:** the caller sets `agent_report_check: paths`, so `loop-execute` machine-checks the PR body report (`### Changes` / `### Deferred`) against the branch diff before the LLM Checker runs.

**Limits:** "Breaking the implementation makes the test fail" (mutation check) and "coverage increases" cannot be confirmed by the Checker. Protection against tests that pass but verify nothing is therefore weaker than execution-based verification. CI confirms green status and human review covers depth.

### Verification and CI failure handling

The loop job installs no test runtime (the execute job sets up Node, uv, and the engine CLI), and the Checker runs before push, so no CI result exists at verification time. The loop therefore **does not validate the tests**.

- CI runs on the test PR and is the validation path
- A failing CI on a `test-gap` PR is handled by a human (fix or close). Closing the PR does not count toward the circuit breaker: `on-loop-state-promote` clears `pending` and leaves `consecutive_failures` unchanged. The ledger keeps the target out for 30 days; see [Operations and status](#operations-and-status)
- `ci-sweeper` is deliberately **not** configured to pick up these PRs: `detect_pr_bot_allowlist` in `on-loop-ci-sweeper.yaml` is unchanged. Every loop PR is authored by the same GitHub App bot, so adding that login would put all loop PRs, including `ci-sweeper` fix PRs, in scope and risks recursion
- Open question: measure the share of `test-gap` PRs whose CI fails, then decide whether to let `ci-sweeper` pick them up (a bot allowlist entry or a label filter) or to install a test runtime in the loop job. Neither is decided

Rationale and the compared options: [Loop `test-gap` 設計: テスト不足を埋める改善ループ](../../../superpowers/specs/2026-10-11-loop-test-gap-design.md).

## Finalize

Always `delivery: pr_create` to `to.branch` at L2, with the PR body composed by `loop-finalize` (see [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md)). The ledger file is committed through `finalize_commit_paths`.

**Merge-gated cursor:** same platform rule as all L2 `pr_create` loops. See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy).

## Ledger

The ledger is a separate file because `write_state.sh` only writes `targets[key]` fields (`last_sha`, `pending`, metadata) and has no slot for domain keys. It follows the same pattern as the `ci-sweeper` run ledger.

- File: `.loop/state-test-gap-ledger.json` (fixed at the default on the finalize side; see [Domain detect environment](#domain-detect-environment-detect_env_json))
- Entries are keyed by **test file path**, not by the production target. The exclusion rule therefore applies to a target whose paired test file path appears in `ledger.processed[]`; adding another new test file for that same target also counts as selecting it again
- Writer: `update_test_gap_ledger.sh`, run by `loop-finalize` as `finalize_script`; `finalize_commit_paths` commits the file with the state update
- Reader: `detect_test_gap.sh` (`ledger.processed[]` and `verifier_context`)

Shape:

```json
{
  "entries": {
    "<repo-relative test path>": {
      "attempts": 1,
      "last_loop_run_id": "<GITHUB_RUN_ID>",
      "outcome": "pr_created",
      "processed_at": "2026-10-11T10:00:00Z"
    }
  }
}
```

Behavior of `update_test_gap_ledger.sh`:

- Records the files in `git diff <base>...<EXECUTE_BRANCH>`; the maker does not have to cooperate. The base is `TEST_GAP_BASE_BRANCH`, else `TARGET_JSON` `.to.branch` (verified: `build_integration_target_json` in `loop-detect` sets `to.branch`, and `loop-finalize` reads the same field as `pr_base_branch`), else `main`
- Records only outcomes `pr_created`, `pr_pushed`, `rejected`, and `watch`. When `OUTCOME` is unset, `VERDICT` maps `APPROVE` to `pr_created` and `REJECT` to `rejected`. `unchanged`, the legacy `no-action` and `no-changes`, `error`, `escalated`, and unknown outcomes are skipped. The script reads old persisted values with its own mapping because skill scripts cannot source `lib/loop/` (the platform mapping lives in `.github/actions/lib/loop/outcome.sh`)
- Increments `attempts` for a path that is already present
- Prunes entries older than the retention window (30 days; `TEST_GAP_RETENTION_DAYS` is not passed by finalize)
- Always exits 0, so a ledger problem never blocks finalize; problems surface as warnings on stderr
- Writes through `mktemp` + `mv`

## Operations and status

**Status.** The loop has run in production. One test PR merged (`on-loop-state-promote` promoted PR #1024 on 2026-10-19), and the state commit of 2026-10-18 carried the ledger entry `test/bats/scripts/go/clean_binaries.bats` (`pr_created`). That confirms the two code-reading checks:

1. `EXECUTE_BRANCH` resolves through `git diff` when `finalize_script` runs (the ledger entry names the PR's test file)
2. `loop-finalize` includes `.loop/state-test-gap-ledger.json` from `finalize_commit_paths` in the state commit

The three runs after that (2026-10-19, 2026-10-26, 2026-11-02) ended `rejected` with no file changes, and the circuit breaker has skipped the loop since 2026-11-09.

Unverified and tracked in the spec's open questions:

3. Whether the PR is created with the GitHub App token and therefore starts CI workflows such as `on-ci-push-shell-script`
4. Whether the Checker rubric rejects meaningless tests in practice (Checker Theater, measured on real runs)

Phase 1 targets shell scripts with Bats suites only. Go support needs a CI caller that runs Go tests; this repository has none today.

### Failure handling and the circuit breaker

- A Maker that finds nothing to test produces no diff, which yields `rejected` (`agent_unchanged_verdict: REJECT`)
- Three consecutive `rejected` outcomes trip the circuit breaker. A human closing a PR does not count: `on-loop-state-promote` clears `pending` without touching `consecutive_failures`. The breaker blocks the only target key, so the whole loop stops
- To resume, reset `targets["integration:main"].consecutive_failures` (the key is `targets[<target key>]`) to `0` in `.loop/state-test-gap.json` (state file `.loop/state-<loop_name>.json`). The 30-day cooldown in `prune_targets.sh` runs only during a finalize state write, so it does not reset a breaker that blocks every run

| Value                     | Rule                                                                                                                                                                         |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `agent_loop_max_attempts` | Agent→Verify cycles inside one run (`3`); the last verdict decides the run outcome                                                                                           |
| `consecutive_failures`    | `loop-finalize` adds 1 on `rejected`, keeps it on `error`, and sets it to `0` on any other outcome; `on-loop-state-promote` sets it to `0` on merge and leaves it on close   |
| Circuit breaker           | `loop-detect` skips the target with `skip_reason` `circuit_breaker` when `consecutive_failures` is 3 or more and `last_run` is less than 30 days old                         |
| Pending PR                | `loop-detect` skips the target with `skip_reason` `pending_pr` while `pending.pr` is open (or its state cannot be read); a closed or merged `pending.pr` is treated as stale |
| Concurrency               | Workflow group `loop-state-main` (`cancel-in-progress: false`, `queue: max`), shared with the other scheduled loops and `on-loop-state-promote`                              |

## Implementation Checklist

Shared platform: [Multi-Branch — Shared platform checklist](../multi-branch-loops-design.md#shared-platform-checklist-all-loops).

### Loop-specific

- [x] `test-gap/scripts/detect_test_gap.sh` (facts output, `verifier_context`)
- [x] `test-gap/scripts/update_test_gap_ledger.sh` (`finalize_script`)
- [x] `on-loop-test-gap.yaml` dogfood caller via `ci-loop-caller`
- [x] First `workflow_dispatch` run and the checks in [Operations and status](#operations-and-status) (items 1 and 2; items 3 and 4 stay open)
- [ ] Platform follow-up: PR-body check for the Checker (see [Checker criteria](#checker-criteria))

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Loop-Capable Skills](../loop-capable-skills.md)
- [Report Tech Debt Workflow Design](loop-tech-debt-workflow-design.md)
- [CI Sweeper Workflow Design](loop-ci-sweeper-workflow-design.md)
- [Specification](../../../reference/specification.md)
