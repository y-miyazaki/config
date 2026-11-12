# Changelog Loop Workflow Design

Workflow and domain design for the `changelog` loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-changelog.yaml` · skill `changelog` · `changelog/scripts/detect_changelog_commits.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Maintain [Keep a Changelog](https://keepachangelog.com/) `CHANGELOG.md` on integration branches: preserve existing release sections, append to `## [Unreleased]`, promote undocumented releases detected from git tags and pin/finalize commits, then open **one domain-only** L2 review PR (`CHANGELOG.md` only). Loop state advances on merge via `on-loop-state-promote`.

### User-facing invariants

| Invariant                   | Rationale                                                                                                          |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| One review PR (domain only) | Reviewers judge `CHANGELOG.md` only; loop state advances on merge via `on-loop-state-promote`                      |
| No orphan state PRs         | Workflow concurrency (`loop-state-main`) serializes with peer loops; merge-gated `pending` lands on `state_branch` |
| Release sections from facts | Skill may add `## [version] - date` only for versions in detect `releases[]` — never invented versions             |

### Modes

| Mode           | Default | Behavior                                       |
| -------------- | ------- | ---------------------------------------------- |
| `integration`  | on      | Detect on watch branch → fix PR to same branch |
| `pull_request` | off     | not supported for this loop                    |

## Use cases

| Use case                                   | Trigger                                                                                                                                                                                                                              | Outcome                                                                                                                                               | Transition     |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| Record new commits under `## [Unreleased]` | Weekly `schedule` (Friday 10:00 UTC) or `workflow_dispatch` finds [Conventional Commits](https://www.conventionalcommits.org/) or other explicit prefixed subjects (for example `renovate(scope):`, `chore(deps):`) after `last_sha` | One L2 review PR to the watch integration branch that changes `CHANGELOG.md` only; existing `## [x.y.z] - date` sections and formatting are preserved | S0 -> S1       |
| Promote undocumented releases              | Detect `releases[]` lists versions from git tags and pin/finalize subjects                                                                                                                                                           | `## [x.y.z] - date` sections in the same PR                                                                                                           | S0 -> S1       |
| Create a missing changelog                 | Detect reports `changelog_exists: false`                                                                                                                                                                                             | A Keep a Changelog template, then a populated `## [Unreleased]`                                                                                       | S0 -> S1       |
| Add commit links                           | `repository_url` is resolved (GitHub Actions `GITHUB_*` or git remote; optional `CHANGELOG_REPOSITORY_URL` override)                                                                                                                 | Each new bullet links its commit                                                                                                                      | S0 -> S1       |
| Merge the fix PR automatically             | The caller sets `level: L3` with `delivery: pr_create`                                                                                                                                                                               | GitHub auto-merge is enabled on the fix PR                                                                                                            | S1 -> S2 -> S0 |

## Out of scope

- Creating git tags (tags are inputs to detect; the loop documents them in `CHANGELOG.md` only)
- PR head mode (`detect_pr_enabled` default off) — changelog updates target integration branches only
- Commits without a clear `prefix: description` or `prefix(scope): description` shape
- Maker edits to loop state (finalize bundles state after verification)

Skill execution boundaries: `changelog` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

## State model

The loop uses the shared states `S0`–`S5` from [Loop Workflow Design Template](loop-workflow-design-template.md#scheduled-loop-states) for its one target key, `integration:main` in `.loop/state-changelog.json` on `state_branch`. It adds no loop-specific rows. The values that hold each state in this loop:

| State | Values in this loop                                                                                                                                                                                    |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| S0    | Detect returns `skip: false`: changelog-worthy commits after `last_sha`, or undocumented `releases[]`                                                                                                  |
| S1    | The fix PR carries `loop-automation`; `pending` holds `{ sha, pr, … }`; run-log `pr_created`                                                                                                           |
| S2    | `on-loop-state-promote` sets `last_sha` to `pending.sha`, removes `pending`, and sets `outcome` `pr_merged` and `consecutive_failures` `0`                                                             |
| S3    | `on-loop-state-promote` removes `pending` and sets `outcome` `pr_closed`; `last_sha` does not change and `consecutive_failures` rises by 1 (a close counts as a failure), so the next tick is S0 again |
| S4    | The PR stays open; every tick records run-log `skipped` with `skip_reason` `pending_pr`                                                                                                                |
| S5    | `consecutive_failures` is 3 or more and `last_run` is under 30 days old; each tick within 30 days of `last_run` records run-log `skipped` with `skip_reason` `circuit_breaker`                         |

A run that opens no PR (checker `REJECT`, no diff, agent error) leaves the target in S0. Only `rejected` raises `consecutive_failures`; the third one moves the target to S5. Retry limits and resets are in [State delivery](#state-delivery).

## User actions

Each row is one action a person can take on the loop's output, the loop response, and what the person sees next. The Transition column references [State model](#state-model).

| User action                                                                                  | Loop response                                                                                                                                                                                                                                                                                                                                                                                                             | Values changed                                                                                                                                                                | Result and next action                                                                                                                              | Transition     |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| Merge the changelog PR                                                                       | `on-loop-state-promote` (`pull_request_target` `closed`, job gated on `loop-automation`) promotes the pending state                                                                                                                                                                                                                                                                                                       | `last_sha` = `pending.sha`; `pending` removed; `outcome` `pr_merged`; `consecutive_failures` `0`; `open_rejections` `[]`                                                      | `CHANGELOG.md` is updated. The next Friday tick scans from the new `last_sha`                                                                       | S1 -> S2 -> S0 |
| Close the changelog PR without merging                                                       | `on-loop-state-promote` clears the pending state                                                                                                                                                                                                                                                                                                                                                                          | `pending` removed; `outcome` `pr_closed`; `last_sha` and `consecutive_failures` unchanged                                                                                     | The next tick detects the same range and opens a PR with the same entries (see [Unhandled cases](#unhandled-cases))                                 | S1 -> S3 -> S0 |
| Delete the loop branch of an open changelog PR                                               | GitHub closes the PR, and `on-loop-state-promote` clears the pending state                                                                                                                                                                                                                                                                                                                                                | As for closing the PR                                                                                                                                                         | As for closing the PR                                                                                                                               | S1 -> S3 -> S0 |
| Leave the changelog PR open                                                                  | Each tick runs detect, which finds the open `pending.pr` and skips; `record-skip` appends the run log                                                                                                                                                                                                                                                                                                                     | Run-log `skipped`, `skip_reason` `pending_pr`                                                                                                                                 | No new PR opens until the PR is merged or closed                                                                                                    | S1 -> S4       |
| Push commits to the changelog PR branch                                                      | Nothing runs                                                                                                                                                                                                                                                                                                                                                                                                              | Branch and PR head only; `pending.sha` keeps the detect SHA                                                                                                                   | Merging promotes `pending.sha`, so the person's commits land with the PR                                                                            | -              |
| Push to `main` while a run is queued or running                                              | The run keeps the detect SHA; finalize opens the PR from the agent branch based on that SHA                                                                                                                                                                                                                                                                                                                               | None beyond the run's own values                                                                                                                                              | When the push also edits `CHANGELOG.md`, GitHub shows a conflict on the PR; resolve it on the PR branch                                             | -              |
| Comment on, review, or resolve a thread on the changelog PR                                  | Nothing runs in this loop. A `@loop` mention follows the intake of [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md)                                                                                                                                                                                                                                                                                  | None in this loop                                                                                                                                                             | Edit the PR by hand, or close it                                                                                                                    | -              |
| Remove `loop-automation` from the changelog PR                                               | Nothing runs now. When the PR later closes, the `on-loop-state-promote` job `if` refuses it                                                                                                                                                                                                                                                                                                                               | Label only; `pending` stays and `last_sha` does not advance                                                                                                                   | Detect treats a closed or merged `pending.pr` as stale and scans the old range again (see [Unhandled cases](#unhandled-cases))                      | -              |
| Start `workflow_dispatch` (no inputs)                                                        | Same as a scheduled tick; it waits in the concurrency group `loop-state-main`                                                                                                                                                                                                                                                                                                                                             | As for a tick: a new PR and `pending`, or run-log `skipped` (`no_changes`, `pending_pr`, `circuit_breaker`, `budget`); only runs that start the agent count toward the budget | Read the run log when no PR opens                                                                                                                   | S0 -> S1       |
| Re-run a failed run from the Actions page                                                    | Detect runs again against the current `main` and the current state                                                                                                                                                                                                                                                                                                                                                        | As for a new tick                                                                                                                                                             | As for `workflow_dispatch`                                                                                                                          | -              |
| Reset the circuit breaker by a PR to `main` that edits `.loop/state-changelog.json`          | Nothing runs on merge; the next tick reads the new state                                                                                                                                                                                                                                                                                                                                                                  | `consecutive_failures` set to `0` (or the target key removed); `last_sha` kept or moved by hand                                                                               | The next tick detects again. Fix the cause of the rejections first                                                                                  | S5 -> S0       |
| Change `.loop/loop-budget.json` or the caller inputs by PR after a failure                   | Nothing runs on merge. The next tick uses the new values                                                                                                                                                                                                                                                                                                                                                                  | `.loop/loop-budget.json` caps (they override caller `budget_*`); caller inputs                                                                                                | Start `workflow_dispatch` to apply them now                                                                                                         | -              |
| Do nothing (no new commits)                                                                  | Each tick runs detect, which returns `skip: true`                                                                                                                                                                                                                                                                                                                                                                         | Run-log `skipped`, `skip_reason` `no_changes`                                                                                                                                 | -                                                                                                                                                   | -              |
| Commits and PRs that the loop or other loops create (state, run log, the changelog PR merge) | No event starts the workflow (only `schedule` and `workflow_dispatch`). Detect drops `chore(changelog):` and `(loop-changelog)` subjects, exactly `chore(loop): update state [skip ci]` and `chore(loop): append run log [skip ci]`, and merge commits (`--no-merges`). It keeps `chore(loop): promote state for PR #N [skip ci]` and `chore(loop): clear_pending state for PR #N [skip ci]` from `on-loop-state-promote` | None                                                                                                                                                                          | After any loop PR closes, the next range holds a promote or clear_pending commit, so detect does not skip (see [Unhandled cases](#unhandled-cases)) | -              |

Not applicable: 3, 5 — the loop uses no mention token and reads or writes no Issue.

## Unhandled cases

| Case                                                                                 | Why nothing follows                                                                                                                                                                                                                                                                                                  | Disposition |
| ------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| A person closes the changelog PR to decline it                                       | `last_sha` stays, so the next tick opens the same PR again. `on-loop-state-promote` raises `consecutive_failures` by 1 on close, so the PR comes back each week until three closes open the circuit breaker (it then stops for 30 days). To decline it for good, edit `last_sha` by hand                             | Limitation  |
| The circuit breaker stops the loop                                                   | Recovers on its own: once `last_run` is older than 30 days, detect lets one run through (`admission_circuit_breaker_open` in `admission.sh`); a `rejected` result reopens the breaker for another 30 days, any other result closes it. No notification: the trip shows only as run-log `skipped` (`circuit_breaker`) | Limitation  |
| A person removes `loop-automation` from the changelog PR                             | `on-loop-state-promote` skips the PR, so it does not promote `pending`. Detect treats a MERGED `pending.pr` as promoted for the run (`last_sha` becomes `pending.sha`, in memory only), so the merged range is not scanned again. A PR closed without merge leaves `pending` stale and the range is scanned again    | Limitation  |
| A person documents the commits by hand and merges that change instead of the loop PR | Only a loop PR merge moves `last_sha`. The next run finds nothing to add, and `agent_unchanged_verdict: REJECT` records `rejected`, so work that is already done counts toward the breaker                                                                                                                           | Follow-up   |
| A person creates a tag after the run                                                 | The tag is read on the next tick through `releases[]`                                                                                                                                                                                                                                                                | Accepted    |
| A person pushes to `main` during a run and both change `CHANGELOG.md`                | The PR shows a conflict that the person resolves; the loop does not rebase                                                                                                                                                                                                                                           | Accepted    |
| A person comments on or reviews the changelog PR                                     | The loop reads no PR comments; the person edits the PR or closes it                                                                                                                                                                                                                                                  | Accepted    |

## Failure and recovery

| Failure kind                                 | How it is recorded                                                                                                                           | Who acts   | What they do                                                                             | How the loop resumes                                                                                            |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Detect script fails                          | The `detect` job fails; no state write and no run-log row                                                                                    | Maintainer | Fix the script or the environment                                                        | The next tick retries from the same `last_sha`                                                                  |
| Checker `REJECT`, or the maker makes no diff | Run-log `rejected`; state `outcome` `rejected`, `last_reject_reason`, `consecutive_failures` + 1; `last_sha` unchanged; agent branch deleted | Maintainer | Read the reason; adjust `agent_maker_instructions` or `agent_checker_instructions` by PR | The next tick retries the same range; the third `rejected` in a row moves to S5                                 |
| Agent or push error                          | Run-log `error`; `consecutive_failures` unchanged                                                                                            | Maintainer | Fix the cause                                                                            | The next tick or `workflow_dispatch` retries                                                                    |
| Circuit breaker open                         | Run-log `skipped`, `skip_reason` `circuit_breaker` on every tick until 30 days after `last_run`                                              | Maintainer | Fix the cause, then reset `consecutive_failures` in `.loop/state-changelog.json` by PR   | The next tick after the merge (S5 -> S0)                                                                        |
| Daily budget used up                         | Run-log `skipped`, `skip_reason` `budget`                                                                                                    | Maintainer | Wait, or raise the cap in `.loop/loop-budget.json` by PR                                 | The next tick or `workflow_dispatch`                                                                            |
| State promote fails after a merge            | The `on-loop-state-promote` run fails; `pending` stays with a merged `pending.pr`                                                            | Maintainer | Re-run the failed `on-loop-state-promote` run                                            | Detect treats the stale `pending` as not blocking, but scans from the old `last_sha` until the promote succeeds |

## Caller inputs

Keys are passed in `on-loop-changelog.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_checker_instructions`, `agent_maker_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

Schedule: **`0 10 * * 5`** (Friday 10:00 UTC, weekly), plus `workflow_dispatch` with no inputs.

| Input / JSON key             | Description                                                                                                                                                                                                               | Dogfood value                                                  |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `agent_maker_max_turns`      | Max maker agent turns per loop attempt (one Agent→Verify cycle).                                                                                                                                                          | `100`                                                          |
| `agent_maker_model`          | Maker model ID. Cursor: `agent --list-models`.                                                                                                                                                                            | `claude-sonnet-5`                                              |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                              | `medium`                                                       |
| `agent_loop_max_attempts`    | Max Agent→Verify retry cycles before finalize records failure.                                                                                                                                                            | `3`                                                            |
| `agent_checker_instructions` | Checker rubric: Unreleased mapping, detect `releases[]` promotion, no hallucinated versions.                                                                                                                              | Inline in caller workflow                                      |
| `agent_checker_max_turns`    | Max checker agent turns per verification.                                                                                                                                                                                 | `100`                                                          |
| `agent_checker_model`        | Checker model ID. Cursor: `agent --list-models`.                                                                                                                                                                          | `claude-opus-5`                                                |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                            | `medium`                                                       |
| `agent_edit_allowlist`       | Comma-separated globs the maker may modify. Enforced in `loop-execute`.                                                                                                                                                   | `CHANGELOG.md`                                                 |
| `detect_branch_match`        | Comma-separated branch patterns to watch for changelog drift.                                                                                                                                                             | `main`                                                         |
| `state_branch`               | Branch for run-log/budget persistence and state **read** baseline.                                                                                                                                                        | `main`                                                         |
| `budget_max_runs_per_day`    | Daily run cap keyed by `loop_name`. Caller input; `.loop/loop-budget.json` overrides when present. Exceeded → `skip_reason=budget`.                                                                                       | `1` (caller); effective `5` via `.loop/loop-budget.json`       |
| `budget_max_tokens_per_day`  | Daily aggregated token cap across loops.                                                                                                                                                                                  | `1000000`                                                      |
| `detect_script`              | Domain detect script path. Invoked once per scan context by `loop-detect`.                                                                                                                                                | `.agents/skills/changelog/scripts/detect_changelog_commits.sh` |
| `agent_engine`               | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                                                                                     | `claude`                                                       |
| `agent_checker_path_pattern` | Extended regex to infer file paths from checker text for allowlist checks.                                                                                                                                                | `CHANGELOG\.md`                                                |
| `level`                      | Autonomy: `L2` human merge on bot fix PR; `L3` GitHub auto-merge on bot fix PR.                                                                                                                                           | `L2`                                                           |
| `loop_name`                  | Loop identifier; state file `.loop/state-changelog.json`. Align workflow name `on-loop-<loop_name>.yaml`.                                                                                                                 | `changelog`                                                    |
| `detect_max_targets`         | Max targets per cron tick after priority filters.                                                                                                                                                                         | `3`                                                            |
| `agent_unchanged_verdict`    | `APPROVE` or `REJECT` when maker produces no file diff.                                                                                                                                                                   | `REJECT`                                                       |
| `pr_body`                    | Optional static prefix (dogfood: `""`). `loop-finalize` composes agent Overview/Summary + mechanical sections. See [Loop PR Body Readable Design](../../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md). | `""`                                                           |
| `pr_title`                   | PR title when `delivery` is `pr_create`.                                                                                                                                                                                  | `chore(changelog): update CHANGELOG.md (loop-changelog)`       |
| `agent_maker_instructions`   | Domain instructions appended to maker prompt by `loop-detect`.                                                                                                                                                            | Inline in caller workflow                                      |
| `detect_pr_enabled`          | Enumerate open PR heads. Changelog uses integration branches only.                                                                                                                                                        | `false`                                                        |
| `agent_maker_skill_name`     | Skill package to invoke. Must match `.agents/skills/changelog/`.                                                                                                                                                          | `changelog`                                                    |
| `agent_edit_target`          | Agent artifact type at L2/L3.                                                                                                                                                                                             | `fix`                                                          |
| `agent_report_check`         | Deterministic check of the maker report before the checker (`commits`: `### Changes` lists commits).                                                                                                                      | `commits`                                                      |
| `delivery`                   | Platform delivery after APPROVE.                                                                                                                                                                                          | `pr_create`                                                    |

### Domain detect environment (`detect_env_json`)

```yaml
detect_env_json: >-
  {"CHANGELOG_FILE":"CHANGELOG.md","CHANGELOG_MERGE_COMMITS":"false"}
```

| JSON key                  | Description                                                      | Dogfood value  |
| ------------------------- | ---------------------------------------------------------------- | -------------- |
| `CHANGELOG_FILE`          | Target changelog path                                            | `CHANGELOG.md` |
| `CHANGELOG_MAX_COMMITS`   | Max commits for `--scope all` (local debugging)                  | `100`          |
| `CHANGELOG_MERGE_COMMITS` | `"true"` includes merge commits; `"false"` applies `--no-merges` | `"false"`      |

Platform handler: `on-loop-state-promote.yaml` (`pull_request_target` `closed`) promotes `pending` → `last_sha` on merge.

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_changelog_commits.sh` with `targets["integration:<branch>"].last_sha`.

Detect script outputs **facts** (not formatted changelog prose):

| Field              | Role                                                                                                           |
| ------------------ | -------------------------------------------------------------------------------------------------------------- |
| `changelog_file`   | Target path (default `CHANGELOG.md`)                                                                           |
| `changelog_exists` | Whether the changelog file already exists on the scanned branch                                                |
| `commit_range`     | Active git range label                                                                                         |
| `commits`          | Changelog-worthy commits (`sha`, `type`, `subject`, …)                                                         |
| `releases`         | Undocumented versions from tags and pin/finalize subjects (`version`, `tag`, `tag_sha`, `date`, `commit_shas`) |
| `compare_url`      | Optional GitHub compare URL for `commit_range` (empty when unknown)                                            |
| `repository`       | `owner/repo` when resolved                                                                                     |
| `repository_url`   | Web base for commit links (`GITHUB_*`, git remote, or override)                                                |
| `skip`             | `true` when no unreleased commits and no undocumented releases                                                 |

**Skill** (`changelog`) creates the Keep a Changelog template when `changelog_exists` is false, groups commits under `## [Unreleased]`, and promotes `releases[]` into versioned sections.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `delivery` = `pr_create`

### Stable filters (detect only)

- Explicit `prefix: description` or `prefix(scope): description` subjects
- Conventional types (`feat:`, `fix:`, `chore:`, …) and tool prefixes (`renovate`, `dependabot`, …)
- Skip loop maintenance commits (`chore(changelog):`, subjects containing `(loop-changelog)`)
- Release detection: semver git tags (`v*.*.*`) and pin/finalize/align subjects in range not yet in `CHANGELOG.md`
- Optional `--no-merges` when `CHANGELOG_MERGE_COMMITS` is `false`
- `--scope all` is bounded by `CHANGELOG_MAX_COMMITS` (default 100) for local debugging only
- Circuit breaker on `targets[key].consecutive_failures`
- Budget / workflow `concurrency` (platform)

### State fields (per target key)

| Field                  | Role                                                                   |
| ---------------------- | ---------------------------------------------------------------------- |
| `last_sha`             | Scan cursor; advances when fix PR merges (`on-loop-state-promote`)     |
| `pending`              | Written at finalize (`pr_created`); holds `{ sha, pr, … }` until merge |
| `outcome`              | `pr_created`, `rejected`, `unchanged`, …                               |
| `consecutive_failures` | Circuit breaker                                                        |

## Execute

- Worktree from `target.from` on integration branch
- Checker diff baseline: `to.branch`
- `verifier_context`: detect commit and release summary
- `Set Acting On` during execute (coordination only; no state PR)

## Finalize

PR body is composed by `loop-finalize` from agent `## Overview` / `## Summary` (skill-owned) plus mechanical sections. Dogfood sets `pr_body: ""`. See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

Always `delivery: pr_create` to `to.branch` at L2.

1. Optional domain persistence (none for changelog)
2. Create PR (`CHANGELOG.md` only)
3. **Write state** to `state_branch` with `pending` (merge-gated; `last_sha` unchanged)
4. Append run log to `state_branch`

On `REJECT`, state writes failure metadata to `state_branch` without advancing `last_sha`.

On fix PR merge, `on-loop-state-promote` promotes `pending.sha` → `last_sha`.

No `finalize_script`.

## State delivery

See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) for platform rules.

Persistence: `state-changelog.json` on `state_branch` (merge-gated `pending` + `on-loop-state-promote`, as described in [Finalize](#finalize)). The run log is `.loop/loop-run-log.md` on the same branch.

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

Changelog runs are doc-metadata only (`CHANGELOG.md`). Coordinate with `docs-updater` via workflow `concurrency` when both target `integration:main`.

## Implementation Checklist

Shared platform: [Multi-Branch — Shared platform checklist](../multi-branch-loops-design.md#shared-platform-checklist-all-loops).

### Loop-specific

- [x] `changelog/scripts/detect_changelog_commits.sh` (facts output)
- [x] `on-loop-changelog.yaml` dogfood caller via `ci-loop-caller`
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.commits` branch)
- [x] `detect_changelog_commits.sh` emits `releases[]` for tag-scoped entries
- [x] Dogfood action pins @ v1.8.47

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
