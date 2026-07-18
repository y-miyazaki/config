# loop-notify-pr Specification (Draft)

Platform specification for PR notifications after loop finalize on `pull_request` targets.
Status: **implemented (P1)** — `loop-notify-pr`, `notify_context_json` in `.github/actions/`; PR-head finalize migration to `open_pr` pending.

| Layer                  | Document                                                                                                   |
| ---------------------- | ---------------------------------------------------------------------------------------------------------- |
| Invariants             | [Loop Engineering Design](../explanation/loop-engineering/loop-engineering-design.md)                      |
| Targets / `pr_exclude` | [Multi-Branch Loops Design](../explanation/loop-engineering/multi-branch-loops-design.md)                  |
| CI sweeper dogfood     | [CI Sweeper Workflow Design](../explanation/loop-engineering/workflows/loop-ci-sweeper-workflow-design.md) |

## Problem

When CI fails on a **human open PR**, the loop opens a separate **bot fix PR** targeting the PR head branch (`open_pr`). The human PR author has no in-thread signal unless the platform posts on the human PR.

## Goals

1. Post or update a single marker comment on the **human PR** (`target_json.to.pr_number`) when finalize runs for a `pull_request` target.
2. Include fix summary and **link to the bot fix PR** when finalize creates one (`open_pr`).
3. Prompt the author to merge or close the bot fix PR (L2) or note that it was auto-merged (L3).
4. Keep notification content platform-owned (Layers 1–2). Skill output is optional appendix only.
5. Implement via shared `loop-notify-pr` action as a sibling step after `loop-finalize` in `ci-loop-agent` (not per-caller shell logic).

`loop-notify-pr` uses `notify_context_json` for human PR comments only. PR description composition is owned by `loop-finalize` (`render_pr_body.sh`).

## Non-Goals (v1)

- Notifications for `integration` + `open_pr` (fix PR body is sufficient; no human PR in scope).
- Per-PR opt-in labels (`pr_require` / `ci-sweeper-ok`) — removed; use `pr_exclude` only.
- Auto-merge of the **human PR** (only the **bot fix PR** is auto-merged at L3).
- Inline review comments per changed line (reviewdog-style).
- External channels (Slack, email, PagerDuty).

## Repository Prerequisites

| Prerequisite                            | Owner           | Failure mode                         |
| --------------------------------------- | --------------- | ------------------------------------ |
| `pr_enabled: true` on ci-sweeper caller | Loop maintainer | PR-head targets not enumerated       |
| `pull-requests: write` on finalize job  | Caller workflow | `loop-notify-pr` cannot post comment |

## PR watch filters (`pr_exclude`)

Comma-separated deny tokens processed by `loop-detect`:

| Token          | Behavior                   |
| -------------- | -------------------------- |
| `fork`         | Exclude fork PRs           |
| `draft`        | Exclude draft PRs          |
| `label:<name>` | Exclude PRs with label     |
| `wip_title`    | Exclude WIP title patterns |

**Dogfood default (ci-sweeper):**

```text
pr_exclude: fork,draft,label:no-loop
pr_enabled: true
```

Bots excluded unless `pr_include_bots` lists them. No `pr_require` gate.

## When `loop-notify-pr` Runs

| Condition                                                                  | Notify             |
| -------------------------------------------------------------------------- | ------------------ |
| `target_json.mode == pull_request`                                         | Yes                |
| `target_json.to.pr_number` present (human PR)                              | Yes                |
| `target_json.mode == integration`                                          | No                 |
| Finalize attempted (success, `rejected`, `watch`, `error` with PR context) | Yes — all outcomes |
| Detect `should_run == false`                                               | No                 |
| Execute skipped (budget, etc.)                                             | No                 |

Invocation: **sibling step** in `ci-loop-agent.yaml` immediately after `loop-finalize`. Run with `if: always()` when `pr_number` is set and the finalize job executed.

## Notification Content Layers

### Layer 1 — Platform (required, machine-sourced)

| Field           | Source                                                                                |
| --------------- | ------------------------------------------------------------------------------------- |
| Loop name       | `loop_name` input                                                                     |
| Actor           | GitHub App / bot login from token                                                     |
| Outcome         | finalize outcome enum                                                                 |
| Verdict         | `APPROVE` / `REJECT` / empty                                                          |
| Bot fix PR      | URL/number from finalize when `open_pr` succeeded                                     |
| Branch          | `target_json.to.branch` (PR head)                                                     |
| Human PR number | `target_json.to.pr_number`                                                            |
| Failed workflow | `target_json.workflow_run_id` + URL from detect `result` or event env                 |
| Failing job     | detect `failures[].job_name` when present                                             |
| Loop run URL    | `${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}` |
| Attempt         | `attempts` / `agent_loop_max_attempts`                                                |
| Level           | L2 vs L3 (merge guidance vs auto-merge note)                                          |

### Layer 2 — Mechanical fix context (required when `has_changes == true`)

| Field           | Source                                                                             |
| --------------- | ---------------------------------------------------------------------------------- |
| `changed_files` | `git diff --name-only` vs verifier baseline ref                                    |
| `diff_stat`     | `git diff --stat` (truncated)                                                      |
| `fix_summary`   | Template: `"Address CI failure in <job_name> (<workflow_name>)"` from detect facts |

L2 success messaging must include **merge or close the bot fix PR** guidance.

### Appendix — Skill (optional)

Optional `<!-- loop-agent-summary:v1 -->` block via `notify_context_json.agent_summary`.

## Comment Format

Marker: `<!-- loop-notify-pr:v1:{loop_name} -->`

### Template (normative structure)

```markdown
<!-- loop-notify-pr:v1:{loop_name} -->

## Loop notification: {loop_name}

| Field      | Value                                  |
| ---------- | -------------------------------------- |
| Outcome    | `{outcome}`                            |
| Bot fix PR | [#{fix_pr}]({fix_pr_url}) or —         |
| Branch     | `{to.branch}`                          |
| Failed run | [{workflow_name} #{run_id}]({run_url}) |
| Loop run   | [actions run]({loop_run_url})          |

### Fix context

{Layer 2 bullets}

**Next step (L2):** Merge or close the bot fix PR above, then re-run CI on this PR.
**Next step (L3):** Bot fix PR auto-merge enabled when checks pass.
```

## Execute Output Extension

| Output                | Type          | Required | Description                          |
| --------------------- | ------------- | -------- | ------------------------------------ |
| `notify_context_json` | string (JSON) | always   | Machine context for `loop-notify-pr` |

Schema unchanged — see prior revision for field list. Add `fix_pr_url` / `fix_pr_number` from finalize outputs when wired.

## `loop-notify-pr` Action Contract (Draft)

Inputs/outputs unchanged from P1 except:

- `commit_sha` — set when finalize pushed or opened PR from agent branch
- Comment body includes bot fix PR link for `open_pr` finalize

**Failure policy:** `continue-on-error: true` on notify step.

## Implementation Phases

| Phase  | Deliverable                                                                             |
| ------ | --------------------------------------------------------------------------------------- |
| **P0** | Spec + design docs (this document)                                                      |
| **P1** | `loop-notify-pr`, `notify_context_json`, `pr_exclude` filters                           |
| **P2** | Dogfood ci-sweeper: `open_pr` to PR head + notify with fix PR link; remove `pr_require` |
| **P3** | Optional `agent_summary` appendix in `loop-ci-sweeper` skill reference                  |

## Resolved decisions

| Topic              | Decision                                             |
| ------------------ | ---------------------------------------------------- |
| Opt-in             | `pr_exclude` deny list only; no label opt-in         |
| Human PR automerge | Never — L3 auto-merge applies to **bot fix PR** only |
| Delivery           | `open_pr` to PR head branch; not direct `push_head`  |
| Marker scope       | `<!-- loop-notify-pr:v1:{loop_name} -->`             |

## References

- [cobusgreyling ci-sweeper — comment on existing PR](https://github.com/cobusgreyling/loop-engineering/blob/main/patterns/ci-sweeper.md)
- [CI Sweeper Workflow Design](../explanation/loop-engineering/workflows/loop-ci-sweeper-workflow-design.md)
