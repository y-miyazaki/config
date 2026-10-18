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

### Supported use cases

- Weekly scheduled run on `main` that adds tests for exactly one target (`max_targets_per_schedule: 1`)
- Manual run through `workflow_dispatch`
- Phase 1 scope for this repository: shell scripts with paired Bats suites under `test/bats/`. The skill itself has no language adapters and discovers the stack from the repository, but the caller instructions and the Checker rubric restrict this loop to Bats

### Out of scope

- Running the tests inside the loop job (see [Verification and CI failure handling](#verification-and-ci-failure-handling))
- Editing or deleting existing tests, or editing production code (a suspected production bug goes under `### Deferred` in the PR body)
- GitHub Issue creation
- L1 log-only observation phase (**L2 from start**)
- Mutation testing and coverage-threshold enforcement
- Go tests: Go needs a CI caller that runs Go tests first; this repository has none, so Go is not enabled (`agent_checker_path_pattern` excludes `go`)

### Modes

| Mode           | Default | Behavior                                                 |
| -------------- | ------- | -------------------------------------------------------- |
| `integration`  | on      | Detect on watch branch → test PR to same branch          |
| `pull_request` | off     | Not supported for this loop (`detect_pr_enabled: false`) |

### Observation trigger

`test-gap` has no failure sensor. Its trigger is state-based: schedule, targets absent from the [ledger](#ledger), and git churn. See [Selection Criteria](../loop-engineering-design.md#selection-criteria) item 5.

## Caller inputs

Keys are passed in `on-loop-test-gap.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_checker_instructions`, `agent_maker_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

Schedule: **`0 10 * * 1`**, `timezone: Etc/UTC` (Monday 10:00 UTC, weekly), plus `workflow_dispatch`. The caller uses the shared `loop-state-main` concurrency group with `queue: max`.

| Input / JSON key             | Description                                                                                                                                            | Dogfood value                                               |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------- |
| `finalize_commit_paths`      | Extra paths `loop-finalize` commits with the state update. Carries the ledger file.                                                                    | `.loop/state-test-gap-ledger.json`                          |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it.                                                                        | `medium`                                                    |
| `agent_checker_instructions` | Checker APPROVE/REJECT rubric (static criteria only; see [Checker criteria](#checker-criteria)).                                                       | Inline in caller workflow                                   |
| `agent_checker_max_turns`    | Max checker agent turns per verification.                                                                                                              | `100`                                                       |
| `agent_checker_model`        | Checker model ID.                                                                                                                                      | `claude-opus-5`                                             |
| `agent_checker_skill_name`   | Checker skill package.                                                                                                                                 | `loop-verifier`                                             |
| `agent_loop_max_attempts`    | Max Agent→Verify retry cycles before finalize records failure.                                                                                         | `3`                                                         |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it.                                                                          | `medium`                                                    |
| `agent_maker_instructions`   | Domain instructions: Phase 1 shell/Bats only, select one target, add tests, no production edits, no claim of running the tests.                        | Inline in caller workflow                                   |
| `agent_maker_max_turns`      | Max maker agent turns per loop attempt (one Agent→Verify cycle).                                                                                       | `100`                                                       |
| `agent_maker_model`          | Maker model ID.                                                                                                                                        | `claude-sonnet-5`                                           |
| `agent_maker_skill_name`     | Skill package to invoke.                                                                                                                               | `test-gap`                                                  |
| `agent_edit_allowlist`       | Comma-separated globs the maker may modify. Tests only. The Checker rubric narrows this to `test/bats/**` (see [Checker criteria](#checker-criteria)). | `test/**`                                                   |
| `detect_branch_match`        | Comma-separated integration branch patterns to watch.                                                                                                  | `main`                                                      |
| `state_branch`               | Branch for `.loop/*` persistence, and state migration (it no longer doubles as a watch fallback).                                                      | `main`                                                      |
| `budget_max_runs_per_day`    | Daily run cap keyed by `loop_name`.                                                                                                                    | `2`                                                         |
| `budget_max_tokens_per_day`  | Daily aggregated token cap across loops.                                                                                                               | `1000000`                                                   |
| `delivery`                   | Platform delivery after APPROVE.                                                                                                                       | `pr_create`                                                 |
| `detect_env_json`            | JSON object of `TEST_GAP_*` env vars passed to the detect script. See [Domain detect environment](#domain-detect-environment-detect_env_json).         | `{}`                                                        |
| `detect_script`              | Domain detect script path.                                                                                                                             | `.agents/skills/test-gap/scripts/detect_test_gap.sh`        |
| `finalize_script`       | Script `loop-finalize` runs to update the ledger.                                                                                                      | `.agents/skills/test-gap/scripts/update_test_gap_ledger.sh` |
| `agent_engine`               | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                  | `claude`                                                    |
| `environment`                | GitHub Environment for env-scoped secrets inside the reusable workflow. Leave `default` when repository secrets suffice.                               | `default`                                                   |
| `agent_checker_path_pattern` | Extended regex to infer file paths from checker text.                                                                                                  | `test/[^[:space:],)]+\.(bats\|sh\|json\|ya?ml)`             |
| `level`                      | Autonomy level (`L1`, `L2`, `L3`). **L2 from start**.                                                                                                  | `L2`                                                        |
| `loop_name`                  | Loop identifier; state file `.loop/state-test-gap.json`.                                                                                               | `test-gap`                                                  |
| `detect_max_targets`         | Max targets per cron tick after priority filters.                                                                                                      | `1`                                                         |
| `agent_edit_allowed`         | Agent worktree edit gate.                                                                                                                              | `true`                                                      |
| `agent_unchanged_verdict`    | `APPROVE` or `REJECT` when the maker produces no file diff.                                                                                            | `REJECT`                                                    |
| `pr_body`                    | Optional static prefix. `loop-finalize` composes agent Overview/Summary + mechanical sections.                                                         | `""`                                                        |
| `detect_pr_enabled`          | Enumerate open PR heads. `test-gap` uses integration branches only.                                                                                    | `false`                                                     |
| `pr_title`                   | PR title when `delivery` is `pr_create`.                                                                                                               | `test: add missing tests (loop-test-gap)`                   |
| `agent_edit_target`          | Agent artifact when `agent_edit_allowed` is true.                                                                                                      | `fix`                                                       |

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

Per watch branch, `loop-detect` checks out the branch and invokes `detect_test_gap.sh` (`--scope all` by default; `--scope range --since <ref>` echoes `since` and `commit_range` and limits the churn log to that range).

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

## Execute

- Worktree from `target.from` on the integration branch
- Checker diff baseline: `to.branch`
- `verifier_context`: the ledger summary from detect (see [Why `verifier_context` is emitted](#why-verifier_context-is-emitted))

## Skill

The `test-gap` skill (`SKILL.md`) reads `hotspots[]`, `ledger`, and `warnings[]` from the detect JSON. The maker:

1. Discovers the stack and test layout from the repository
2. Selects exactly one target, skipping a target whose paired test file path appears in `ledger.processed[]` (a second new test file for the same target also counts) unless a new reason is stated in the PR body or an Open Rejections item from a previous run applies
3. Adds tests that assert observable behavior (return values, side effects, error paths)
4. Names the target, the reason, the command CI will run, and the expected result in the PR body, without claiming the tests were run

Language-specific guidance comes from the caller's `agent_maker_instructions` (Phase 1: shell scripts, the `shell-script-validation` skill, and Bats pairing), not from the skill, which keeps the skill portable. A caller may restrict the stack and the caller instructions win over the skill's stack discovery. In interactive mode there is no `Allowed paths`; the skill uses the repository's existing test directories.

## Checker criteria

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

**Open item (platform follow-up, needs a ruling and a pin bump):** either add `test-gap` to `agent_report_skill_requires_format_check` in `.github/actions/loop-execute/lib/validate_agent_report.sh`, or pass the maker summary to the Checker. Until then the PR body is not machine-checked.

**Limits:** "Breaking the implementation makes the test fail" (mutation check) and "coverage increases" cannot be confirmed by the Checker. Protection against tests that pass but verify nothing is therefore weaker than execution-based verification. CI confirms green status and human review covers depth.

## Verification and CI failure handling

The loop job installs no test runtime (the execute job sets up Node, uv, and the engine CLI), and the Checker runs before push, so no CI result exists at verification time. The loop therefore **does not validate the tests**.

- CI runs on the test PR and is the validation path
- A failing CI on a `test-gap` PR is handled by a human (fix or close). Three consecutive failures, including a human closing a failing PR (`pr_closed`), trip the circuit breaker; see [Operations and status](#operations-and-status)
- `ci-sweeper` is deliberately **not** configured to pick up these PRs: `detect_pr_bot_allowlist` in `on-loop-ci-sweeper.yaml` is unchanged. Every loop PR is authored by the same GitHub App bot, so adding that login would put all loop PRs, including `ci-sweeper` fix PRs, in scope and risks recursion
- Open question: measure the share of `test-gap` PRs whose CI fails, then decide whether to let `ci-sweeper` pick them up (a bot allowlist entry or a label filter) or to install a test runtime in the loop job. Neither is decided

Rationale and the compared options: [Loop `test-gap` 設計: テスト不足を埋める改善ループ](../../../superpowers/specs/2026-10-11-loop-test-gap-design.md).

## Finalize

Always `delivery: pr_create` to `to.branch` at L2, with the PR body composed by `loop-finalize` (see [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md)). The ledger file is committed through `finalize_commit_paths`.

**Merge-gated cursor:** same platform rule as all L2 `pr_create` loops. See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy).

## Operations and status

**Status / unverified in production.** The first `workflow_dispatch` run has not happened.

Confirmed by reading the code, still to observe on the first real run:

1. Whether `EXECUTE_BRANCH` resolves through `git diff` when `finalize_script` runs. The finalize checkout uses `fetch-depth: 0`, so the agent branch should be fetched; if it is not, the ledger is not updated and a warning is logged
2. Whether `loop-finalize` includes `.loop/state-test-gap-ledger.json` from `finalize_commit_paths` in the state commit. `write_state.sh` stages `finalize_commit_paths`; the committed result is still to be observed

Unverified and tracked in the spec's open questions:

3. Whether the PR is created with the GitHub App token and therefore starts CI workflows such as `on-ci-push-shell-script`
4. Whether the Checker rubric rejects meaningless tests in practice (Checker Theater, measured on real runs)

Phase 1 targets shell scripts with Bats suites only. Go support needs a CI caller that runs Go tests; this repository has none today.

### Failure handling and the circuit breaker

- A Maker that finds nothing to test produces no diff, which yields `rejected` (`agent_unchanged_verdict: REJECT`)
- Three consecutive failures (`rejected` or `pr_closed`, so a human closing a failing PR counts) trip the circuit breaker, and the schedule stops selecting the target
- To resume, reset `targets["integration:main"].consecutive_failures` (the key is `targets[<target key>]`) to `0` in `.loop/state-test-gap.json` (state file `.loop/state-<loop_name>.json`)

## Implementation Checklist

Shared platform: [Multi-Branch — Shared platform checklist](../multi-branch-loops-design.md#shared-platform-checklist-all-loops).

### Loop-specific

- [x] `test-gap/scripts/detect_test_gap.sh` (facts output, `verifier_context`)
- [x] `test-gap/scripts/update_test_gap_ledger.sh` (`finalize_script`)
- [x] `on-loop-test-gap.yaml` dogfood caller via `ci-loop-caller`
- [ ] First `workflow_dispatch` run and the checks in [Operations and status](#operations-and-status)
- [ ] Platform follow-up: PR-body check for the Checker (see [Checker criteria](#checker-criteria))

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Loop-Capable Skills](../loop-capable-skills.md)
- [Report Tech Debt Workflow Design](loop-tech-debt-workflow-design.md)
- [CI Sweeper Workflow Design](loop-ci-sweeper-workflow-design.md)
- [Specification](../../../reference/specification.md)
