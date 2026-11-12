# CI Sweeper Workflow Design

Workflow and domain design for the `ci-sweeper` loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-ci-sweeper.yaml` · skill `ci-sweeper` · `ci-sweeper/scripts/detect_ci_failures.sh` · `ci-sweeper/scripts/update_run_ledger.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Automated minimal repair when CI fails on integration branches and/or open PR heads. One engine; no separate `loop-pr-ci-healer` package.

Dogfood uses **`delivery: pr_create` for all repair paths**, including open PR heads (a new bot fix PR to the PR head branch). `pr_push` (push to an existing PR head) is a separate platform delivery — not the ci-sweeper default. See [Finalize strategy](#finalize-strategy).

Behaviors to know:

- The workflow has no `schedule` trigger. It runs on `workflow_run` (`completed`) of the CI workflows listed in `on-loop-ci-sweeper.yaml` and on `workflow_dispatch`. The job `if` passes only same-repository runs whose conclusion is `failure` or `startup_failure`; any other `workflow_run` event skips the job and writes no run-log row.
- Each target key has its own state: `integration:<branch>` for a watch branch and `pull_request:<number>` for a human PR head. The pending PR, the circuit breaker, and the cursor are per key.
- The run ledger, not the cursor, decides whether a failed run is processed again. Under the dogfood policy `block`, a run ID in the ledger is never processed again, whatever its outcome.

### Failure contexts

Two independent watch paths. Both use **`delivery: pr_create`**; **`level`** selects human review (L2) vs GitHub auto-merge on the bot fix PR (L3).

| Context        | Trigger example                          | Bot fix PR target (`to.branch`) |
| -------------- | ---------------------------------------- | ------------------------------- |
| `integration`  | CI fails on `main` after direct push     | `main`                          |
| `pull_request` | CI fails on PR head `hotfix/0001 → main` | `hotfix/0001` (PR head)         |

### End-to-end flows

#### Integration (`main` CI failure)

```text
L2:
  1. main CI fails
  2. Bot opens loop/* → main fix PR
  3. Human reviews and merges fix PR

L3:
  1. main CI fails
  2. Bot opens loop/* → main fix PR
  3. GitHub auto-merge on fix PR (allowlist + branch protection)
```

#### Pull request (`main ← hotfix/0001`, head CI failure)

```text
L2:
  1. Human PR #1 (hotfix/0001 → main) — CI fails on hotfix/0001
  2. Bot opens loop/* → hotfix/0001 fix PR (#2)
  3. Bot comments on human PR #1: fix summary, link to #2, merge or close guidance
  4. Human merges #2 into hotfix/0001 → CI on #1 goes green → human merges #1

L3:
  1–3. Same as L2, except bot fix PR (#2) is auto-merged into hotfix/0001
  4. Human merges #1 when CI is green
```

The human PR is **never** auto-merged by the loop. L3 auto-merge applies only to the **bot fix PR**.

## Use cases

| Use case                      | Trigger                                                                                                                                                                       | Outcome                                                                                                                                                                                             | Transition |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| Integration branch CI failure | `workflow_run` on a failed repair-target CI workflow on `main` (or another watch branch such as `develop`, `release/*`)                                                       | Open a bot fix PR **to** the watch branch; L3 enables GitHub **auto-merge** on that fix PR                                                                                                          | S0 -> S1   |
| Open PR head CI failure       | `workflow_run` on a failed CI run whose head is an eligible open PR                                                                                                           | Open a bot fix PR **to the PR head branch** (not `main`); post a marker comment on the **human PR** with fix summary and link to the bot fix PR; L3 auto-merges the bot fix PR into the head branch | S0 -> S1   |
| Classify and fix              | Every target                                                                                                                                                                  | Classify failures as Fix / Watch / Escalate; apply small lint, workflow, shell, or doc edits when actionable                                                                                        | S0 -> S1   |
| Dedupe and defer              | A failed run that is in the ledger, or that the skill classifies as infra/flake/env                                                                                           | Dedupe by `workflow_run_id` ledger; skip infra/flake/env failures as `outcome: watch`                                                                                                               | S0 -> S0a  |
| Manual scan                   | `workflow_run` on repair-target CI workflows (dogfood default); `workflow_dispatch` for manual / `gh run list` scan; see [ops checklist](#workflow_run-operational-checklist) | `workflow_dispatch` scans every watch branch and eligible open PR, up to `detect_max_targets` targets                                                                                               | S0 -> S1   |

## Out of scope

Entry skill design intent for failure kinds deferred via [Failure kind defer (B)](../loop-engineering-design.md#failure-kind-defer-b) — coverage threshold, dependency breakage.

- Infra outages, secrets, runner capacity, or persistent flakes (Watch — no code edit when Skill recognizes them)
- Large refactors (>5 files), auth/payment/credential paths
- Auto-merging the **human's** open PR (only the **bot fix PR** is auto-merged at L3)
- Re-running CI in the checker (semantic fit against log excerpt only)
- Manual interactive debugging as a substitute for the loop
- Separate `loop-pr-ci-healer` package
- **Coverage-threshold and test-gap repair** — defer (B) until a domain skill exists
- **Dependency-breakage repair** — defer (B); bot PR heads excluded in dogfood (`detect_pr_bot_allowlist` not set, so the default `""` excludes every author whose login ends in `bot`)
- Per-PR opt-in labels (`pr_require`) — removed; use `detect_pr_denylist` only

Skill execution boundaries: `ci-sweeper` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

## State model

The loop uses the shared states `S0`–`S5` from [Loop Workflow Design Template](loop-workflow-design-template.md#scheduled-loop-states), once per target key in `.loop/state-ci-sweeper.json` on `state_branch`: `integration:<branch>` for a watch branch, and `pull_request:<number>` for a human PR head. The run ledger `.loop/state-ci-sweeper-run-ledger.json` adds one row:

| ID  | State                                      | Trigger                                                                                                                             | Next state                                                       |
| --- | ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| S0a | Failed run settled without a PR (ledgered) | The skill classifies the failure as Watch, or the checker rejects the fix; the ledger records the run ID with `watch` or `rejected` | S0 when a new run fails (new run ID); the same run ID is skipped |

The values that hold each state in this loop:

| State | Values in this loop                                                                                                                                                                                                    |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S0    | Detect returns `skip: false`: a failed run on the key's head that is not skipped by the ledger policy and whose head SHA is `last_sha` or a descendant of it                                                           |
| S0a   | Ledger `runs[<run id>].outcome` is `watch` or `rejected` (`reject_count` + 1 on `rejected`); state `outcome` `watch` (counter kept) or `rejected` (`consecutive_failures` + 1)                                         |
| S1    | The bot fix PR carries `loop-automation`; `pending` holds `{ sha, pr, … }`; run-log `pr_created`; ledger `outcome` `pr_created`; for `pull_request` keys, the marker comment on the human PR links the bot fix PR      |
| S2    | `on-loop-state-promote` sets `last_sha` to `pending.sha`, removes `pending`, and sets `outcome` `pr_merged`, `consecutive_failures` `0`, and `open_rejections` `[]`                                                    |
| S3    | `on-loop-state-promote` removes `pending` and sets `outcome` `pr_closed`; `last_sha` and `consecutive_failures` do not change; the ledger keeps `pr_created`, so the same run ID is not processed again                |
| S4    | The bot fix PR stays open; detect for that key skips it, and when no other key yields a target the run records `skipped` with `skip_reason` `pending_pr`                                                               |
| S5    | `consecutive_failures` of the key is 3 or more and its `last_run` is less than 30 days old; detect skips the key, and when no other key yields a target the run records `skipped` with `skip_reason` `circuit_breaker` |

Only `rejected` raises `consecutive_failures`; three in a row on one key move that key to S5. Other keys keep running. Retry limits and resets are in [State delivery](#state-delivery).

## User actions

Each row is one action a person can take on the loop's output or on the CI it watches, the loop response, and what the person sees next. The Transition column references [State model](#state-model).

| User action                                                                                                                                         | Loop response                                                                                                                                                                                                                                                                | Values changed                                                                                                                                                      | Result and next action                                                                                  | Transition     |
| --------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | -------------- |
| Merge the bot fix PR into `main`                                                                                                                    | `on-loop-state-promote` (`pull_request_target` `closed`, job gated on `loop-automation`) promotes the pending state of `integration:main`                                                                                                                                    | `last_sha` = `pending.sha`; `pending` removed; `outcome` `pr_merged`; `consecutive_failures` `0`; `open_rejections` `[]`                                            | CI runs on `main` again. A new failure is a new run ID and a new target                                 | S1 -> S2 -> S0 |
| Merge the bot fix PR into the human PR head                                                                                                         | `on-loop-state-promote` promotes the pending state of `pull_request:<n>` (it reads state from `main`, not from the PR base)                                                                                                                                                  | As for the `main` merge, on the `pull_request:<n>` key                                                                                                              | CI runs on the human PR. Merge the human PR when CI is green                                            | S1 -> S2 -> S0 |
| Close the bot fix PR without merging                                                                                                                | `on-loop-state-promote` clears the pending state                                                                                                                                                                                                                             | `pending` removed; `outcome` `pr_closed`; `last_sha` and `consecutive_failures` unchanged; ledger keeps `pr_created`                                                | The same failed run is not processed again. Fix CI by hand, or push to get a new failed run             | S1 -> S3 -> S0 |
| Delete the loop branch of an open bot fix PR                                                                                                        | GitHub closes the PR, and `on-loop-state-promote` clears the pending state                                                                                                                                                                                                   | As for closing the PR                                                                                                                                               | As for closing the PR                                                                                   | S1 -> S3 -> S0 |
| Leave the bot fix PR open                                                                                                                           | Later failures on the same head find the open `pending.pr` and skip that key; `record-skip` appends the run log when no other key yields a target                                                                                                                            | Run-log `skipped`, `skip_reason` `pending_pr`                                                                                                                       | No new fix PR opens for that key until the PR is merged or closed                                       | S1 -> S4       |
| Push commits to the bot fix PR branch                                                                                                               | CI runs on the bot fix PR. A failure raises `workflow_run`, but detect scopes to the loop branch and the bot-authored PR is excluded, so the run records `skipped` (`no_changes`)                                                                                            | Branch and PR head; run-log `skipped` on a failure; `pending.sha` keeps the detect SHA                                                                              | Merging still promotes `pending.sha`                                                                    | -              |
| Fix CI yourself by pushing to `main` or to the human PR head                                                                                        | A green run skips the job (`if` passes only `failure` and `startup_failure`). A red run is a new run ID and a new target, unless the key is pending or stopped                                                                                                               | None on a green run; on a red run, as for a new target                                                                                                              | Close the bot fix PR if your push made it obsolete                                                      | -              |
| Re-run a failed CI workflow from the Actions page                                                                                                   | A re-run keeps the run ID. If it fails again, the ledger already holds that ID, so `block` skips it                                                                                                                                                                          | Run-log `skipped`, `skip_reason` `no_changes` when the ledger skip leaves no target                                                                                 | To retry the loop on that run, remove the run ID from the ledger file by PR, or change the retry policy | -              |
| Mark the human PR draft, add `no-loop`, or open it from a fork                                                                                      | `detect_pr_denylist` (`fork,draft,label:no-loop`, the caller default) excludes the PR; a fork run never passes the job `if`                                                                                                                                                  | Run-log `skipped`, `skip_reason` `no_changes` for in-repository runs; none for fork runs                                                                            | Remove the label or mark the PR ready; the next failed run is picked up                                 | -              |
| Comment on, review, or resolve a thread on the bot fix PR or on the marker comment of the human PR                                                  | Nothing runs in this loop. A `@loop` mention follows the intake of [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md)                                                                                                                                     | None in this loop                                                                                                                                                   | Edit the bot fix PR by hand, or close it                                                                | -              |
| Remove `loop-automation` from the bot fix PR                                                                                                        | Nothing runs now. When the PR later closes, the `on-loop-state-promote` job `if` refuses it                                                                                                                                                                                  | Label only; `pending` stays; on merge `last_sha` does not advance and `consecutive_failures` is not reset                                                           | Detect treats a closed or merged `pending.pr` as stale and runs as usual                                | -              |
| Start `workflow_dispatch` (no inputs)                                                                                                               | Detect scans every watch branch and every eligible open PR (`gh run list`, `SCAN_BRANCH_RUN_LIMIT` 100 per branch), applies the ledger and the `since` filter, and caps the matrix at `detect_max_targets` (`3`); it waits in the concurrency group `loop-state-main`        | As for a new target per key; or run-log `skipped` (`no_changes`, `pending_pr`, `circuit_breaker`, `budget`); only runs that start the agent count toward the budget | Review each bot fix PR                                                                                  | S0 -> S1       |
| Re-run a failed `on-loop-ci-sweeper` run from the Actions page                                                                                      | Detect runs again with the same event payload against the current state and ledger                                                                                                                                                                                           | As for a new run                                                                                                                                                    | An `error` run left no ledger entry, so the same failed run is retried                                  | -              |
| Reset the circuit breaker by a PR to `main` that edits `.loop/state-ci-sweeper.json`                                                                | Nothing runs on merge; the next event or dispatch reads the new state                                                                                                                                                                                                        | `consecutive_failures` of the key set to `0` (or the key removed)                                                                                                   | Fix the cause of the rejections first                                                                   | S5 -> S0       |
| Change `.loop/loop-budget.json`, `detect_env_json` (ledger policy), the `workflow_run.workflows` list, or other caller inputs by PR after a failure | Nothing runs on merge. The next event or dispatch uses the new values                                                                                                                                                                                                        | `.loop/loop-budget.json` caps (they override caller `budget_*`); `CI_SWEEPER_REJECT_RETRY_POLICY` and `CI_SWEEPER_REJECT_MAX_RETRIES`; caller inputs                | Start `workflow_dispatch` to apply them now                                                             | -              |
| Do nothing (CI stays green)                                                                                                                         | Every `workflow_run` event skips the job                                                                                                                                                                                                                                     | None                                                                                                                                                                | -                                                                                                       | -              |
| Commits, PRs, and CI runs that the loop or other bots create (state and ledger commits, run log, bot PRs)                                           | State, ledger, and run-log commits carry `[skip ci]`, so they start no CI. `workflow_run.workflows` lists no `on-loop-*` or `ci-loop-*` caller. A failure on a bot-authored PR or on a branch with no open PR leaves no target, and the run records `skipped` (`no_changes`) | Run-log `skipped`, `skip_reason` `no_changes`                                                                                                                       | -                                                                                                       | -              |

Not applicable: 3, 5 — the loop uses no mention token and reads or writes no Issue.

## Unhandled cases

| Case                                                                          | Why nothing follows                                                                                                                                                                                                                                                                                            | Disposition |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| The circuit breaker stops a key                                               | Recovers on its own: once `last_run` is older than 30 days, detect lets one run through (`target_circuit_breaker_open` in `guards.sh`); a `rejected` result reopens the breaker for another 30 days, any other result closes it. No notification: the trip shows only as run-log `skipped` (`circuit_breaker`) | Limitation  |
| A scan finds several failed runs for one key                                  | `loop-detect` copies only `failures[0]` into `target_json` (`workflow_run_id`, `workflow_name`, `head_sha`), and `update_run_ledger.sh` records only that run ID. The other runs stay out of the ledger, so the next scan finds them again even when the merged fix PR already covered them                    | Follow-up   |
| A PR author is a bot whose login does not end in `bot`                        | The bot exclusion matches the login suffix `bot` (case-insensitive) only, so such a PR is watched like a human PR. The loop's own App login (`app/repo-maintenance-bot` in the tests) ends in `bot`                                                                                                            | Follow-up   |
| The human PR is merged or closed while its bot fix PR is open                 | Nothing closes the bot fix PR. If the head branch is deleted, GitHub closes the bot fix PR and promote clears `pending`; otherwise the bot fix PR stays open against an orphaned branch until a person closes it                                                                                               | Follow-up   |
| `pull_request:<n>` keys that never end in `rejected` or `pr_closed`           | `prune_targets.sh` deletes a `pull_request:*` key only when its outcome is `rejected` or `pr_closed`; keys with `pr_merged`, `watch`, `unchanged`, or `error` stay forever (the dogfood state keeps `pull_request:1025` with `pr_merged`)                                                                      | Follow-up   |
| Parallel matrix targets of one `workflow_dispatch` run race on the state push | With `finalize_commit_paths` set, `write_state.sh` does not retry a push race; the losing job opens a state PR, which needs a manual merge when it conflicts                                                                                                                                                   | Follow-up   |
| A person closes the bot fix PR to decline it                                  | The ledger keeps `pr_created`, so the loop does not retry that run; a later failure is a new run ID and gets a new attempt                                                                                                                                                                                     | Accepted    |
| The checker rejects a fix under the `block` policy                            | The run ID is ledgered as `rejected` and not retried; `retry` or `limited` in `detect_env_json` changes this                                                                                                                                                                                                   | Accepted    |
| A person removes `loop-automation` from the bot fix PR                        | `on-loop-state-promote` skips the PR and `pending` stays. Detect treats a closed or merged `pending.pr` as stale, and the ledger decides re-processing, so the loop keeps running                                                                                                                              | Accepted    |
| A person comments on or reviews the bot fix PR                                | The loop reads no PR comments; the person edits the PR or closes it                                                                                                                                                                                                                                            | Accepted    |
| A failed run is older than the 100 most recent failed runs of its branch      | `workflow_dispatch` scans only `SCAN_BRANCH_RUN_LIMIT` runs per branch; `workflow_run` events still handle each new failure                                                                                                                                                                                    | Limitation  |

## Failure and recovery

| Failure kind                                               | How it is recorded                                                                                                                                            | Who acts   | What they do                                                                                       | How the loop resumes                                                                                                 |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Detect script fails, or `workflow_run` scope is incomplete | The `detect` job fails (no run-log row), or detect records `skipped` with `skip_reason` `config_error`                                                        | Maintainer | Fix the script, the token, or `detect_env_json`                                                    | The next failed CI run or `workflow_dispatch`                                                                        |
| Checker `REJECT` (including a Fix with no diff)            | Run-log `rejected`; state `outcome` `rejected`, `last_reject_reason`, `consecutive_failures` + 1; ledger `rejected`, `reject_count` + 1; agent branch deleted | Maintainer | Read the reason; adjust `agent_maker_instructions` or `agent_checker_instructions` by PR           | A new failed run; the same run ID only under `retry` or `limited`; the third `rejected` in a row moves the key to S5 |
| Skill classifies Watch                                     | Run-log `watch`; state `outcome` `watch` (counter kept); ledger `watch`                                                                                       | Maintainer | Check the infra, flake, or env cause by hand                                                       | A new failed run                                                                                                     |
| Agent, push, or PR creation error                          | Run-log `error` with `failure_stage`; when a `loop-finalize` step fails, the later steps are skipped, so neither state nor ledger is written                  | Maintainer | Fix the cause                                                                                      | The same failed run is not ledgered, so the next event or `workflow_dispatch` retries it                             |
| Circuit breaker open on a key                              | Run-log `skipped`, `skip_reason` `circuit_breaker` when no other key yields a target                                                                          | Maintainer | Fix the cause, then reset `consecutive_failures` of the key in `.loop/state-ci-sweeper.json` by PR | The next event or dispatch after the merge (S5 -> S0)                                                                |
| Daily budget used up                                       | Run-log `skipped`, `skip_reason` `budget`                                                                                                                     | Maintainer | Wait, or raise the cap in `.loop/loop-budget.json` by PR                                           | The next failed run or `workflow_dispatch`; runs skipped meanwhile are not ledgered and a dispatch finds them        |
| State promote fails after a merge                          | The `on-loop-state-promote` run fails; `pending` stays with a merged `pending.pr`                                                                             | Maintainer | Re-run the failed `on-loop-state-promote` run                                                      | Detect treats the stale `pending` as not blocking                                                                    |

## Caller inputs

Keys are passed in `on-loop-ci-sweeper.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_checker_instructions`, `agent_maker_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

Triggers: `workflow_run` (`completed`) on `on-cd-mkdocs`, `on-ci-push-apm-audit`, `on-ci-push-github-actions-workflow`, `on-ci-push-markdown`, `on-ci-push-mise-update-lock`, `on-ci-push-shell-script`, and `on-ci-security`, plus `workflow_dispatch`. No `schedule`. Concurrency group `loop-state-main` (`cancel-in-progress: false`, `queue: max`).

**Dogfood minimum (autonomy + delivery + PR watch):**

```yaml
agent_edit_target: fix
delivery: pr_create
detect_pr_enabled: true
level: L2
```

`detect_pr_denylist` is not set in the caller; the `ci-loop-caller.yaml` default `fork,draft,label:no-loop` applies.

`delivery` is the only declaration of how the output lands (`pr_create`, `pr_push`, or `none`); there is no separate git-landing input, and the agent edit gate (`agent_edit_allowed`) is derived from `level`. See [Level × finalize matrix](loop-caller-inputs-reference.md#level--finalize-matrix).

| Input / JSON key             | Description                                                                                                                                                                                                                                                                                 | Dogfood value                                                                                                                               |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `finalize_commit_paths`      | Extra paths included in finalize commit (ledger file).                                                                                                                                                                                                                                      | `.loop/state-ci-sweeper-run-ledger.json`                                                                                                    |
| `agent_maker_max_turns`      | Max maker agent turns per loop attempt (one Agent→Verify cycle).                                                                                                                                                                                                                            | `100`                                                                                                                                       |
| `agent_maker_model`          | Maker model ID. Cursor: `agent --list-models`.                                                                                                                                                                                                                                              | `claude-sonnet-5`                                                                                                                           |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                                                                                                | `medium`                                                                                                                                    |
| `agent_loop_max_attempts`    | Max Agent→Verify retry cycles before finalize records failure.                                                                                                                                                                                                                              | `3`                                                                                                                                         |
| `agent_checker_instructions` | Checker APPROVE/REJECT rubric. Requires fix addresses logged CI failure; minimal diff; allowlist/denylist respected.                                                                                                                                                                        | Inline in caller workflow                                                                                                                   |
| `agent_checker_max_turns`    | Max checker agent turns per verification.                                                                                                                                                                                                                                                   | `100`                                                                                                                                       |
| `agent_checker_model`        | Checker model ID. Cursor: `agent --list-models`.                                                                                                                                                                                                                                            | `claude-opus-5`                                                                                                                             |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                                                                                              | `medium`                                                                                                                                    |
| `agent_checker_path_pattern` | Extended regex to infer file paths from checker text.                                                                                                                                                                                                                                       | See caller workflow                                                                                                                         |
| `agent_edit_allowlist`       | Comma-separated globs the maker may modify. `.github/**` also allows `.github/workflows/` changes: finalize pushes the agent branch, and a pushed workflow runs with repository secrets on `on: push`, so this loop accepts that exposure. Callers with `**` only are refused such changes. | `.apm/packages/**,.github/**,docs/**/*.md,renovate/**,scripts/**,test/**,apm.yml,mise.toml,mkdocs.yml,README.md`                            |
| `agent_edit_target`          | Agent artifact when `agent_edit_allowed` is true.                                                                                                                                                                                                                                           | `fix`                                                                                                                                       |
| `agent_report_check`         | Deterministic check of the maker report before the checker (`paths`: `### Changes` lists repository paths).                                                                                                                                                                                 | `paths`                                                                                                                                     |
| `agent_tool_allowlist`       | Read-only `gh` rules and the validation scripts for the maker; the agent job has no write credential.                                                                                                                                                                                       | `gh api -X GET`, `gh run list`, `gh run view`, `git remote get-url`, `validate.sh` of github-actions, markdown, and shell-script validation |
| `delivery`                   | Platform delivery after APPROVE.                                                                                                                                                                                                                                                            | `pr_create`                                                                                                                                 |
| `detect_branch_match`        | Comma-separated integration branch patterns to poll for failed CI.                                                                                                                                                                                                                          | `main`                                                                                                                                      |
| `state_branch`               | Branch for `.loop/*` persistence, and state migration (it no longer doubles as a watch fallback).                                                                                                                                                                                           | `main`                                                                                                                                      |
| `budget_max_runs_per_day`    | Daily run cap keyed by `loop_name`. Caller input; `.loop/loop-budget.json` overrides when present.                                                                                                                                                                                          | `5` (caller); effective `50` via `.loop/loop-budget.json`                                                                                   |
| `budget_max_tokens_per_day`  | Daily aggregated token cap across loops.                                                                                                                                                                                                                                                    | `1000000`                                                                                                                                   |
| `agent_edit_denylist`        | Not set — the platform default (`**/.env,**/credentials*,**/secrets*`) applies.                                                                                                                                                                                                             | Omitted                                                                                                                                     |
| Reusable workflow (`uses:`)  | `ci-loop-caller.yaml` — detect job requires `actions: write`, `contents: read`, and `pull-requests: read`; caller `permissions` must include `actions: write`.                                                                                                                              | `./.github/workflows/ci-loop-caller.yaml`                                                                                                   |
| `detect_script`              | Domain detect script path. Uses `gh run list` per watch branch / PR head.                                                                                                                                                                                                                   | `.agents/skills/ci-sweeper/scripts/detect_ci_failures.sh`                                                                                   |
| `finalize_script`            | Bash script for `loop-finalize` domain persistence (run ledger updates).                                                                                                                                                                                                                    | `.agents/skills/ci-sweeper/scripts/update_run_ledger.sh`                                                                                    |
| `agent_engine`               | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                                                                                                                                                       | `claude`                                                                                                                                    |
| `level`                      | Autonomy: `L2` (human merges bot fix PR) or `L3` (GitHub auto-merge on bot fix PR).                                                                                                                                                                                                         | `L2`                                                                                                                                        |
| `loop_name`                  | Loop identifier; state file `.loop/state-ci-sweeper.json`.                                                                                                                                                                                                                                  | `ci-sweeper`                                                                                                                                |
| `detect_max_targets`         | Max targets per run after priority filters. Not set; the caller default applies. A `workflow_run` event scopes detect to one head, so it yields at most one target.                                                                                                                         | `3` (default)                                                                                                                               |
| `agent_unchanged_verdict`    | `APPROVE` or `REJECT` when maker produces no file diff on actionable CI failure.                                                                                                                                                                                                            | `REJECT`                                                                                                                                    |
| `pr_body`                    | Optional static prefix (dogfood: `""`). `loop-finalize` composes agent Overview/Summary + mechanical sections. See [Loop PR Body Readable Design](../../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md).                                                                   | `""`                                                                                                                                        |
| `detect_pr_enabled`          | Watch open PR heads for failed CI.                                                                                                                                                                                                                                                          | `true`                                                                                                                                      |
| `detect_pr_denylist`         | PR exclusion tokens: `fork`, `draft`, `label:<name>`, `wip_title`. Not set; the caller default applies.                                                                                                                                                                                     | `fork,draft,label:no-loop` (default)                                                                                                        |
| `detect_pr_bot_allowlist`    | Comma-separated bot logins to include when scanning PRs. Empty = exclude all bots. Not set; the caller default applies.                                                                                                                                                                     | `""` (default)                                                                                                                              |
| `pr_title`                   | PR title when `delivery` is `pr_create`.                                                                                                                                                                                                                                                    | `chore(ci-sweeper): automated CI repair (loop-ci-sweeper)`                                                                                  |
| `agent_maker_instructions`   | Domain instructions: classify Watch vs Fix; minimal diff; run validation skills.                                                                                                                                                                                                            | Inline in caller workflow                                                                                                                   |
| `agent_maker_skill_name`     | Skill package to invoke.                                                                                                                                                                                                                                                                    | `ci-sweeper`                                                                                                                                |

**Removed from dogfood (do not set):** `pr_require`, `finalize_integration`, `finalize_pull_request` (replaced by `delivery`).

### Domain detect environment (`detect_env_json`)

| JSON key                         | Description                                     | Dogfood value                            |
| -------------------------------- | ----------------------------------------------- | ---------------------------------------- |
| `CI_SWEEPER_LEDGER_FILE`         | JSON ledger for `workflow_run_id` dedupe        | `.loop/state-ci-sweeper-run-ledger.json` |
| `CI_SWEEPER_REJECT_MAX_RETRIES`  | Max retries per run ID when policy is `limited` | `"3"`                                    |
| `CI_SWEEPER_REJECT_RETRY_POLICY` | `block`, `retry`, or `limited`                  | `block`                                  |

**Event keys** (embed when `workflow_run` trigger is enabled on the caller). Dogfood builds one JSON object with the ledger keys and the event keys, each value through `toJSON()`, and keeps the keys in alphabetical order:

```yaml
detect_env_json: |
  ${{ format(
    '{{"CI_SWEEPER_EVENT_HEAD_BRANCH":{0},"CI_SWEEPER_HEAD_BRANCH":{0},"CI_SWEEPER_HEAD_SHA":{1},"CI_SWEEPER_LEDGER_FILE":".loop/state-ci-sweeper-run-ledger.json","CI_SWEEPER_REJECT_MAX_RETRIES":"3","CI_SWEEPER_REJECT_RETRY_POLICY":"block","CI_SWEEPER_RUN_URL":{2},"CI_SWEEPER_WORKFLOW_NAME":{3},"CI_SWEEPER_WORKFLOW_RUN_ID":{4}}}',
    toJSON(github.event.workflow_run.head_branch || 'main'),
    toJSON(github.event.workflow_run.head_sha || github.sha),
    toJSON(github.event.workflow_run.html_url || ''),
    toJSON(github.event.workflow_run.name || ''),
    toJSON(format('{0}', github.event.workflow_run.id || ''))
  ) }}
```

| JSON key                       | Description                                                                                                      |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `CI_SWEEPER_EVENT_HEAD_BRANCH` | Stable failed-run head (not rewritten per scan). With `WORKFLOW_RUN_ID`, scopes `loop-detect` to that head only. |
| `CI_SWEEPER_HEAD_BRANCH`       | Initial head; `loop-detect` rewrites per scan context                                                            |
| `CI_SWEEPER_HEAD_SHA`          | Failed run head SHA                                                                                              |
| `CI_SWEEPER_WORKFLOW_RUN_ID`   | Failed run ID for ledger dedupe + trigger-aware target scoping                                                   |
| `CI_SWEEPER_WORKFLOW_NAME`     | Failed workflow display name                                                                                     |
| `CI_SWEEPER_RUN_URL`           | HTML URL of failed run                                                                                           |

On `workflow_dispatch` the event fields are empty, so `CI_SWEEPER_WORKFLOW_RUN_ID` is `""` and detect scans every watch branch and eligible open PR.

### Execute-only inputs

| Input                   | Dogfood value                                            |
| ----------------------- | -------------------------------------------------------- |
| `finalize_commit_paths` | `.loop/state-ci-sweeper-run-ledger.json`                 |
| `finalize_script`       | `.agents/skills/ci-sweeper/scripts/update_run_ledger.sh` |

When `CI_SWEEPER_WORKFLOW_RUN_ID` is set, `loop-detect` enumerates **only** the failed head (matching integration branch or open PR). See [Trigger-aware priority](../multi-branch-loops-design.md#trigger-aware-priority). Detect script binaries are always pinned from the job checkout (branch_state), never from a stale PR worktree.

## Detect

### Stable mechanical filters (detect script + platform)

Detect applies **only** stable gates — not semantic failure classification:

| Filter                                   | Layer                  |
| ---------------------------------------- | ---------------------- |
| Ledger dedupe (`workflow_run_id`)        | detect script          |
| `workflow_run` caller `workflows:` list  | caller trigger         |
| `workflow_run` → single failed head      | `loop-detect` scope    |
| Pin `DETECT_SCRIPT` absolute path        | `loop-detect`          |
| Event run branch vs scan branch          | detect script          |
| PR exclusion (fork, draft, bot, label)   | `loop-detect` + script |
| Workflow concurrency (`loop-state-main`) | `on-loop-*.yaml`       |
| Budget / circuit breaker                 | `loop-detect`          |

`failure_type` from grep heuristics is an optional **hint** for the Skill — not a detect gate. Default is `regression` when the log is not infra/env/flake. See [Execute — responsibility split](#execute--responsibility-split-a--b).

### Integration mode

Per watch branch, `loop-detect` sets context; script uses `gh run list --branch <watch_branch> --status failure`.

- Range filter via `targets["integration:<branch>"].last_sha`
- **Dedupe:** `state-ci-sweeper-run-ledger.json` keyed by `workflow_run_id` (entries pruned after **30 days** on ledger update)

### Pull request mode

Requires `detect_pr_enabled: true`.

- Failed runs where `head_branch` matches an eligible open PR
- Emit `pr_number`, `base.branch` in `target_json.to`
- Apply [PR exclusion rules](#pr-exclusion-detect_pr_denylist)

### Detect truth source

| Mode         | Primary cursor             | Secondary                                                 |
| ------------ | -------------------------- | --------------------------------------------------------- |
| integration  | `workflow_run_id` + ledger | `last_sha` in state (advances when the bot fix PR merges) |
| pull_request | `workflow_run_id` + ledger | `last_sha` of the `pull_request:<number>` key in state    |

**Rule:** Do not rely on `last_sha` alone to skip a still-failing workflow run. Under the `block` policy any ledger outcome (`pr_created`, `pr_pushed`, `watch`, `rejected`, or `unchanged`) blocks re-processing the same run ID. `last_sha` drops only runs whose head SHA is not `last_sha` or a descendant of it.

### Run ledger and REJECT retry policy (caller / detect)

Owned by the **caller** and detect scripts — not by skill triage. Configure via `detect_env_json`:

| Variable                         | Default (portable detect default)        | Dogfood                                  | Description                                                                                                                                        |
| -------------------------------- | ---------------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CI_SWEEPER_LEDGER_FILE`         | `.loop/state-ci-sweeper-run-ledger.json` | `.loop/state-ci-sweeper-run-ledger.json` | Repo-relative ledger keyed by `workflow_run_id`                                                                                                    |
| `CI_SWEEPER_REJECT_RETRY_POLICY` | `block`                                  | `block`                                  | `block`: skip any ledgered run. `retry`: skip only `pr_created` and `pr_pushed`. `limited`: skip `rejected` after max retries. Aliases `a`/`b`/`c` |
| `CI_SWEEPER_REJECT_MAX_RETRIES`  | `3`                                      | `3`                                      | Used when policy is `limited`                                                                                                                      |

`update_run_ledger.sh` (via `finalize_script`) prunes `runs` older than **30 days**. It records `pr_created`, `pr_pushed`, `rejected`, `unchanged`, and `watch`, and skips `error` and `escalated`. Detect places skipped runs in `ignored[]`; the skill only notes them in Overview.

### `agent_unchanged_verdict: REJECT`

When the Skill classifies **Fix** but the maker produces no changes → REJECT → `outcome: rejected`.

When the Skill classifies **Watch** (infra/flake/env) with no code edit → `outcome: watch` (not REJECT). See [Outcome enum](../../../reference/specification.md#outcome-enum).

### PR exclusion (`detect_pr_denylist`)

| Rule          | Default     | Token                                   |
| ------------- | ----------- | --------------------------------------- |
| Fork PR       | Exclude     | `fork`                                  |
| Draft         | Exclude     | `draft`                                 |
| Label opt-out | Exclude     | `label:<name>`                          |
| Bots          | **Exclude** | use `detect_pr_bot_allowlist` to opt in |
| WIP title     | Optional    | `wip_title`                             |

No label opt-in (`pr_require`) — eligible open PRs passing `detect_pr_denylist` are watched when `detect_pr_enabled: true`. The bot rule treats an author as a bot when the login ends in `bot` (case-insensitive).

After finalize on `pull_request` targets, `loop-notify-pr` posts or updates a marker comment on the **human PR** (`target_json.to.pr_number`), including the bot fix PR URL when finalize creates one. See [loop-notify-pr Specification](../../../reference/loop-notify-pr-specification.md).

## Execute

- Worktree: `target.from` (see [platform table](../multi-branch-loops-design.md#execute-and-checker-platform))
- **`verifier_context`:** failed job log excerpt from detect `result` — **always** wired (integration and pull_request)

```yaml
with:
  target_json: ${{ toJson(matrix.target.target_json) }}
  verifier_context: ${{ matrix.target.verifier_context }}
```

### Execute — responsibility split (A' / B)

Distributable `ci-sweeper` skill stays repository-neutral. **Do not** hardcode consumer skill names in skill `references/`. Named dispatch belongs in caller `agent_maker_instructions` (dogfood: `on-loop-ci-sweeper.yaml`).

| Layer         | Input                        | Role                                                                                            |
| ------------- | ---------------------------- | ----------------------------------------------------------------------------------------------- |
| Detect        | `detect_ci_failures.sh`      | `failures[]`, `failure_type` hint; optional future `stack_hint`                                 |
| Entry skill   | `ci-sweeper`                 | Generic orchestration: classify, follow `## Instructions` for skill dispatch, fix one, validate |
| Caller        | `agent_maker_instructions`   | **Stack routing (A')** — workflow/stack → named domain skills for this repo                     |
| Caller        | `agent_checker_instructions` | Failure kind defer (B): appendix REJECT rules                                                   |
| Domain skills | Consumer `.agents/skills/*`  | Invoked per caller routing table                                                                |

See [CI failure repair — layered responsibilities](../loop-engineering-design.md#ci-failure-repair--one-package-layered-responsibilities).

### Checker criteria (caller-owned)

CI sweeper criteria require the fix to address the **logged failure** (semantic fit against `verifier_context`). This does not violate the generic rule “checker does not re-run CI” — see [Loop Engineering — Verify](../loop-engineering-design.md#verify).

## Finalize

### Finalize strategy

PR body is composed by `loop-finalize` from agent `## Overview` / `## Summary` (skill-owned) plus mechanical sections. Dogfood sets `pr_body: ""`. See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

Platform rule for dogfood loops (changelog, docs-updater, ci-sweeper): **`delivery` is always `pr_create`**. **`level`** controls review vs auto-merge on the **bot fix PR**.

| Mode           | L2                                        | L3                                                        |
| -------------- | ----------------------------------------- | --------------------------------------------------------- |
| `integration`  | Bot fix PR → `to.branch`; human merge     | Bot fix PR → `to.branch`; **GitHub auto-merge**           |
| `pull_request` | Bot fix PR → PR head; comment on human PR | Bot fix PR → PR head; **auto-merge**; comment on human PR |

Reference: [Finalize strategy matrix](../loop-engineering-design.md#finalize-strategy-matrix).

| Persistence | Mechanism                                                 |
| ----------- | --------------------------------------------------------- |
| State       | `state-ci-sweeper.json` (`targets` map) on `state_branch` |
| Run ledger  | `finalize_script` → `update_run_ledger.sh`                |
| Run log     | `loop-run-log` in `loop-finalize` chain                   |

`update_run_ledger.sh` runs in the `Run Finalize Hook` step, before `Create PR`, with the outcome that `Determine Outcome` computed. `Write State` commits the ledger file through `finalize_commit_paths`; when an earlier `loop-finalize` step fails, `Write State` is skipped and the ledger change is not committed.

Dogfood: **`level=L2`** until [L3 promotion gate](../loop-engineering-design.md).

## State delivery

See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) for platform rules.

**Target (dogfood):** merge-gated `pending` + `on-loop-state-promote` per target key, plus the run ledger committed with each finalize state write.

### Retry limits and circuit breaker

| Value                     | Rule                                                                                                                                                                                                                             |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `agent_loop_max_attempts` | Agent→Verify cycles inside one run (`3`); the last verdict decides the run outcome                                                                                                                                               |
| Ledger retry policy       | `CI_SWEEPER_REJECT_RETRY_POLICY` `block`: a run ID in the ledger is never processed again                                                                                                                                        |
| `consecutive_failures`    | Per key. `loop-finalize` adds 1 on `rejected`, keeps it on `watch` and `error`, and sets it to `0` on any other outcome; `on-loop-state-promote` sets it to `0` on merge and leaves it on close                                  |
| Circuit breaker           | `loop-detect` skips a key whose `consecutive_failures` is 3 or more and whose `last_run` is less than 30 days old; `skip_reason` `circuit_breaker` is recorded when no other key yields a target                                 |
| Cooldown                  | On any finalize state write, an `integration:*` key whose `outcome` is `rejected` or `pr_closed` and whose `last_run` is older than 30 days gets `consecutive_failures` `0`; a `pull_request:*` key in that condition is deleted |
| Pending PR                | `loop-detect` skips a key while its `pending.pr` is open (or its state cannot be read); a closed or merged `pending.pr` is treated as stale                                                                                      |
| Concurrency               | Workflow group `loop-state-main` (`cancel-in-progress: false`, `queue: max`), shared with the other scheduled loops and `on-loop-state-promote`                                                                                  |

### Cross-Loop Note

CI failure on `integration:main` is serialized with `docs-updater` and `changelog` via [workflow concurrency](../multi-branch-loops-design.md#cross-loop-coordination-workflow-concurrency). Limit recursion with `workflow_run.workflows` (caller allowlist), run ledger (`workflow_run_id`), and daily budget — not workflow-name exclude lists in detect.

`workflow_dispatch` (no event run ID) uses `gh run list` on the watch branch (`SCAN_BRANCH_RUN_LIMIT`, default 100), then ledger and `since` range filters. Skill classifies infra/env/flake failures as Watch.

## Operations

### workflow_run Operational Checklist

Dogfood `on-loop-ci-sweeper.yaml` enables `workflow_run`. Keep these gates when changing the trigger or `workflows:` list:

- [x] zizmor / security review complete (`zizmor: ignore[dangerous-triggers]` documented on the trigger)
- [x] `workflow_run.workflows` lists only CI workflows to repair (not `on-loop-*` / `ci-loop-*` callers)
- [x] Concurrency prevents overlapping runs on same workflow
- [x] Event path sets `CI_SWEEPER_*` keys in `detect_env_json`
- [x] Failed workflow is not the sweeper’s own finalize push (`[skip ci]` on ledger commits)
- [x] Fork / draft / bot exclusions active (`detect_pr_denylist`)
- [x] Job `if:` limits event runs to `failure` / `startup_failure`
- [x] 1 failure event → 1 target (no unbounded matrix from one event) — `loop-detect` scopes watch list to failed head when `CI_SWEEPER_WORKFLOW_RUN_ID` is set; verify when expanding `workflows:`

### Dependency update (caller filter + domain skill)

Tier 3 **dependency-update** behavior is a domain skill plus caller PR filters (`detect_pr_bot_allowlist`, `detect_pr_denylist`) under **`ci-sweeper`** — not a separate loop package. Defer via [Failure kind defer (B)](../loop-engineering-design.md#failure-kind-defer-b) until the skill exists.

## Implementation Checklist

Shared platform: [Multi-Branch — Shared platform checklist](../multi-branch-loops-design.md#shared-platform-checklist-all-loops).

### Loop-specific

- [x] `ci-sweeper/scripts/detect_ci_failures.sh` (facts output)
- [x] `on-loop-ci-sweeper.yaml` dogfood caller via `ci-loop-caller`
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.failures` branch)
- [x] Single detect path via `loop-detect` (no caller re-run)
- [x] `detect_pr_enabled`
- [x] Ledger via `finalize_script` in `loop-finalize`
- [x] `outcome: watch` for Skill Watch classification
- [x] `loop-notify-pr` on human PR for `pull_request` mode
- [x] `pr_create` delivery for PR head targets (a new bot fix PR to the PR head branch)

## References

- [cobusgreyling ci-sweeper pattern](https://github.com/cobusgreyling/loop-engineering/blob/main/patterns/ci-sweeper.md)
- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
