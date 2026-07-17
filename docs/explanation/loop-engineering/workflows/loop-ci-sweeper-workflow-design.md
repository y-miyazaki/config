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

- **Integration branch CI failure** (`main`, `develop`, `release/*`, …) → open a bot fix PR **to** the watch branch; L3 enables GitHub **auto-merge** on that fix PR
- **Open PR head CI failure** → open a bot fix PR **to the PR head branch** (not `main`); post a marker comment on the **human PR** with fix summary and link to the bot fix PR; L3 auto-merges the bot fix PR into the head branch
- Classify failures as Fix / Watch / Escalate; apply small lint, workflow, shell, or doc edits when actionable
- Dedupe by `workflow_run_id` ledger; skip infra/flake/env failures as `outcome: watch`
- `workflow_run` on repair-target CI workflows (dogfood default); `workflow_dispatch` for manual / `gh run list` scan; see [ops checklist](#workflow_run-operational-checklist)

Dogfood uses **`open_pr` for all repair paths**. Direct branch push (`push` / `push_head`) is a platform exception path — not the ci-sweeper default. See [Finalize strategy](#finalize-strategy).

### Out of scope

Entry skill design intent for failure kinds deferred via [Failure kind defer (B)](../loop-engineering-design.md#failure-kind-defer-b) — coverage threshold, dependency breakage.

- Infra outages, secrets, runner capacity, or persistent flakes (Watch — no code edit when Skill recognizes them)
- Large refactors (>5 files), auth/payment/credential paths
- Auto-merging the **human's** open PR (only the **bot fix PR** is auto-merged at L3)
- Re-running CI in the verifier (semantic fit against log excerpt only)
- Manual interactive debugging as a substitute for the loop
- Separate `loop-pr-ci-healer` package
- **Coverage-threshold and test-gap repair** — defer (B) until a domain skill exists
- **Dependency-breakage repair** — defer (B); bot PR heads excluded in dogfood (`pr_include_bots: ""`)
- Per-PR opt-in labels (`pr_require`) — removed; use `pr_exclude` only

Skill execution boundaries: `loop-ci-sweeper` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

### Execute — responsibility split (A' / B)

Distributable `loop-ci-sweeper` skill stays repository-neutral. **Do not** hardcode consumer skill names in skill `references/`. Named dispatch belongs in caller `prompt_instructions` (dogfood: `on-loop-ci-sweeper.yaml`).

| Layer         | Input                       | Role                                                                                            |
| ------------- | --------------------------- | ----------------------------------------------------------------------------------------------- |
| Detect        | `detect_ci_failures.sh`     | `failures[]`, `failure_type` hint; optional future `stack_hint`                                 |
| Entry skill   | `loop-ci-sweeper`           | Generic orchestration: classify, follow `## Instructions` for skill dispatch, fix one, validate |
| Caller        | `prompt_instructions`       | **Stack routing (A')** — workflow/stack → named domain skills for this repo                     |
| Caller        | `agent_verifier_criteria`   | Failure kind defer (B): appendix REJECT rules                                                   |
| Domain skills | Consumer `.agents/skills/*` | Invoked per caller routing table                                                                |

See [CI failure repair — layered responsibilities](../loop-engineering-design.md#ci-failure-repair--one-package-layered-responsibilities).

### Failure contexts

Two independent watch paths. Both use **`open_pr`** finalize; **`level`** selects human review (L2) vs GitHub auto-merge on the bot fix PR (L3).

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

## Caller inputs

Keys are passed in `on-loop-ci-sweeper.yaml` via `with:` on `ci-loop-caller-full-github.yaml` (alphabetically ordered). Multiline values (`agent_verifier_criteria`, `pr_body`, `prompt_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Legacy env name mapping: [Loop Caller `env` Reference](loop-caller-env-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

**Dogfood minimum (autonomy + PR watch):**

```yaml
level: L2
pr_enabled: true # target name; wire name today: pull_requests
pr_exclude: fork,draft,label:no-loop
```

Do **not** set caller `finalize_integration` or `finalize_pull_request` for ci-sweeper — platform defaults to `open_pr` for both modes. See [Level × finalize matrix](loop-caller-inputs-reference.md#level--finalize-matrix).

| Input / JSON key                                            | Description                                                                                                                                                                            | Dogfood value                                                                                            |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `additional_commit_paths`                                   | Extra paths included in finalize commit (ledger file).                                                                                                                                 | `.loop/state-ci-sweeper-run-ledger.json`                                                                 |
| `agent_implementer_max_turns`                               | Max implementer agent turns per loop attempt (one Agent→Verify cycle).                                                                                                                 | `8`                                                                                                      |
| `agent_implementer_model`                                   | Implementer model ID. Cursor: `agent --list-models`.                                                                                                                                   | `cursor-grok-4.5-low`                                                                                    |
| `agent_loop_max_attempts`                                   | Max Agent→Verify retry cycles before finalize records failure.                                                                                                                         | `3`                                                                                                      |
| `agent_verifier_criteria`                                   | Verifier APPROVE/REJECT rubric. Requires fix addresses logged CI failure; minimal diff; allowlist/denylist respected.                                                                  | Inline in caller workflow                                                                                |
| `agent_verifier_max_turns`                                  | Max verifier agent turns per verification.                                                                                                                                             | `3`                                                                                                      |
| `agent_verifier_model`                                      | Verifier model ID. Cursor: `agent --list-models`.                                                                                                                                      | `composer-2.5`                                                                                           |
| `allowlist`                                                 | Comma-separated globs the implementer may modify.                                                                                                                                      | `.github/**,.apm/packages/**,scripts/**,apm.yml,mise.toml,renovate/**,docs/**/*.md,README.md,mkdocs.yml` |
| `branch_match`                                              | Comma-separated integration branch patterns to poll for failed CI.                                                                                                                     | `main`                                                                                                   |
| `branch_state`                                              | Branch for `.loop/*` persistence, state migration, and watch fallback.                                                                                                                 | `main`                                                                                                   |
| `budget_max_runs_per_day`                                   | Daily run cap keyed by `loop_name`. Caller input; `.loop/loop-budget.json` overrides when present.                                                                                     | `5` (caller); effective `50` via `.loop/loop-budget.json`                                                |
| `budget_max_tokens_per_day`                                 | Daily aggregated token cap across loops.                                                                                                                                               | `1000000`                                                                                                |
| `denylist`                                                  | Comma-separated globs the implementer must never modify (credentials, infra, migrations).                                                                                              | `**/.env,**/credentials*,**/secrets*,**/migration/*.sql,**/infrastructure/**`                            |
| `detect_domain_env_json` → `CI_SWEEPER_LEDGER_FILE`         | JSON ledger path for `workflow_run_id` dedupe.                                                                                                                                         | `.loop/state-ci-sweeper-run-ledger.json`                                                                 |
| `detect_domain_env_json` → `CI_SWEEPER_REJECT_MAX_RETRIES`  | Max re-attempts per run ID when policy is `limited`.                                                                                                                                   | `3`                                                                                                      |
| `detect_domain_env_json` → `CI_SWEEPER_REJECT_RETRY_POLICY` | `block`, `retry`, or `limited` — ledger policy for prior `rejected` entries.                                                                                                           | `block`                                                                                                  |
| Reusable workflow (`uses:`)                                 | `ci-loop-caller-full-github.yaml` — detect job requires `actions: read` and `pull-requests: read`; caller `permissions` must include `actions: read`.                                  | `./.github/workflows/ci-loop-caller-full-github.yaml`                                                    |
| `detect_script`                                             | Domain detect script path. Uses `gh run list` per watch branch / PR head.                                                                                                              | `.agents/skills/loop-ci-sweeper/scripts/detect_ci_failures.sh`                                           |
| `domain_persistence_script`                                 | Bash script for `loop-finalize` domain persistence (run ledger updates).                                                                                                               | `.agents/skills/loop-ci-sweeper/scripts/update_run_ledger.sh`                                            |
| `engine`                                                    | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                                                  | `cursor`                                                                                                 |
| `level`                                                     | Autonomy: `L2` (human merges bot fix PR) or `L3` (GitHub auto-merge on bot fix PR).                                                                                                    | `L2`                                                                                                     |
| `loop_name`                                                 | Loop identifier; state file `.loop/state-ci-sweeper.json`.                                                                                                                             | `ci-sweeper`                                                                                             |
| `max_targets_per_schedule`                                  | Max targets per cron tick after priority/`acting_on` filters.                                                                                                                          | `3`                                                                                                      |
| `no_changes_verdict`                                        | `APPROVE` or `REJECT` when implementer produces no file diff on actionable CI failure.                                                                                                 | `REJECT`                                                                                                 |
| `pr_body`                                                   | Static markdown prefix only; `loop-finalize` hybrid-composes the final PR body. See [Loop PR Body Hybrid Design](../../../superpowers/specs/2026-07-17-loop-pr-body-hybrid-design.md). | Inline in caller workflow                                                                                |
| `pr_enabled`                                                | Watch open PR heads for failed CI. **Wire name today:** `pull_requests`.                                                                                                               | `true`                                                                                                   |
| `pr_exclude`                                                | PR exclusion tokens: `fork`, `draft`, `label:<name>`, `wip_title`.                                                                                                                     | `fork,draft,label:no-loop`                                                                               |
| `pr_include_bots`                                           | Comma-separated bot logins to include when scanning PRs. Empty = exclude all bots.                                                                                                     | `""`                                                                                                     |
| `pr_title`                                                  | PR title when finalize strategy is `open_pr`.                                                                                                                                          | `fix(ci): automated CI repair (loop-ci-sweeper)`                                                         |
| `prompt_instructions`                                       | Domain instructions: classify Watch vs Fix; minimal diff; run validation skills.                                                                                                       | Inline in caller workflow                                                                                |
| `skill_name`                                                | Skill package to invoke.                                                                                                                                                               | `loop-ci-sweeper`                                                                                        |

**Removed from dogfood (do not set):** `pr_require`, `finalize_integration`, `finalize_pull_request`.

**Event keys** (embedded in `detect_domain_env_json` when `workflow_run` fires; dogfood caller enables this trigger):

| JSON key                       | Description                                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| `CI_SWEEPER_EVENT_HEAD_BRANCH` | Stable failed-run head branch (not rewritten per scan). Drives `loop-detect` watch-list scoping. |
| `CI_SWEEPER_HEAD_BRANCH`       | Per-scan branch context rewritten by `loop-detect` for each target.                              |
| `CI_SWEEPER_HEAD_SHA`          | Failed workflow run head SHA.                                                                    |
| `CI_SWEEPER_WORKFLOW_RUN_ID`   | Failed workflow run ID for ledger dedupe **and** trigger-aware target scoping.                   |
| `CI_SWEEPER_WORKFLOW_NAME`     | Failed workflow display name.                                                                    |
| `CI_SWEEPER_RUN_URL`           | HTML URL of the failed workflow run (verifier context).                                          |

When `CI_SWEEPER_WORKFLOW_RUN_ID` is set, `loop-detect` enumerates **only** the failed head (matching integration branch or open PR). See [Trigger-aware priority](../multi-branch-loops-design.md#trigger-aware-priority). Detect script binaries are always pinned from the job checkout (branch_state), never from a stale PR worktree.

## Detect

### Stable mechanical filters (detect script + platform)

Detect applies **only** stable gates — not semantic failure classification:

| Filter                                  | Layer                  |
| --------------------------------------- | ---------------------- |
| Ledger dedupe (`workflow_run_id`)       | detect script          |
| `workflow_run` caller `workflows:` list | caller trigger         |
| `workflow_run` → single failed head     | `loop-detect` scope    |
| Pin `DETECT_SCRIPT` absolute path       | `loop-detect`          |
| Event run branch vs scan branch         | detect script          |
| PR exclusion (fork, draft, bot, label)  | `loop-detect` + script |
| `acting_on` / `peer_active`             | `loop-detect`          |
| Budget / circuit breaker                | `loop-detect`          |

`failure_type` from grep heuristics is an optional **hint** for the Skill — not a detect gate. Default is `regression` when the log is not infra/env/flake. See [Execute — responsibility split](#execute--responsibility-split-a--b).

### Integration mode

Per watch branch, `loop-detect` sets context; script uses `gh run list --branch <watch_branch> --status failure`.

- Range filter via `targets["integration:<branch>"].last_sha`
- **Dedupe:** `state-ci-sweeper-run-ledger.json` keyed by `workflow_run_id` (entries pruned after **30 days** on ledger update)

### Pull request mode

Requires `pr_enabled: true` (wire: `pull_requests`).

- Failed runs where `head_branch` matches an eligible open PR
- Emit `pr_number`, `base.branch` in `target_json.to`
- Apply [PR exclusion rules](#pr-exclusion-pr_exclude)

### Detect truth source

| Mode         | Primary cursor             | Secondary                                 |
| ------------ | -------------------------- | ----------------------------------------- |
| integration  | `workflow_run_id` + ledger | `last_sha` in state (advance on finalize) |
| pull_request | `workflow_run_id` + ledger | `head_ref` per PR in state                |

**Rule:** Do not rely on `last_sha` alone to skip a still-failing workflow run. Ledger outcome `pr-created` or `watch` blocks re-processing same run ID under `block` policy.

### `no_changes_verdict: REJECT`

When the Skill classifies **Fix** but the implementer produces no changes → REJECT → `outcome: rejected`.

When the Skill classifies **Watch** (infra/flake/env) with no code edit → `outcome: watch` (not REJECT). See [Outcome enum](../../../reference/specification.md#outcome-enum).

## PR exclusion (`pr_exclude`)

| Rule          | Default     | Token                           |
| ------------- | ----------- | ------------------------------- |
| Fork PR       | Exclude     | `fork`                          |
| Draft         | Exclude     | `draft`                         |
| Label opt-out | Exclude     | `label:<name>`                  |
| Bots          | **Exclude** | use `pr_include_bots` to opt in |
| WIP title     | Optional    | `wip_title`                     |

No label opt-in (`pr_require`) — eligible open PRs passing `pr_exclude` are watched when `pr_enabled: true`.

After finalize on `pull_request` targets, `loop-notify-pr` posts or updates a marker comment on the **human PR** (`target_json.to.pr_number`), including the bot fix PR URL when finalize creates one. See [loop-notify-pr Specification](../../../reference/loop-notify-pr-specification.md).

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

## Finalize strategy

PR body is hybrid-composed by `loop-finalize` (see [Loop PR Body Hybrid Design](../../../superpowers/specs/2026-07-17-loop-pr-body-hybrid-design.md)). Caller `pr_body` remains a static prefix only.

Platform rule for dogfood loops (changelog, docs-triage, ci-sweeper): **`target.finalize` is always `open_pr`**. **`level`** controls review vs auto-merge on the **bot fix PR**.

| Mode           | L2                                        | L3                                                        |
| -------------- | ----------------------------------------- | --------------------------------------------------------- |
| `integration`  | Bot fix PR → `to.branch`; human merge     | Bot fix PR → `to.branch`; **GitHub auto-merge**           |
| `pull_request` | Bot fix PR → PR head; comment on human PR | Bot fix PR → PR head; **auto-merge**; comment on human PR |

Reference: [Finalize strategy matrix](../loop-engineering-design.md#finalize-strategy-matrix).

| Persistence | Mechanism                                                 |
| ----------- | --------------------------------------------------------- |
| State       | `state-ci-sweeper.json` (`targets` map) on `branch_state` |
| Run ledger  | `domain_persistence_script` → `update_run_ledger.sh`      |
| Run log     | `loop-run-log` in `loop-finalize` chain                   |

Dogfood: **`level=L2`** until [L3 promotion gate](../loop-engineering-design.md).

## Implementation Checklist

- [ ] Single detect path via `loop-detect` (no caller re-run)
- [ ] `branch_match` / `pr_enabled` (`pull_requests` wire)
- [ ] State `targets` map; flat `last_sha` removed
- [ ] `target_matrix` + matrix execute/finalize
- [ ] `verifier_context` always on execute
- [ ] Ledger via `domain_persistence_script` in `loop-finalize`
- [ ] `outcome: watch` for Skill Watch classification
- [ ] `loop-notify-pr` on human PR for `pull_request` mode
- [ ] `open_pr` finalize for PR head targets (implementation migration from `push_head`-only)
- [x] Hybrid PR body pins: `ci-loop-agent.yaml` uses `loop-finalize` / `loop-execute` @ v1.8.36 (`render_pr_body.sh`)

## workflow_run Operational Checklist

Dogfood `on-loop-ci-sweeper.yaml` enables `workflow_run`. Keep these gates when changing the trigger or `workflows:` list:

- [x] zizmor / security review complete (`zizmor: ignore[dangerous-triggers]` documented on the trigger)
- [x] `workflow_run.workflows` lists only CI workflows to repair (not `on-loop-*` / `ci-loop-*` callers)
- [x] Concurrency prevents overlapping runs on same workflow
- [x] Event path sets `CI_SWEEPER_*` keys in `detect_domain_env_json`
- [x] Failed workflow is not the sweeper’s own finalize push (`[skip ci]` on ledger commits)
- [x] Fork / draft / bot exclusions active (`pr_exclude`)
- [x] Job `if:` limits event runs to `failure` / `startup_failure`
- [x] 1 failure event → 1 target (no unbounded matrix from one event) — `loop-detect` scopes watch list to failed head when `CI_SWEEPER_WORKFLOW_RUN_ID` is set; verify when expanding `workflows:`

## Dependency update (caller filter + domain skill)

Tier 3 **dependency-update** behavior is a domain skill plus caller PR filters (`pr_include_bots`, `pr_exclude`) under **`loop-ci-sweeper`** — not a separate loop package. Defer via [Failure kind defer (B)](../loop-engineering-design.md#failure-kind-defer-b) until the skill exists.

## Cross-Loop Note

CI failure on `integration:main` takes priority over `loop-docs-triage` and `loop-changelog` via [acting_on](../multi-branch-loops-design.md#cross-loop-coordination-acting_on). Limit recursion with `workflow_run.workflows` (caller allowlist), run ledger (`workflow_run_id`), and daily budget — not workflow-name exclude lists in detect.

`workflow_dispatch` (no event run ID) uses `gh run list` on the watch branch (`SCAN_BRANCH_RUN_LIMIT`, default 100), then ledger and `since` range filters. Skill classifies infra/env/flake failures as Watch.

## References

- [cobusgreyling ci-sweeper pattern](https://github.com/cobusgreyling/loop-engineering/blob/main/patterns/ci-sweeper.md)
- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
