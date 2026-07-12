# CI Sweeper Workflow Design

Workflow and domain design for the `loop-ci-sweeper` (`ci-sweeper`) loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-ci-sweeper.yaml` · skill `loop-ci-sweeper` · `scripts/detect_ci_failures.sh` · `scripts/update_run_ledger.sh`

Shared caller keys (`AGENT_*`, `DEFAULT_*`, `LOOP_*`, `SKILL_NAME`): [Loop Caller `env` Reference](loop-caller-env-reference.md).

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

## Environment variables

All keys in workflow `env:` (alphabetically ordered). Multiline values (`AGENT_VERIFIER_CRITERIA`, `LOOP_PR_BODY`, `LOOP_PROMPT_INSTRUCTIONS`) are defined inline in `on-loop-ci-sweeper.yaml`.

Shared semantics for keys used across loops: [Loop Caller `env` Reference](loop-caller-env-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Variable                         | Description                                                                                                           | Dogfood value                                                                                            |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `AGENT_IMPLEMENTER_MAX_TURNS`    | Max implementer agent turns per loop attempt (one Agent→Verify cycle).                                                | `"8"`                                                                                                    |
| `AGENT_IMPLEMENTER_MODEL`        | Implementer model ID. Cursor: `agent --list-models`.                                                                  | `grok-4.5-medium`                                                                                        |
| `AGENT_LOOP_MAX_ATTEMPTS`        | Max Agent→Verify retry cycles before finalize records failure.                                                        | `"3"`                                                                                                    |
| `AGENT_VERIFIER_CRITERIA`        | Verifier APPROVE/REJECT rubric. Requires fix addresses logged CI failure; minimal diff; allowlist/denylist respected. | Inline in workflow YAML                                                                                  |
| `AGENT_VERIFIER_MAX_TURNS`       | Max verifier agent turns per verification.                                                                            | `"3"`                                                                                                    |
| `AGENT_VERIFIER_MODEL`           | Verifier model ID. Cursor: `agent --list-models`.                                                                     | `composer-2.5`                                                                                           |
| `CI_SWEEPER_EXCLUDED_WORKFLOWS`  | Comma-separated workflow **names** to ignore (prevents loop self-trigger / recursion).                                | `on-loop-changelog,on-loop-ci-sweeper,on-loop-docs-triage,ci-loop-agent`                                 |
| `CI_SWEEPER_INCLUDED_WORKFLOWS`  | Workflow name allowlist. Empty = all non-excluded workflows.                                                          | `""`                                                                                                     |
| `CI_SWEEPER_LEDGER_FILE`         | JSON ledger path for `workflow_run_id` dedupe. Updated by `update_run_ledger.sh` in finalize.                         | `.loop/ci-sweeper-run-ledger.json`                                                                       |
| `CI_SWEEPER_REJECT_MAX_RETRIES`  | Max re-attempts per run ID when `CI_SWEEPER_REJECT_RETRY_POLICY=limited`.                                             | `"3"`                                                                                                    |
| `CI_SWEEPER_REJECT_RETRY_POLICY` | `block`, `retry`, or `limited` — ledger policy for prior `rejected` entries for the same run.                         | `block`                                                                                                  |
| `DEFAULT_BASE_BRANCH`            | Default branch for state migration fallback.                                                                          | `main`                                                                                                   |
| `DEFAULT_ENGINE`                 | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                 | `cursor`                                                                                                 |
| `DEFAULT_LEVEL`                  | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR.                                                                | `L2`                                                                                                     |
| `DOMAIN_PERSISTENCE_SCRIPT`      | Bash script for `loop-finalize` `domain_persistence_script` (run ledger updates).                                     | `.agents/skills/loop-ci-sweeper/scripts/update_run_ledger.sh`                                            |
| `LOOP_ALLOWLIST`                 | Comma-separated globs the implementer may modify.                                                                     | `.github/**,.apm/packages/**,scripts/**,apm.yml,mise.toml,renovate/**,docs/**/*.md,README.md,mkdocs.yml` |
| `LOOP_BUDGET_MAX_RUNS_PER_DAY`   | Daily run cap keyed by `LOOP_NAME`.                                                                                   | `"5"`                                                                                                    |
| `LOOP_BUDGET_MAX_TOKENS_PER_DAY` | Daily aggregated token cap across loops.                                                                              | `"1000000"`                                                                                              |
| `LOOP_DENYLIST`                  | Comma-separated globs the implementer must never modify (credentials, infra, migrations).                             | `**/.env,**/credentials*,**/secrets*,**/migration/*.sql,**/infrastructure/**`                            |
| `LOOP_DETECT_SCRIPT`             | Domain detect script path. Uses `gh run list` per watch branch / PR head.                                             | `.agents/skills/loop-ci-sweeper/scripts/detect_ci_failures.sh`                                           |
| `LOOP_FINALIZE_INTEGRATION`      | Finalize for integration targets: `open_pr` (fix PR to watch branch) or `push` (L3).                                  | `open_pr`                                                                                                |
| `LOOP_FINALIZE_PULL_REQUEST`     | Finalize for pull_request targets. Currently `push_head` only.                                                        | `push_head`                                                                                              |
| `LOOP_INFER_FILES_PATTERN`       | Extended regex to infer file paths from verifier text.                                                                | See workflow YAML                                                                                        |
| `LOOP_INTEGRATION_BRANCHES`      | Comma-separated integration branch patterns to poll for failed CI.                                                    | `main`                                                                                                   |
| `LOOP_MAX_TARGETS_PER_SCHEDULE`  | Max targets per cron tick after priority/`acting_on` filters.                                                         | `"3"`                                                                                                    |
| `LOOP_NAME`                      | Loop identifier; state file `.loop/state-ci-sweeper.json`.                                                            | `ci-sweeper`                                                                                             |
| `LOOP_NO_CHANGES_VERDICT`        | `APPROVE` or `REJECT` when implementer produces no file diff on actionable CI failure.                                | `REJECT`                                                                                                 |
| `LOOP_PR_BODY`                   | Static markdown prefix for finalize PR body.                                                                          | Inline in workflow YAML                                                                                  |
| `LOOP_PR_EXCLUDE`                | PR exclusion tokens: `fork`, `draft`, `label:<name>`, `wip_title`.                                                    | `fork,draft,label:no-loop`                                                                               |
| `LOOP_PR_INCLUDE_BOTS`           | Comma-separated bot logins to include when scanning PRs. Empty = exclude all bots.                                    | `""`                                                                                                     |
| `LOOP_PR_TITLE`                  | PR title when finalize strategy is `open_pr`.                                                                         | `fix(ci): automated CI repair (loop-ci-sweeper)`                                                         |
| `LOOP_PROMPT_INSTRUCTIONS`       | Domain instructions: classify Watch vs Fix; minimal diff; run validation skills.                                      | Inline in workflow YAML                                                                                  |
| `LOOP_PULL_REQUESTS`             | `"true"` enumerates open PR heads for failed CI repair (`push_head`).                                                 | `"true"`                                                                                                 |
| `LOOP_STATE_PUSH_BRANCH`         | Branch for `.loop/*` persistence commits.                                                                             | `main`                                                                                                   |
| `SKILL_NAME`                     | Skill package to invoke.                                                                                              | `loop-ci-sweeper`                                                                                        |

**Event vars** (inject on detect job when `workflow_run` trigger is enabled — currently commented out in workflow YAML):

| Variable                     | Description                                                       |
| ---------------------------- | ----------------------------------------------------------------- |
| `CI_SWEEPER_HEAD_BRANCH`     | Failed workflow run head branch from `github.event.workflow_run`. |
| `CI_SWEEPER_HEAD_SHA`        | Failed workflow run head SHA.                                     |
| `CI_SWEEPER_WORKFLOW_RUN_ID` | Failed workflow run ID for ledger dedupe.                         |
| `CI_SWEEPER_WORKFLOW_NAME`   | Failed workflow display name.                                     |
| `CI_SWEEPER_RUN_URL`         | HTML URL of the failed workflow run (verifier context).           |

## Detect

### Stable mechanical filters (detect script + platform)

Detect applies **only** stable gates — not semantic failure classification:

| Filter                                 | Layer                  |
| -------------------------------------- | ---------------------- |
| Ledger dedupe (`workflow_run_id`)      | detect script          |
| Workflow include/exclude lists         | detect script          |
| PR exclusion (fork, draft, bot, label) | `loop-detect` + script |
| `acting_on` / `peer_active`            | `loop-detect`          |
| Budget / circuit breaker               | `loop-detect`          |

`failure_type` from grep heuristics is an optional **hint** for the Skill — not a detect gate. **Skill** classifies Fix / Watch / Escalate.

### Integration mode

Per watch branch, `loop-detect` sets context; script uses `gh run list --branch <watch_branch> --status failure`.

- Range filter via `targets["integration:<branch>"].last_sha`
- **Dedupe:** `ci-sweeper-run-ledger.json` keyed by `workflow_run_id`

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

### `LOOP_NO_CHANGES_VERDICT: REJECT`

When the Skill classifies **Fix** but the implementer produces no changes → REJECT → `outcome: rejected`.

When the Skill classifies **Watch** (infra/flake/env) with no code edit → `outcome: watch` (not REJECT). See [Outcome enum](../../reference/specification.md#outcome-enum).

## PR Exclusion Rules

| Rule          | Default     | Token                                |
| ------------- | ----------- | ------------------------------------ |
| Fork PR       | Exclude     | `fork`                               |
| Draft         | Exclude     | `draft`                              |
| Label opt-out | Exclude     | `label:<name>`                       |
| Bots          | **Exclude** | use `LOOP_PR_INCLUDE_BOTS` to opt in |
| WIP title     | Optional    | `wip_title`                          |

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

| Persistence | Mechanism                                                           |
| ----------- | ------------------------------------------------------------------- |
| State       | `state-ci-sweeper.json` (`targets` map) on `LOOP_STATE_PUSH_BRANCH` |
| Run ledger  | `domain_persistence_script` → `update_run_ledger.sh`                |
| Run log     | `loop-run-log` in `loop-finalize` chain                             |

Dogfood: **`DEFAULT_LEVEL=L2`** until [L3 promotion gate](../loop-engineering-design.md).

## Implementation Checklist

- [ ] Single detect path via `loop-detect` (no caller re-run)
- [ ] `LOOP_INTEGRATION_BRANCHES` / `LOOP_PULL_REQUESTS`
- [ ] State `targets` map; flat `last_sha` removed
- [ ] `target_matrix` + matrix execute/finalize
- [ ] `verifier_context` always on execute
- [ ] Ledger via `domain_persistence_script` in `loop-finalize`
- [ ] `outcome: watch` for Skill Watch classification

## workflow_run Operational Checklist

Before uncommenting `workflow_run` in `on-loop-ci-sweeper.yaml`:

- [ ] zizmor / security review complete
- [ ] `CI_SWEEPER_EXCLUDED_WORKFLOWS` includes `on-loop-changelog`, `on-loop-ci-sweeper`, `on-loop-docs-triage`, `ci-loop-agent`
- [ ] Concurrency prevents overlapping runs on same `target.key`
- [ ] Event path sets `CI_SWEEPER_*` env on detect job
- [ ] Failed workflow is not the sweeper’s own finalize push (`[skip ci]` on ledger commits)
- [ ] Fork / draft / bot exclusions active
- [ ] 1 failure event → 1 target (no unbounded matrix from one event)

## dependency-update (roadmap)

`LOOP_PULL_REQUESTS=true` + `LOOP_PR_INCLUDE_BOTS=renovate[bot]`. Same workflow; no new package.

## Cross-Loop Note

CI failure on `integration:main` takes priority over `loop-docs-triage` and `loop-changelog` via [acting_on](../multi-branch-loops-design.md#cross-loop-coordination-acting_on). Include loop caller workflows in `CI_SWEEPER_EXCLUDED_WORKFLOWS` to prevent self-trigger recursion.

## References

- [cobusgreyling ci-sweeper pattern](https://github.com/cobusgreyling/loop-engineering/blob/main/patterns/ci-sweeper.md)
- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../reference/specification.md)
