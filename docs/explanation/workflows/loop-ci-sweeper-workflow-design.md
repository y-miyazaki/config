# CI Sweeper Workflow Design

Workflow and domain design for the `loop-ci-sweeper` (`ci-sweeper`) loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-ci-sweeper.yaml` · skill `loop-ci-sweeper` · `scripts/detect_ci_failures.sh` · `scripts/update_run_ledger.sh`

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

## Recommended `env` (consumer)

Link to [canonical `LOOP_*`](../multi-branch-loops-design.md#caller-configuration-canonical). Example:

```yaml
env:
  CI_SWEEPER_EXCLUDED_WORKFLOWS: on-loop-changelog,on-loop-ci-sweeper,on-loop-docs-triage,ci-loop-agent
  CI_SWEEPER_LEDGER_FILE: .loop/ci-sweeper-run-ledger.json
  CI_SWEEPER_REJECT_RETRY_POLICY: block
  DEFAULT_LEVEL: L2
  DOMAIN_PERSISTENCE_SCRIPT: .agents/skills/loop-ci-sweeper/scripts/update_run_ledger.sh
  LOOP_DETECT_SCRIPT: .agents/skills/loop-ci-sweeper/scripts/detect_ci_failures.sh
  LOOP_FINALIZE_INTEGRATION: open_pr
  LOOP_FINALIZE_PULL_REQUEST: push_head
  LOOP_INTEGRATION_BRANCHES: main,develop,release/*
  LOOP_NAME: ci-sweeper
  LOOP_PULL_REQUESTS: "true"
  LOOP_PR_EXCLUDE: fork,draft,label:no-loop
  LOOP_PR_INCLUDE_BOTS: ""
  LOOP_NO_CHANGES_VERDICT: REJECT
  SKILL_NAME: loop-ci-sweeper
```

### CI-specific `env`

| Variable                         | Role                                                                                |
| -------------------------------- | ----------------------------------------------------------------------------------- |
| `CI_SWEEPER_EXCLUDED_WORKFLOWS`  | Prevent sweeper self-trigger / recursion                                            |
| `CI_SWEEPER_INCLUDED_WORKFLOWS`  | Allowlist (empty = all non-excluded)                                                |
| `CI_SWEEPER_LEDGER_FILE`         | Run-level dedupe JSON                                                               |
| `CI_SWEEPER_REJECT_RETRY_POLICY` | `block` \| `retry` \| `limited` (dogfood: **`block`**)                              |
| `CI_SWEEPER_*` event vars        | Injected when `workflow_run` enabled (trigger remains disabled until ops checklist) |

Event vars (when `workflow_run` active): `CI_SWEEPER_HEAD_BRANCH`, `CI_SWEEPER_HEAD_SHA`, `CI_SWEEPER_WORKFLOW_RUN_ID`, `CI_SWEEPER_WORKFLOW_NAME`, `CI_SWEEPER_RUN_URL`.

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
