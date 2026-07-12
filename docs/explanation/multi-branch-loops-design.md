# Multi-Branch Loops Design

Platform architecture for Loop Engineering loops that act on more than one branch (and ref).

**Scope:** target model, caller `env` contract, state, attempt accounting, `loop-detect` orchestration.  
**Out of scope:** GitHub Actions YAML job layout — see [Loop Caller Workflows Design](loop-caller-workflows-design.md). Per-loop behavior — see [Workflow designs](#workflow-design-documents).

| Document                                                        | Role                                                 |
| --------------------------------------------------------------- | ---------------------------------------------------- |
| [Loop Engineering Design](loop-engineering-design.md)           | Invariants, Phase Contract, finalize strategy matrix |
| [Loop Caller Workflows Design](loop-caller-workflows-design.md) | Shared `on-loop-*.yaml` shell                        |
| [Specification](../reference/specification.md)                  | Action I/O, detect script contract, outcome enum     |

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

| Variable                        | Description                                                                                                       | Default / empty            |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------------- |
| `LOOP_INTEGRATION_BRANCHES`     | Comma-separated branch patterns. Empty = mode off.                                                                | `""`                       |
| `LOOP_PULL_REQUESTS`            | `true` / `false`.                                                                                                 | `false`                    |
| `LOOP_BRANCH_MATCH`             | `list` \| `glob` \| `regex`.                                                                                      | `glob`                     |
| `LOOP_PRIORITY`                 | Cron mode order. Overridden by [trigger-aware priority](#trigger-aware-priority).                                 | `integration,pull_request` |
| `LOOP_FINALIZE_INTEGRATION`     | `open_pr` or `push` (L3).                                                                                         | `open_pr`                  |
| `LOOP_FINALIZE_PULL_REQUEST`    | `push_head`.                                                                                                      | `push_head`                |
| `DEFAULT_LEVEL`                 | `L1` \| `L2` \| `L3`. [Single level switch](#single-level-switch).                                                | `L2`                       |
| `LOOP_PR_EXCLUDE`               | PR exclusion tokens — see [CI Sweeper Workflow](workflows/loop-ci-sweeper-workflow-design.md#pr-exclusion-rules). | `fork,draft,label:no-loop` |
| `LOOP_PR_INCLUDE_BOTS`          | Bot logins to include. Empty = all bots excluded.                                                                 | `""`                       |
| `LOOP_MAX_TARGETS_PER_SCHEDULE` | Max targets per cron tick (fan-out cap).                                                                          | `3`                        |
| `LOOP_STATE_PUSH_BRANCH`        | Branch for `.loop/*` persistence commits.                                                                         | repository default branch  |

`.loop/*` metadata is **always centralized** on `LOOP_STATE_PUSH_BRANCH` (typically `main`), aligned with [cobusgreyling loop-engineering](https://github.com/cobusgreyling/loop-engineering). Fix PRs may target other branches; state does not follow `target.to.branch`.

### Env validation

| Condition                  | `skip_reason`   |
| -------------------------- | --------------- |
| Invalid config / regex     | `config_error`  |
| Both modes disabled        | `no_changes`    |
| Fan-out cap                | `target_budget` |
| Daily cap                  | `budget`        |
| Peer loop active on target | `peer_active`   |

## Single level switch

`DEFAULT_LEVEL` is **not** split per mode (intentional). One autonomy posture per loop name. Workaround for mixed needs: two caller workflows, same skill, different `env`.

## Trigger-aware priority

| Trigger        | Order                                                                          |
| -------------- | ------------------------------------------------------------------------------ |
| `schedule`     | `LOOP_PRIORITY` — integration before pull_request                              |
| `workflow_run` | pull_request when `head_branch` is open PR; else integration for failed branch |

`workflow_run` triggers remain disabled until per-loop ops checklist passes — see [CI Sweeper Workflow](workflows/loop-ci-sweeper-workflow-design.md#workflow_run-operational-checklist).

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
| `finalize`             | `open_pr` \| `push` \| `push_head`                              |

## Platform Contract: candidates and `target_json`

| Phase        | Role                                                                                                                   |
| ------------ | ---------------------------------------------------------------------------------------------------------------------- |
| **Detect**   | Output `target_matrix` when `should_run=true`. Each cell: `target_json`, `prompt`, `verifier_context`, `result`        |
| **Execute**  | Input one matrix cell; worktree from `from`; `verifier_context` always wired (may be empty)                            |
| **Finalize** | Input same cell + execute outputs; strategy per [finalize matrix](loop-engineering-design.md#finalize-strategy-matrix) |

Recorded in [Specification](../reference/specification.md).

## Execute and Verifier (platform)

| Mode         | Worktree                   | Verifier diff baseline |
| ------------ | -------------------------- | ---------------------- |
| integration  | `from.ref` @ `from.branch` | `to.branch`            |
| pull_request | `from.ref` @ `from.branch` | `base.branch`          |

`verifier_context`: platform always passes to `loop-execute`. Content is domain-specific (CI logs, detect fact summary). See [Specification](../reference/specification.md).

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

| Phase | Platform deliverable                                                               | Status                     |
| ----- | ---------------------------------------------------------------------------------- | -------------------------- |
| **0** | Single-branch dogfood                                                              | ✅ Done                    |
| **1** | `target_matrix`; `targets` map; no double detect; `acting_on`                      | In progress                |
| **2** | `target_json` on execute/finalize; `domain_persistence_script`; `push`/`push_head` | Planned                    |
| **3** | Matrix fan-out + per-target concurrency                                            | Planned (with Phase 1)     |
| **4** | `workflow_run` per loop ops checklist                                              | Planned (trigger disabled) |
| **5** | L3 integration `push` (opt-in)                                                     | Planned                    |
| **6** | Optional `repository` on target                                                    | Future                     |

Caller/workflow steps: [Loop Caller Workflows Design](loop-caller-workflows-design.md).

## Workflow Design Documents

| Loop                 | Document                                                                     | Caller workflow            |
| -------------------- | ---------------------------------------------------------------------------- | -------------------------- |
| **loop-changelog**   | [Changelog Workflow Design](workflows/loop-changelog-workflow-design.md)     | `on-loop-changelog.yaml`   |
| **loop-ci-sweeper**  | [CI Sweeper Workflow Design](workflows/loop-ci-sweeper-workflow-design.md)   | `on-loop-ci-sweeper.yaml`  |
| **loop-docs-triage** | [Docs Triage Workflow Design](workflows/loop-docs-triage-workflow-design.md) | `on-loop-docs-triage.yaml` |

Add new loops as `docs/explanation/workflows/<name>-workflow-design.md` without growing this file.

Shared caller `env` keys: [Loop Caller `env` Reference](workflows/loop-caller-env-reference.md).

## Decision Summary

| Question                    | Decision                                                       |
| --------------------------- | -------------------------------------------------------------- |
| Config                      | Caller `env` (table above)                                     |
| Target shape                | `mode` + from/to/base                                          |
| Branch scan                 | `loop-detect` enumerates + checkout; detect script per context |
| Fan-out                     | `target_matrix` → execute/finalize matrix                      |
| State persistence           | `LOOP_STATE_PUSH_BRANCH` (default branch), not per target      |
| `loop-pr-ci-healer` package | **No**                                                         |
| Levels                      | Single `DEFAULT_LEVEL`; L2 default                             |
| Bot PRs                     | Excluded; `LOOP_PR_INCLUDE_BOTS` opt-in                        |
| Detect filters              | Stable mechanical only; Skill classifies Watch                 |

## References

- [Loop Engineering Design](loop-engineering-design.md)
- [Loop Caller Workflows Design](loop-caller-workflows-design.md)
- [cobusgreyling loop-engineering](https://github.com/cobusgreyling/loop-engineering)
