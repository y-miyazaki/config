# CI Sweeper Workflow Design

Workflow and domain design for the `loop-ci-sweeper` (`ci-sweeper`) loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-ci-sweeper.yaml` · skill `loop-ci-sweeper` · `scripts/detect_ci_failures.sh` · `scripts/update_run_ledger.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Automated minimal repair when CI fails on integration branches and/or open PR heads. One engine; no separate `loop-pr-ci-healer` package.

### Supported use cases

- Integration branch CI failure → open a fix PR **to** the watch branch (`main`, `develop`, `release/*`, …)
- Open PR head CI failure → push a minimal fix **to the PR branch** (`push_head`)
- Classify failures as Fix / Watch / Escalate; apply small lint, workflow, shell, or doc edits when actionable
- Dedupe by `workflow_run_id` ledger; skip infra/flake/env failures as `outcome: watch`
- Cron polling (default); optional `workflow_run` after [ops checklist](#workflow_run-operational-checklist)

### Out of scope

- Infra outages, secrets, runner capacity, or persistent flakes (Watch — no code edit)
- Large refactors (>5 files), auth/payment/credential paths
- Merging PRs or pushing directly to the default branch (L2 integration uses `open_pr` only)
- Re-running CI in the verifier (semantic fit against log excerpt only)
- Manual interactive debugging as a substitute for the loop
- Separate `loop-pr-ci-healer` package

Skill execution boundaries: `loop-ci-sweeper` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

### Modes

| Mode           | User expectation                               |
| -------------- | ---------------------------------------------- |
| `integration`  | Fix PR **to** `main` / `develop` / `release/*` |
| `pull_request` | Push fix **to PR head**                        |

## Caller inputs

Keys are passed in `on-loop-ci-sweeper.yaml` via `with:` on `ci-loop-caller-full-github.yaml` (alphabetically ordered). Multiline values (`agent_verifier_criteria`, `pr_body`, `prompt_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Legacy env name mapping: [Loop Caller `env` Reference](loop-caller-env-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Input / JSON key                                            | Description                                                                                                                                           | Dogfood value                                                                                            |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `additional_commit_paths`                                   | Extra paths included in finalize commit (ledger file).                                                                                                | `.loop/state-ci-sweeper-run-ledger.json`                                                                 |
| `agent_implementer_max_turns`                               | Max implementer agent turns per loop attempt (one Agent→Verify cycle).                                                                                | `8`                                                                                                      |
| `agent_implementer_model`                                   | Implementer model ID. Cursor: `agent --list-models`.                                                                                                  | `grok-4.5-medium`                                                                                        |
| `agent_loop_max_attempts`                                   | Max Agent→Verify retry cycles before finalize records failure.                                                                                        | `3`                                                                                                      |
| `agent_verifier_criteria`                                   | Verifier APPROVE/REJECT rubric. Requires fix addresses logged CI failure; minimal diff; allowlist/denylist respected.                                 | Inline in caller workflow                                                                                |
| `agent_verifier_max_turns`                                  | Max verifier agent turns per verification.                                                                                                            | `3`                                                                                                      |
| `agent_verifier_model`                                      | Verifier model ID. Cursor: `agent --list-models`.                                                                                                     | `composer-2.5`                                                                                           |
| `allowlist`                                                 | Comma-separated globs the implementer may modify.                                                                                                     | `.github/**,.apm/packages/**,scripts/**,apm.yml,mise.toml,renovate/**,docs/**/*.md,README.md,mkdocs.yml` |
| `branch_match`                                              | Comma-separated integration branch patterns to poll for failed CI.                                                                                    | `main`                                                                                                   |
| `branch_state`                                              | Branch for `.loop/*` persistence, state migration, and watch fallback.                                                                                | `main`                                                                                                   |
| `budget_max_runs_per_day`                                   | Daily run cap keyed by `loop_name`.                                                                                                                   | `5`                                                                                                      |
| `budget_max_tokens_per_day`                                 | Daily aggregated token cap across loops.                                                                                                              | `1000000`                                                                                                |
| `denylist`                                                  | Comma-separated globs the implementer must never modify (credentials, infra, migrations).                                                             | `**/.env,**/credentials*,**/secrets*,**/migration/*.sql,**/infrastructure/**`                            |
| `detect_domain_env_json` → `CI_SWEEPER_LEDGER_FILE`         | JSON ledger path for `workflow_run_id` dedupe.                                                                                                        | `.loop/state-ci-sweeper-run-ledger.json`                                                                 |
| `detect_domain_env_json` → `CI_SWEEPER_REJECT_MAX_RETRIES`  | Max re-attempts per run ID when policy is `limited`.                                                                                                  | `3`                                                                                                      |
| `detect_domain_env_json` → `CI_SWEEPER_REJECT_RETRY_POLICY` | `block`, `retry`, or `limited` — ledger policy for prior `rejected` entries.                                                                          | `block`                                                                                                  |
| Reusable workflow (`uses:`)                                 | `ci-loop-caller-full-github.yaml` — detect job requires `actions: read` and `pull-requests: read`; caller `permissions` must include `actions: read`. | `./.github/workflows/ci-loop-caller-full-github.yaml`                                                    |
| `detect_script`                                             | Domain detect script path. Uses `gh run list` per watch branch / PR head.                                                                             | `.agents/skills/loop-ci-sweeper/scripts/detect_ci_failures.sh`                                           |
| `domain_persistence_script`                                 | Bash script for `loop-finalize` domain persistence (run ledger updates).                                                                              | `.agents/skills/loop-ci-sweeper/scripts/update_run_ledger.sh`                                            |
| `engine`                                                    | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                 | `cursor`                                                                                                 |
| `finalize_integration`                                      | Finalize for integration targets: `open_pr` (fix PR to watch branch) or `push` (L3).                                                                  | `open_pr`                                                                                                |
| `finalize_pull_request`                                     | Finalize for pull_request targets. Currently `push_head` only.                                                                                        | `push_head`                                                                                              |
| `infer_files_pattern`                                       | Extended regex to infer file paths from verifier text.                                                                                                | See caller workflow                                                                                      |
| `branch_match`                                              | Comma-separated integration branch patterns to poll for failed CI.                                                                                    | `main`                                                                                                   |
| `branch_state`                                              | Branch for `.loop/*` persistence, state migration, and watch fallback.                                                                                | `main`                                                                                                   |
| `level`                                                     | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR.                                                                                                | `L2`                                                                                                     |
| `loop_name`                                                 | Loop identifier; state file `.loop/state-ci-sweeper.json`.                                                                                            | `ci-sweeper`                                                                                             |
| `max_targets_per_schedule`                                  | Max targets per cron tick after priority/`acting_on` filters.                                                                                         | `3`                                                                                                      |
| `no_changes_verdict`                                        | `APPROVE` or `REJECT` when implementer produces no file diff on actionable CI failure.                                                                | `REJECT`                                                                                                 |
| `pr_body`                                                   | Static markdown prefix for finalize PR body.                                                                                                          | Inline in caller workflow                                                                                |
| `pr_exclude`                                                | PR exclusion tokens: `fork`, `draft`, `label:<name>`, `wip_title`.                                                                                    | `fork,draft,label:no-loop`                                                                               |
| `pr_include_bots`                                           | Comma-separated bot logins to include when scanning PRs. Empty = exclude all bots.                                                                    | `""`                                                                                                     |
| `pr_title`                                                  | PR title when finalize strategy is `open_pr`.                                                                                                         | `fix(ci): automated CI repair (loop-ci-sweeper)`                                                         |
| `prompt_instructions`                                       | Domain instructions: classify Watch vs Fix; minimal diff; run validation skills.                                                                      | Inline in caller workflow                                                                                |
| `pull_requests`                                             | Enumerate open PR heads for failed CI repair (`push_head`).                                                                                           | `true`                                                                                                   |
| `skill_name`                                                | Skill package to invoke.                                                                                                                              | `loop-ci-sweeper`                                                                                        |

**Event keys** (embed in `detect_domain_env_json` when `workflow_run` trigger is enabled — currently commented out in caller workflow):

| JSON key                     | Description                                                       |
| ---------------------------- | ----------------------------------------------------------------- |
| `CI_SWEEPER_HEAD_BRANCH`     | Failed workflow run head branch from `github.event.workflow_run`. |
| `CI_SWEEPER_HEAD_SHA`        | Failed workflow run head SHA.                                     |
| `CI_SWEEPER_WORKFLOW_RUN_ID` | Failed workflow run ID for ledger dedupe.                         |
| `CI_SWEEPER_WORKFLOW_NAME`   | Failed workflow display name.                                     |
| `CI_SWEEPER_RUN_URL`         | HTML URL of the failed workflow run (verifier context).           |

## Detect

### Stable mechanical filters (detect script + platform)

Detect applies **only** stable gates — not semantic failure classification:

| Filter                                  | Layer                  |
| --------------------------------------- | ---------------------- |
| Ledger dedupe (`workflow_run_id`)       | detect script          |
| `workflow_run` caller `workflows:` list | caller trigger         |
| Event run branch vs scan branch         | detect script          |
| PR exclusion (fork, draft, bot, label)  | `loop-detect` + script |
| `acting_on` / `peer_active`             | `loop-detect`          |
| Budget / circuit breaker                | `loop-detect`          |

`failure_type` from grep heuristics is an optional **hint** for the Skill — not a detect gate. **Skill** classifies Fix / Watch / Escalate.

### Integration mode

Per watch branch, `loop-detect` sets context; script uses `gh run list --branch <watch_branch> --status failure`.

- Range filter via `targets["integration:<branch>"].last_sha`
- **Dedupe:** `state-ci-sweeper-run-ledger.json` keyed by `workflow_run_id`

### Pull request mode

- Failed runs where `head_branch` matches open PR
- Emit `pr_number`, `base.branch` in `target_json`
- Apply [PR exclusion rules](#pr-exclusion-rules)

### Detect truth source

| Mode         | Primary cursor             | Secondary                                 |
| ------------ | -------------------------- | ----------------------------------------- |
| integration  | `workflow_run_id` + ledger | `last_sha` in state (advance on finalize) |
| pull_request | `workflow_run_id` + ledger | `head_ref` per PR in state                |

**Rule:** Do not rely on `last_sha` alone to skip a still-failing workflow run. Ledger outcome `pr-created` or `watch` blocks re-processing same run ID under `block` policy.

### `no_changes_verdict: REJECT`

When the Skill classifies **Fix** but the implementer produces no changes → REJECT → `outcome: rejected`.

When the Skill classifies **Watch** (infra/flake/env) with no code edit → `outcome: watch` (not REJECT). See [Outcome enum](../../reference/specification.md#outcome-enum).

## PR Exclusion Rules

| Rule          | Default     | Token                           |
| ------------- | ----------- | ------------------------------- |
| Fork PR       | Exclude     | `fork`                          |
| Draft         | Exclude     | `draft`                         |
| Label opt-out | Exclude     | `label:<name>`                  |
| Bots          | **Exclude** | use `pr_include_bots` to opt in |
| WIP title     | Optional    | `wip_title`                     |

## Execute

- Worktree: `target.from` (see [platform table](../multi-branch-loops-design.md#execute-and-verifier-platform))
- **`verifier_context`:** failed job log excerpt from detect `result` — **always** wired (integration and pull_request)

```yaml
with:
  target_json: ${{ toJson(matrix.target.target_json) }}
  verifier_context: ${{ matrix.target.verifier_context }}
```

### Verifier criteria (caller-owned)

CI sweeper criteria require the fix to address the **logged failure** (semantic fit against `verifier_context`). This does not violate the generic rule “verifier does not re-run CI” — see [Loop Engineering — Verify](../loop-engineering-design.md#verify).

## Finalize

| Mode         | L2                                | L3                                      |
| ------------ | --------------------------------- | --------------------------------------- |
| integration  | `open_pr` → fix PR to `to.branch` | `push` → Finalize pushes to `to.branch` |
| pull_request | `push_head`                       | `push_head`                             |

| Persistence | Mechanism                                                 |
| ----------- | --------------------------------------------------------- |
| State       | `state-ci-sweeper.json` (`targets` map) on `branch_state` |
| Run ledger  | `domain_persistence_script` → `update_run_ledger.sh`      |
| Run log     | `loop-run-log` in `loop-finalize` chain                   |

Dogfood: **`DEFAULT_LEVEL=L2`** until [L3 promotion gate](../loop-engineering-design.md).

## Implementation Checklist

- [ ] Single detect path via `loop-detect` (no caller re-run)
- [ ] `branch_match` / `pull_requests`
- [ ] State `targets` map; flat `last_sha` removed
- [ ] `target_matrix` + matrix execute/finalize
- [ ] `verifier_context` always on execute
- [ ] Ledger via `domain_persistence_script` in `loop-finalize`
- [ ] `outcome: watch` for Skill Watch classification

## workflow_run Operational Checklist

Before uncommenting `workflow_run` in `on-loop-ci-sweeper.yaml`:

- [ ] zizmor / security review complete
- [ ] `workflow_run.workflows` lists only CI workflows to repair (not `on-loop-*` / `ci-loop-*` callers)
- [ ] Concurrency prevents overlapping runs on same `target.key`
- [ ] Event path sets `CI_SWEEPER_*` env on detect job
- [ ] Failed workflow is not the sweeper’s own finalize push (`[skip ci]` on ledger commits)
- [ ] Fork / draft / bot exclusions active
- [ ] 1 failure event → 1 target (no unbounded matrix from one event)

## dependency-update (roadmap)

`pull_requests: true` + `pr_include_bots: renovate[bot]`. Same workflow; no new package.

## Cross-Loop Note

CI failure on `integration:main` takes priority over `loop-docs-triage` and `loop-changelog` via [acting_on](../multi-branch-loops-design.md#cross-loop-coordination-acting_on). Limit recursion with `workflow_run.workflows` (caller allowlist), run ledger (`workflow_run_id`), and daily budget — not workflow-name exclude lists in detect.

`workflow_dispatch` (no event run ID) uses `gh run list` on the watch branch (`SCAN_BRANCH_RUN_LIMIT`, default 100), then ledger and `since` range filters. Skill classifies infra/env/flake failures as Watch.

## References

- [cobusgreyling ci-sweeper pattern](https://github.com/cobusgreyling/loop-engineering/blob/main/patterns/ci-sweeper.md)
- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../reference/specification.md)
