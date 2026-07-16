# Multi-Branch Loops Design

Platform architecture for Loop Engineering loops that act on more than one branch (and ref).

**Scope:** target model, caller `env` contract, state, attempt accounting, `loop-detect` orchestration.  
**Out of scope:** GitHub Actions YAML job layout — see [Loop Caller Workflows Design](loop-caller-workflows-design.md). Per-loop behavior — see [Workflow designs](#workflow-design-documents).

| Document                                                        | Role                                                 |
| --------------------------------------------------------------- | ---------------------------------------------------- |
| [Loop Engineering Design](loop-engineering-design.md)           | Invariants, Phase Contract, finalize strategy matrix |
| [Loop Caller Workflows Design](loop-caller-workflows-design.md) | Shared `on-loop-*.yaml` shell                        |
| [Specification](../../reference/specification.md)               | Action I/O, detect script contract, outcome enum     |

## Problem

Phase 0 loops assume **one branch per run**: detect polls `main` only; execute/finalize ignore `head_branch` in detect JSON.

Two **independent**, caller-configurable capabilities:

| Capability               | Example                                                                | Typical loops                         |
| ------------------------ | ---------------------------------------------------------------------- | ------------------------------------- |
| **Integration branches** | Drift or CI on `main`, `develop`, `release/*` → fix **to** that branch | `loop-docs-triage`, `loop-ci-sweeper` |
| **Pull request heads**   | CI fails on open PR → fix **on PR branch**                             | `ci-sweeper`                          |

## Design Goal

| Loop                 | Integration branches | Pull requests        |
| -------------------- | -------------------- | -------------------- |
| **loop-docs-triage** | Default on           | Default off          |
| **loop-ci-sweeper**  | Configurable         | Configurable         |
| **Future loops**     | Same target contract | Same target contract |

## Caller Configuration (canonical)

Defined here only. Other docs link to this section.

`ci-loop-caller` workflow inputs map to these `loop-detect` environment variables — see [Loop Caller Inputs Reference](workflows/loop-caller-inputs-reference.md#branch-configuration).

| Variable                        | `ci-loop-caller` input     | Description                                                                                                                                                                                  | Default / empty            |
| ------------------------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| `LOOP_INTEGRATION_BRANCHES`     | `branch_match`             | Comma-separated branch patterns. Empty = watch `branch_state` only.                                                                                                                          | `""`                       |
| `LOOP_PULL_REQUESTS`            | `pr_enabled` / `pull_requests` | `true` / `false`. Watch open PR heads.                                                                                       | `false`                    |
| `LOOP_BRANCH_MATCH`             | `branch_match_mode`        | `list` \| `glob` \| `regex`.                                                                                                                                                                 | `glob`                     |
| `LOOP_PRIORITY`                 | `priority`                 | Cron mode order. Overridden by [trigger-aware priority](#trigger-aware-priority).                                                                                                            | `integration,pull_request` |
| `LOOP_FINALIZE_INTEGRATION`     | `finalize_integration`     | Finalize for integration targets. Wire default **`open_pr`**. Exception: `push` (L3 direct write).                                                                                           | `open_pr`                  |
| `LOOP_FINALIZE_PULL_REQUEST`    | `finalize_pull_request`    | Finalize for PR-head targets. Wire default **`push_head`**. Migration to default `open_pr` pending (see ci-sweeper checklist).                                                               | `push_head`                |
| `DEFAULT_LEVEL`                 | `level`                    | `L1` \| `L2` \| `L3`. L3 + `open_pr` → GitHub auto-merge on bot fix PR. [Single level switch](#single-level-switch).                                                                       | `L2`                       |
| `LOOP_PR_EXCLUDE`               | `pr_exclude`               | PR exclusion tokens — see [CI Sweeper Workflow](workflows/loop-ci-sweeper-workflow-design.md#pr-exclusion-pr_exclude).                                                                        | `fork,draft,label:no-loop` |
| `LOOP_PR_REQUIRE`               | `pr_require`               | PR require tokens (all must match). Empty when `pull_requests=true` → no PR-head targets (fail-closed).                                                                                      | `""` (ci-sweeper dogfood sets `label:ci-sweeper-ok`) |
| `LOOP_PR_INCLUDE_BOTS`          | `pr_include_bots`          | Bot logins to include. Empty = all bots excluded.                                                                                                                                            | `""`                       |
| `LOOP_MAX_TARGETS_PER_SCHEDULE` | `max_targets_per_schedule` | Max targets per cron tick (fan-out cap).                                                                                                                                                     | `3`                        |
| `LOOP_STATE_PUSH_BRANCH`        | `branch_state`             | Branch for `.loop/*` persistence commits and state migration fallback.                                                                                                                       | repository default branch  |

`.loop/*` metadata is **always centralized** on `branch_state` (typically `main`), aligned with [cobusgreyling loop-engineering](https://github.com/cobusgreyling/loop-engineering). Fix PRs may target other branches; state does not follow `target.to.branch`.

### Env validation

| Condition                  | `skip_reason`   |
| -------------------------- | --------------- |
| Invalid config / regex     | `config_error`  |
| Both modes disabled        | `no_changes`    |
| Fan-out cap                | `target_budget` |
| Daily cap                  | `budget`        |
| Peer loop active on target | `peer_active`   |
| Open pending fix PR        | `pending_pr`    |

## Single level switch

`DEFAULT_LEVEL` is **not** split per mode (intentional). One autonomy posture per loop name. Workaround for mixed needs: two caller workflows, same skill, different `env`.

## Trigger-aware priority

| Trigger        | Order                                                                          |
| -------------- | ------------------------------------------------------------------------------ |
| `schedule`     | `LOOP_PRIORITY` — integration before pull_request                              |
| `workflow_run` | pull_request when `head_branch` is open PR; else integration for failed branch |

`workflow_run` is enabled for dogfood `loop-ci-sweeper` after the [ops checklist](workflows/loop-ci-sweeper-workflow-design.md#workflow_run-operational-checklist). Other loops stay schedule / `workflow_dispatch` until their checklist passes.

## `loop-detect` orchestration

`loop-detect` owns platform enumeration and checkout. The caller **never** re-invokes the detect script.

```text
loop-detect
  1. Read LOOP_* + state (targets map)
  2. Resolve integration branch list (glob/regex)
  3. Optionally enumerate open PRs (LOOP_PULL_REQUESTS)
  4. For each scan context:
       a. fetch/checkout target ref
       b. invoke detect_script (once per context)
       c. if not skip: build candidate (target_json, result, prompt, verifier_context)
  5. Apply acting_on / peer_active on each candidate.key
  6. Apply LOOP_PRIORITY + LOOP_MAX_TARGETS_PER_SCHEDULE
  7. Output target_matrix (JSON array)
```

Execute and finalize jobs use **matrix fan-out** over `target_matrix` — one cell per target, parallel with per-target `concurrency.group`.

Detect scripts scan **only the current context** (branch/ref `loop-detect` checked out). They do not iterate branches themselves.

## Target Model (from / to)

```json
{
  "mode": "integration",
  "key": "integration:main",
  "from": { "branch": "main", "ref": "abc123" },
  "to": { "branch": "main" },
  "finalize": "open_pr"
}
```

```json
{
  "mode": "pull_request",
  "key": "pull_request:42",
  "from": { "branch": "feature/auth", "ref": "def456" },
  "to": { "branch": "feature/auth", "pr_number": 42 },
  "base": { "branch": "main" },
  "finalize": "push_head"
}
```

| Field                  | Description                                                     |
| ---------------------- | --------------------------------------------------------------- |
| `mode`                 | `integration` \| `pull_request`                                 |
| `key`                  | State key: `integration:<branch>` or `pull_request:<pr_number>` |
| `from` / `to` / `base` | Detect, finalize, verifier diff baseline                        |
| `finalize`             | Wire defaults: integration `open_pr`, pull_request `push_head`  |

## Branch roles and fix direction

Three branch roles on callers — detailed tables in [Loop Caller Inputs Reference](workflows/loop-caller-inputs-reference.md#branch-configuration):

| Role             | `ci-loop-caller` input                                   | Behavior                                                                                      |
| ---------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| **Watch**        | `branch_match`, `branch_match_mode`, `pr_enabled`        | Detect scans matching integration branches and/or open PR heads                               |
| **State**        | `branch_state`, `state_file`                             | `.loop/*` persistence commits land on `branch_state`; optional path override via `state_file` |
| **Autonomy**     | `level`                                                  | L2: human merge on bot fix PR; L3: GitHub auto-merge on bot fix PR when `finalize=open_pr`    |

## Platform Contract: candidates and `target_json`

| Phase        | Role                                                                                                                   |
| ------------ | ---------------------------------------------------------------------------------------------------------------------- |
| **Detect**   | Output `target_matrix` when `should_run=true`. Each cell: `target_json`, `prompt`, `verifier_context`, `result`        |
| **Execute**  | Input one matrix cell; worktree from `from`; `verifier_context` always wired (may be empty)                            |
| **Finalize** | Input same cell + execute outputs; strategy per [finalize matrix](loop-engineering-design.md#finalize-strategy-matrix) |

Recorded in [Specification](../../reference/specification.md).

## Execute and Verifier (platform)

| Mode         | Worktree                   | Verifier diff baseline |
| ------------ | -------------------------- | ---------------------- |
| integration  | `from.ref` @ `from.branch` | `to.branch`            |
| pull_request | `from.ref` @ `from.branch` | `base.branch`          |

`verifier_context`: platform always passes to `loop-execute`. Content is domain-specific (CI logs, detect fact summary). See [Specification](../../reference/specification.md).

## State and Attempt Accounting

### `targets` map

```json
{
  "targets": {
    "integration:main": {
      "last_sha": "abc123",
      "outcome": "pr-created",
      "consecutive_failures": 0,
      "attempt_fingerprint": "sha256:…"
    }
  },
  "acting_on": null
}
```

Field sets differ by loop — see each workflow design doc.

### Per-target state delivery (`state_bundle_with_fix_pr`)

Caller input on `ci-loop-caller` (see [Loop Caller Inputs Reference](workflows/loop-caller-inputs-reference.md)). Controls whether **per-target cursor fields** (`last_sha`, `outcome`, …) are committed on the **fix branch** before `open_pr`, or pushed to `branch_state` separately.

| Mode                      | `state_bundle_with_fix_pr` | Reviewer sees                                         | When to use                                                                                                                                                             |
| ------------------------- | -------------------------- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Bundled**               | `true`                     | One PR: domain fix + `.loop/state-<loop>.json`        | Watch branch equals fix branch **and** equals `branch_state` (typical dogfood: all `main`). Cursor advances only when the fix PR merges.                                |
| **Centralized** (default) | `false`                    | Fix PR + optional separate state PR to `branch_state` | Multi-branch watch while `branch_state` stays `main`; PR-head fixes use bot fix PR + `loop-notify-pr` on human PR. |

**Always on `branch_state` (not bundled):** run log, budget — operational metadata, not reviewer-facing.

**On `REJECT`:** finalize still writes target state to `branch_state` (failure accounting without a fix PR).

#### Loop defaults (dogfood)

| Loop               | Default           | Rationale                                                                                                                    |
| ------------------ | ----------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `loop-changelog`   | `false` (default) | Merge-gated `pending` via `on-loop-state-promote`                                                                            |
| `loop-docs-triage` | `false`           | Merge-gated `pending` (same as changelog; do not bundle state in fix PR)                                                     |
| `loop-ci-sweeper`  | `false`           | Merge-gated `pending` for integration and PR-head bot fix PRs; run ledger for dedupe |

Bundling is **per-loop opt-in**, not a global LE requirement. The historical default (centralized on `branch_state`) exists for [multi-branch watch + shared state file](#branch-roles-and-fix-direction), not because users prefer two PRs.

### State delivery philosophy

**State is not a reviewer-facing deliverable.** `.loop/state-*.json` holds machine cursors (`last_sha`), outcomes, and circuit-breaker counters — analogous to a CI cache key or migration ledger, not to `CHANGELOG.md` or doc fixes. Asking humans to approve state in a PR is a category error.

| Delivery                                                                                         | Verdict                                                                                                                                                       |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Direct push to `branch_state`** (bot token + branch-protection bypass for `.loop/*`)           | **Target.** State updates are infrastructure writes, not review gates.                                                                                        |
| **Merge-gated state push** (`pull_request` `closed` + `merged` → promote `pending` → `last_sha`) | **Chosen L2 model.** Fix PR is domain-only; state advances on the merge **event**, not because a human approved a state diff.                                 |
| **State-only PR** (including auto-merge queue)                                                   | **Anti-pattern.** A fallback when push is blocked; must not be the designed happy path.                                                                       |
| **`state_bundle_with_fix_pr`**                                                                   | **Deprecated interim.** Mixed machine state into a human PR; retire after merge-gated push.                                                                   |
| **L3 `push` / `push_head`**                                                                      | **Platform exception.** Dogfood uses `open_pr` + GitHub auto-merge instead of direct push. |

**What matters more than PR vs push is _when_ `last_sha` advances:**

- Pushing state at finalize **before** the fix PR merges → cursor races ahead; rejected fixes are skipped on re-detect. **Wrong** for L2 `open_pr`.
- Advancing `last_sha` **when the fix is accepted** (PR merged, or L3 push) → **correct**.

So “state should be pushed, not PR’d” is right for **delivery mechanism**. It is insufficient without **timing**: centralized direct push belongs at **fix acceptance**, not unconditionally at finalize success.

**`git push --force`:** not part of normal loop operation. “強制” here means **bypass the PR gate** (ruleset allowing `github-actions[bot]` to push `.loop/*` to `branch_state`), not rewriting history on every run. Reserve force-push for explicit recovery only.

**Platform direction (chosen):**

1. **L2:** Fix PR carries **domain files only**. On `pull_request` `closed` + `merged`, a platform handler **direct-pushes** state to `branch_state` (promote `pending` → `last_sha`). Humans never review or merge state.
2. **L2 + `to.branch != branch_state`:** Same merge hook; state always lands on `branch_state`, not on the fix branch.
3. **L3:** `finalize: push` / `push_head` — single atomic push to the watched branch; no **new fix PR**, no `pending` state cursor.
4. **`state_bundle_with_fix_pr`:** **Deprecated interim** (changelog dogfood today). Remove once merge-gated push ships. Do not adopt for new loops.

**Pending cursor:** On `pr-created`, finalize writes `targets[key].pending = { sha, pr, … }` to `branch_state` via direct push **without** advancing `last_sha`. `on-loop-state-promote` (`pull_request` `closed`) promotes `pending.sha` → `last_sha` on merge or clears `pending` when closed without merge. Re-open detect therefore still sees the same commits if the fix PR is closed without merge.

### Migration

On first Phase 1+ read, if legacy flat `last_sha` exists and `targets` is absent:

1. `loop-state-read` copies `last_sha` (and related fields) into `targets["integration:<default_branch>"]`
2. Subsequent writes **omit** flat `last_sha` — `targets` only

### Circuit breaker (per `target.key`)

| Field                  | Role                                        |
| ---------------------- | ------------------------------------------- |
| `attempt_fingerprint`  | workflow run / commit range + failure class |
| `consecutive_failures` | ≥3 → `circuit_breaker` (`skip_reason`)      |

`outcome: watch` does **not** increment `consecutive_failures`. CI run-ledger is **secondary** dedupe — see [CI Sweeper Workflow](workflows/loop-ci-sweeper-workflow-design.md#detect-truth-source).

## Cross-Loop Coordination (`acting_on`)

```json
{
  "acting_on": {
    "target_key": "integration:main",
    "loop_name": "ci-sweeper",
    "started_at": "2026-07-10T18:00:00Z"
  }
}
```

| Phase        | Behavior                                                                                                                                          |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Detect**   | Read all `.loop/state-*.json` peers. If `acting_on.target_key` matches candidate and `started_at` within TTL (90 min) → `skip_reason=peer_active` |
| **Execute**  | Set `acting_on` on this loop's state file (via `loop-state-write` sub-step or execute preamble)                                                   |
| **Finalize** | Clear `acting_on` (always, success or failure)                                                                                                    |

Per-target `concurrency.group` in caller YAML complements `acting_on` — see [Loop Caller Workflows](loop-caller-workflows-design.md#concurrency).

## Implementation Phases

| Phase | Platform deliverable                                                               | Status                                             |
| ----- | ---------------------------------------------------------------------------------- | -------------------------------------------------- |
| **0** | Single-branch dogfood                                                              | ✅ Done                                            |
| **1** | `target_matrix`; `targets` map; no double detect; `acting_on`                      | ✅ Done                                            |
| **2** | `target_json` on execute/finalize; `domain_persistence_script`; `push`/`push_head` | ✅ Done                                            |
| **3** | Matrix fan-out + per-target concurrency                                            | ✅ Done                                            |
| **4** | `workflow_run` per loop ops checklist                                              | ✅ Done (ci-sweeper dogfood; other loops TBD)      |
| **5** | L3 integration `push` (opt-in)                                                     | Planned                                            |
| **6** | Optional `repository` on target                                                    | Future                                             |
| **7** | `ci-loop-caller.yaml` — thin callers + `with:`                                     | ✅ Done ([design](loop-caller-reusable-design.md)) |
| **8** | Merge-gated state push (`on-loop-state-promote`)                                   | ✅ Done                                            |

Caller/workflow steps: [Loop Caller Workflows Design](loop-caller-workflows-design.md).

## Workflow Design Documents

| Loop                 | Document                                                                     | Caller workflow            |
| -------------------- | ---------------------------------------------------------------------------- | -------------------------- |
| **loop-changelog**   | [Changelog Workflow Design](workflows/loop-changelog-workflow-design.md)     | `on-loop-changelog.yaml`   |
| **loop-ci-sweeper**  | [CI Sweeper Workflow Design](workflows/loop-ci-sweeper-workflow-design.md)   | `on-loop-ci-sweeper.yaml`  |
| **loop-docs-triage** | [Docs Triage Workflow Design](workflows/loop-docs-triage-workflow-design.md) | `on-loop-docs-triage.yaml` |

Add new loops as `docs/explanation/loop-engineering/workflows/<name>-workflow-design.md` without growing this file.

Shared caller configuration: [Loop Caller Inputs Reference](workflows/loop-caller-inputs-reference.md) (`with:` on `ci-loop-caller`). Legacy: [Loop Caller `env` Reference](workflows/loop-caller-env-reference.md).

## Decision Summary

| Question                    | Decision                                                                                                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Config                      | Caller `with:` on `ci-loop-caller` ([inputs reference](workflows/loop-caller-inputs-reference.md))                                                                       |
| Target shape                | `mode` + from/to/base                                                                                                                                                    |
| Branch scan                 | `loop-detect` enumerates + checkout; detect script per context                                                                                                           |
| Fan-out                     | `target_matrix` → execute/finalize matrix                                                                                                                                |
| State persistence           | Direct push to `branch_state` (no state PR); per-loop [delivery modes](#per-target-state-delivery-state_bundle_with_fix_pr) and [philosophy](#state-delivery-philosophy) |
| `loop-pr-ci-healer` package | **No**                                                                                                                                                                   |
| Levels                      | Single `DEFAULT_LEVEL`; L2 default                                                                                                                                       |
| Bot PRs                     | Excluded; `LOOP_PR_INCLUDE_BOTS` opt-in                                                                                                                                  |
| Detect filters              | Stable mechanical only; Skill classifies Watch                                                                                                                           |

## References

- [Loop Engineering Design](loop-engineering-design.md)
- [Loop Caller Workflows Design](loop-caller-workflows-design.md)
- [cobusgreyling loop-engineering](https://github.com/cobusgreyling/loop-engineering)

