# Loop Agent Finalize Levels Design

**Status:** Approved (design session 2026-08-13)  
**Date:** 2026-08-13  
**Related:** [Loop Write Target and Delivery](2026-07-23-loop-write-target-delivery-design.md), [Loop Caller Workflows](../../explanation/loop-engineering/loop-caller-workflows-design.md), [Loop Caller Reusable](../../explanation/loop-engineering/loop-caller-reusable-design.md)

## Problem

`ci-loop-agent` treated **running the last platform job** and **opening a PR / git landing** as the same flag (`finalize_enabled`). Consequences:

- L1 (`agent-l1`) never entered finalize; a side job `record-l1` appended the run-log.
- L2/L3 with `delivery: none` also skipped finalize, so successful Agent runs left no run-log.
- Callers looked like they "turned finalize off" for L1, which contradicted the four-plane rule: **delivery is a finalize concern**, and run-log is platform persistence, not an Agent skill.

`record-l1` is the wrong name and the wrong place in the graph. The last hop after every Agent execute is finalize.

## Goals

- Every non-cancelled Agent execute is followed by a **finalize-\*** job (L1 → `finalize-l1`, L2/L3 → `finalize-l2`).
- Run-log append always happens in that finalize hop (when `loop_name` is set).
- Git landing / PR (`loop-finalize`) is an **inner step** of `finalize-l2`, gated by `finalize_enabled` (callers continue to set this from `delivery == open_pr`).
- No L1-only job on `ci-loop-caller*.yaml`. Detect-time skips stay on caller `record-skip`.
- This repository's callers dogfood `./.github/workflows/ci-loop-agent.yaml` so graph changes take effect without a tag pin.

## Non-Goals

- `finalize-l3` as a third job (L3 is `agent-l2` + `auto_merge` on `finalize-l2`).
- Implementing L1 `delivery: issue | notion` connectors in this change (the job exists so those steps attach to `finalize-l1` later).
- Capturing L1 token `usage_json` (`loop-agent-once` still does not export it).
- Moving `record-skip` into `ci-loop-agent` (no Agent job ran).

## Job graph

```text
ci-loop-caller*.yaml
  detect
    ├─ should_run=false + (budget|circuit_breaker) → record-skip → loop-run-log
    └─ should_run=true → execute (matrix) → ci-loop-agent.yaml
         level L1:     agent-l1 → finalize-l1
         level L2|L3:  agent-l2 → finalize-l2
```

| Job           | Runs when                                         | Always does                                                          | Conditionally does                     |
| ------------- | ------------------------------------------------- | -------------------------------------------------------------------- | -------------------------------------- |
| `finalize-l1` | `level==L1`, `agent-l1` not skipped/cancelled     | checkout, token, `loop-run-log`                                      | future: L1 delivery (`issue` / `log`)  |
| `finalize-l2` | `level==L2\|L3`, `agent-l2` not skipped/cancelled | checkout, token, `loop-run-log` (and notify when a PR number exists) | `loop-finalize` iff `finalize_enabled` |

Cancelled Agent jobs skip the matching finalize hop (no partial log required). Failed Agent jobs **do** finalize so the error is recorded.

## `finalize_enabled` contract

| Layer                          | Meaning                                                           |
| ------------------------------ | ----------------------------------------------------------------- |
| Caller `with.finalize_enabled` | Still `${{ delivery == 'open_pr' }}`. Unchanged at caller YAML.   |
| `ci-loop-agent` **job** `if`   | Must **not** require `finalize_enabled`. Job runs for run-log.    |
| `loop-finalize` **step** `if`  | `inputs.finalize_enabled` — git landing / state / PR create only. |

When the `loop-finalize` step is skipped (`delivery` not `open_pr`):

- Do not treat the skipped step as a finalize failure in run-log metadata.
- Run-log `outcome`: agent failure → `error`; `verdict==REJECT` → `rejected`; otherwise `no-changes` (no platform PR). If `loop-finalize` ran, prefer its `outputs.outcome` (`pr-created`, …).

## Naming

- Forbidden: `record-l1` as a sibling of `agent-l1`.
- Required: `finalize-l1` / `finalize-l2` mirroring `agent-l1` / `agent-l2`.
- Token-resolution comments list `finalize-l1` / `finalize-l2`, not a generic `finalize`.

## Caller dogfood

Both `ci-loop-caller.yaml` and `ci-loop-caller-entity.yaml` `execute.uses` **this repo relative path**:

`./.github/workflows/ci-loop-agent.yaml`

External repositories that pin `y-miyazaki/config/.../ci-loop-agent.yaml@<sha>` pick up the graph on the next pin bump. This repository must not wait on a tag for the invariant to hold.

## `delivery: issue` (not implied by entity L1)

Entity loops and `delivery: issue` are **independent**. An entity caller (`ci-loop-caller-entity`) binding a GitHub Issue event to `agent-l1` does **not** implement `delivery: issue`. Jobs must not be specified as "the Agent already commented, so skip the adapter."

| Pattern                   | `delivery` | Who talks to GitHub Issues                                                         |
| ------------------------- | ---------- | ---------------------------------------------------------------------------------- |
| issue-triage today        | `none`     | Implementer Agent during the session (labels/comments on the **triggering** Issue) |
| `delivery: issue` adapter | `issue`    | **finalize-l1 / finalize-l2 only** — skill does not call Issue APIs                |

When `delivery` is `issue`, finalize resolves the destination as:

1. **Specified Issue** — if `target_json` (or detect result) carries an Issue number (`entity.number`, `issue_number`, or equivalent), append a comment (and optional labels) to that Issue.
2. **Create Issue** — if no number is present, create a new Issue from the Agent report (title/body). Repository default is the current repo unless `target_json` names another.

`none` means finalize does not post. In-session skill mutations on the triggering entity remain a separate, explicit skill contract — they are not a substitute for the adapter and must not be retrofitted as "`delivery: issue` is already done."

The adapter itself is **not** implemented in this change. `finalize-l1` is the attach point.

## Tests

`test/bats/github-actions/loop-caller-parity.bats` asserts:

- both callers share `auto_merge`, `may_edit` mapping, `pr_draft`, `record-skip` skip reasons
- both `uses: ./.github/workflows/ci-loop-agent.yaml`
- `ci-loop-agent` has `finalize-l1` and `finalize-l2`, not `record-l1`
- `finalize-l2` job `if` does not gate on `finalize_enabled`
- `loop-finalize` step is gated on `finalize_enabled`

`entity_target.bats` keeps `target_json.finalize` derived from `delivery`.
