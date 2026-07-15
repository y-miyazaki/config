# loop-notify-pr Specification (Draft)

Platform specification for PR notifications after loop finalize on `pull_request` targets (`push_head`).
Status: **implemented (P1)** — `loop-notify-pr`, `notify_context_json`, and `LOOP_PR_REQUIRE` in `.github/actions/`; release pin bump pending.

| Layer                  | Document                                                                                  |
| ---------------------- | ----------------------------------------------------------------------------------------- |
| Invariants             | [Loop Engineering Design](../explanation/loop-engineering-design.md)                      |
| Targets / `pr_exclude` | [Multi-Branch Loops Design](../explanation/multi-branch-loops-design.md)                  |
| CI sweeper dogfood     | [CI Sweeper Workflow Design](../explanation/workflows/loop-ci-sweeper-workflow-design.md) |

## Problem

`push_head` updates an existing PR branch without opening a new PR. Today finalize does not post human-visible notifications. Authors and reviewers cannot distinguish bot fixes from their own commits or understand why a change landed.

## Goals

1. Post or update a single marker comment on the target PR when a loop attempts finalize on a `pull_request` target.
2. Require explicit opt-in via a repository label before PR-head repair runs.
3. Keep notification content platform-owned (Layers 1–2). Skill output is optional appendix only.
4. Implement via shared `loop-notify-pr` action as a sibling step after `loop-finalize` in `ci-loop-agent` (not per-caller shell logic).

## Non-Goals (v1)

- Notifications for `integration` + `open_pr` (fix PR body is sufficient; no `pr_number` on target).
- Notifications for `integration` + `push` (L3; no PR).
- Bot-created or bot-applied labels (human/maintainer applies opt-in label).
- Inline review comments per changed line (reviewdog-style).
- External channels (Slack, email, PagerDuty).
- Auto-merge of the human PR after `push_head` (unchanged: `push_head` never enables auto-merge).

## Repository Prerequisites

| Prerequisite                                   | Owner                   | Failure mode                                                     |
| ---------------------------------------------- | ----------------------- | ---------------------------------------------------------------- |
| Label `ci-sweeper-ok` exists in the repository | Repo admin (one-time)   | PR-head targets never match opt-in → detect skips (not an error) |
| Label applied to PRs that allow bot repair     | PR author or maintainer | PR skipped until label present                                   |
| `pull-requests: write` on finalize job         | Caller workflow         | `loop-notify-pr` cannot post comment                             |

**Invariant (v1):** The loop runtime must not call GitHub APIs to **create repository labels** or **add labels to PRs**. Opt-in is explicit human action.

### Label permissions — can the bot create labels?

**Technically yes, but v1 does not use it.**

| Capability                        | GitHub permission                        | v1 behavior                                                         |
| --------------------------------- | ---------------------------------------- | ------------------------------------------------------------------- |
| Create repo label `ci-sweeper-ok` | App `administration: write` or admin PAT | **Repo admin or IaC** creates once (setup checklist). Bot does not. |
| Add label to a PR                 | `issues: write` / `pull-requests: write` | **Humans apply** opt-in. Bot does not.                              |

Granting the maintenance bot label-creation or label-application permissions would not improve safety: opt-in would become bot-self-granted unless humans still apply the label manually. Runtime label creation also hides misconfiguration (missing label looks like “no PRs to fix” instead of a setup error).

**Optional bootstrap (out of v1 scope):** a one-time `workflow_dispatch` or Terraform resource that creates `ci-sweeper-ok` in the repository. That is repository onboarding, not loop finalize.

### Opt-in check timing (v1)

Label membership is evaluated at **detect only**. If a label is removed after detect but before finalize, v1 still proceeds. Re-check at finalize is deferred to v2.

## PR Watch Filters

### Existing: `pr_exclude` (deny)

Comma-separated tokens processed by `loop-detect`:

| Token          | Behavior                   |
| -------------- | -------------------------- |
| `fork`         | Exclude fork PRs           |
| `draft`        | Exclude draft PRs          |
| `label:<name>` | Exclude PRs with label     |
| `wip_title`    | Exclude WIP title patterns |

### New: `pr_require` (allow)

Comma-separated **require** tokens. All must match for a PR to be eligible.

| Token          | Behavior                                        |
| -------------- | ----------------------------------------------- |
| `label:<name>` | PR must have label (e.g. `label:ci-sweeper-ok`) |

**Dogfood default (ci-sweeper):**

```text
pr_exclude: fork,draft,label:no-loop
pr_require: label:ci-sweeper-ok
```

**Empty `pr_require`:** When `pull_requests=true`, empty `pr_require` means **no PR-head targets** (fail-closed). Callers must set at least one require token to enable PR-head repair. This prevents deny-only configs from silently enabling `push_head` on all open PRs.

If the required label does not exist in the repository, no PR can satisfy `pr_require` → PR-head mode is effectively disabled (silent no-op, not workflow failure).

Maps to `loop-detect` env: `LOOP_PR_REQUIRE` (new), caller input: `pr_require`.

**Evaluation order:** Apply `pr_exclude` first, then `pr_require`. A PR with both `label:no-loop` and `label:ci-sweeper-ok` is excluded.

## When `loop-notify-pr` Runs

| Condition                                                                  | Notify             |
| -------------------------------------------------------------------------- | ------------------ |
| `target_json.mode == pull_request`                                         | Yes                |
| `target_json.to.pr_number` present                                         | Yes                |
| `target_json.mode == integration`                                          | No                 |
| Finalize attempted (success, `rejected`, `watch`, `error` with PR context) | Yes — all outcomes |
| Detect `should_run == false`                                               | No                 |
| Execute skipped (budget, peer_active, etc.)                                | No                 |

Invocation: **sibling step** in `ci-loop-agent.yaml` immediately after `loop-finalize` (not nested inside `loop-finalize` — composite actions must not nest per [specification](specification.md#composite-action-composition)). Run with `if: always()` when `pr_number` is set and the finalize job executed.

## Notification Content Layers

### Layer 1 — Platform (required, machine-sourced)

`loop-notify-pr` must render these fields without parsing skill output:

| Field           | Source                                                                                |
| --------------- | ------------------------------------------------------------------------------------- |
| Loop name       | `loop_name` input                                                                     |
| Actor           | GitHub App / bot login from token                                                     |
| Outcome         | finalize outcome enum                                                                 |
| Verdict         | `APPROVE` / `REJECT` / empty                                                          |
| Commit SHA      | finalize push result (link to commit on PR head)                                      |
| Branch          | `target_json.to.branch`                                                               |
| PR number       | `target_json.to.pr_number`                                                            |
| Failed workflow | `target_json.workflow_run_id` + URL from detect `result` or event env                 |
| Failing job     | detect `failures[].job_name` when present                                             |
| Loop run URL    | `${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}` |
| Attempt         | `attempts` / `agent_loop_max_attempts`                                                |
| Timestamp       | finalize time (UTC)                                                                   |

### Layer 2 — Mechanical fix context (required when `has_changes == true`)

Extracted by `loop-execute` into `notify_context_json` (platform; not skill):

| Field           | Source                                                                             |
| --------------- | ---------------------------------------------------------------------------------- |
| `changed_files` | `git diff --name-only` vs verifier baseline ref                                    |
| `diff_stat`     | `git diff --stat` (truncated)                                                      |
| `fix_summary`   | Template: `"Address CI failure in <job_name> (<workflow_name>)"` from detect facts |

When `has_changes == false`, omit Layer 2 file lists; include `reject_reason` or watch classification instead.

### Appendix — Skill (optional)

`loop-execute` may parse implementer output for a fenced block:

```markdown
<!-- loop-agent-summary:v1 -->

...
```

and place the text in `notify_context_json.agent_summary`. **`loop-notify-pr` does not parse skill output** — it reads `agent_summary` from JSON only. Parse failure in execute omits the field; notify still succeeds with Layers 1–2.

Skill packages must not be required to emit this block. `loop-ci-sweeper` may document it as optional in `common-output-format.md`.

### Beyond Layers 1–2: What v1 Does Not Need

| Item                            | Verdict                | Reason                                            |
| ------------------------------- | ---------------------- | ------------------------------------------------- |
| Full patch / diff in comment    | **No**                 | Size limits, noise, secrets risk                  |
| Duplicate of fix PR body        | **No**                 | N/A for `push_head`; integration uses separate PR |
| Re-request review automatically | **Deferred**           | Policy varies; may annoy authors                  |
| `@mention` PR author            | **Optional v1.1**      | Useful but needs spam guard                       |
| Link to newly created fix PR    | **No** for `push_head` | Same PR                                           |
| Checks API annotation           | **Deferred**           | PR comment is primary channel per design decision |
| Per-file inline comments        | **No**                 | Different product (reviewdog)                     |

Layers 1–2 plus outcome-specific messaging (success / rejected / watch) are sufficient for v1 auditability.

## Comment Format

Marker for idempotent update (loop name embedded — resolves per-loop comment scope):

```html
<!-- loop-notify-pr:v1:{loop_name} -->
```

Single comment per PR per loop name. Update existing comment when marker matches; create otherwise.

### Template (normative structure)

```markdown
<!-- loop-notify-pr:v1:{loop_name} -->

## Loop notification: {loop_name}

| Field      | Value                                  |
| ---------- | -------------------------------------- |
| Outcome    | `{outcome}`                            |
| Verdict    | {verdict or —}                         |
| Actor      | `{actor}`                              |
| Commit     | [`{short_sha}`]({commit_url})          |
| Branch     | `{to.branch}`                          |
| Failed run | [{workflow_name} #{run_id}]({run_url}) |
| Loop run   | [actions run]({loop_run_url})          |
| Attempt    | {attempts}/{max_attempts}              |

### Fix context

{Layer 2 bullets or reject/watch message}

### Agent summary (appendix)

{optional skill block}
```

## Execute Output Extension

Extend L2/L3 unified contract (`ci-loop-agent` → `loop-finalize`):

| Output                | Type          | Required | Description                          |
| --------------------- | ------------- | -------- | ------------------------------------ |
| `notify_context_json` | string (JSON) | always   | Machine context for `loop-notify-pr` |

### `notify_context_json` schema

```json
{
  "changed_files": ["path/a", "path/b"],
  "diff_stat": " 2 files changed, 10 insertions(+), 1 deletion(-)",
  "fix_summary": "Address CI failure in lint (on-ci-push-shell-script)",
  "agent_summary": "",
  "baseline_ref": "abc1234"
}
```

| Field           | Required           | Notes                                                                      |
| --------------- | ------------------ | -------------------------------------------------------------------------- |
| `changed_files` | when `has_changes` | Max 20 paths; truncate with `… (+N more)`                                  |
| `diff_stat`     | when `has_changes` | Max 500 chars                                                              |
| `fix_summary`   | always             | Platform template from detect facts                                        |
| `agent_summary` | no                 | Set by `loop-execute` from optional `<!-- loop-agent-summary:v1 -->` block |
| `baseline_ref`  | pull_request       | Merge-base SHA of `base.branch` vs worktree HEAD used for `git diff`       |

Existing outputs unchanged: `branch`, `has_changes`, `verdict`, `reason`, `attempts`, `open_rejections`, `usage_json`.

When execute fails before producing a diff, emit empty `notify_context_json` (`changed_files: []`, `fix_summary` from detect facts if available). `loop-notify-pr` still runs on PR targets.

### `push_head` git semantics

`push_head` uses **non-force** push to `to.branch` only. If push fails (non-FF, branch protection), finalize records `outcome: error` and `loop-notify-pr` still posts with outcome and reason. Force-push is not part of normal loop operation.

## `loop-notify-pr` Action Contract (Draft)

| Input                 | Required | Description                           |
| --------------------- | -------- | ------------------------------------- |
| `token`               | yes      | `pull-requests: write`                |
| `repository`          | yes      | `owner/repo`                          |
| `pr_number`           | yes      | Target PR                             |
| `loop_name`           | yes      | For marker scoping                    |
| `outcome`             | yes      | Outcome enum                          |
| `verdict`             | no       |                                       |
| `commit_sha`          | no       | Set when push succeeded               |
| `target_json`         | yes      | Full target for branch / run metadata |
| `notify_context_json` | yes      | From execute                          |
| `reject_reason`       | no       | Verifier reason                       |
| `attempts`            | no       |                                       |
| `max_attempts`        | no       |                                       |
| `loop_run_id`         | yes      | `${{ github.run_id }}`                |

| Output        | Description                   |
| ------------- | ----------------------------- |
| `comment_url` | Posted or updated comment URL |
| `comment_id`  | GraphQL node id               |

**Failure policy:** `continue-on-error: true` on notify step. Finalize outcome must not flip to `error` solely because comment posting failed. Log warning; append `notify_failed: true` to run-log metadata (future).

## Comment body sanitization (v1)

| Field                                           | Rule                                                                                                                                                                                                                                                      |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `changed_files`                                 | Max 20 paths; truncate with `… (+N more)`                                                                                                                                                                                                                 |
| `diff_stat`                                     | Max 500 characters                                                                                                                                                                                                                                        |
| `fix_summary`, `reject_reason`, `agent_summary` | Apply the same redact patterns as CI detect `sanitize_log_excerpt` (GitHub tokens `gh[pousr]_…`, `AKIA…`, `password`/`secret`/`token`/`api_key` assignments, `x-access-token:`, `Bearer …`, `Authorization:`, JWT, PEM blocks). Max 2000 characters each. |
| Total comment body                              | Target under 32 KiB; hard cap 64 KiB (GitHub limit). Omit appendix first if over budget.                                                                                                                                                                  |

Do not embed full `git diff` or raw CI logs in the comment.

## Finalize Invariant Change

Replace in [Loop Engineering Design](../explanation/loop-engineering-design.md):

```diff
- Must not: Perform notifications
+ Must not: Perform ad-hoc notifications outside loop-notify-pr
+ Must: Invoke loop-notify-pr when target_json.to.pr_number is set and finalize phase executed
```

## Implementation Phases

| Phase  | Deliverable                                                                                                                                     |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **P0** | Spec + design docs (this document)                                                                                                              |
| **P1** | `loop-notify-pr` in `y-miyazaki/config`; `notify_context_json` in `loop-execute`; `LOOP_PR_REQUIRE` in `loop-detect`; caller input `pr_require` |
| **P2** | Dogfood: `on-loop-ci-sweeper.yaml` + label setup note in workflow design doc                                                                    |
| **P3** | Optional `agent_summary` appendix in `loop-ci-sweeper` skill reference                                                                          |

## Future Features (Explicit Backlog)

Items reviewed for v1; deferred unless noted.

| Feature                                                | Priority | Notes                                |
| ------------------------------------------------------ | -------- | ------------------------------------ |
| `@mention` PR author on success                        | P2       | Rate-limit per PR per day            |
| GitHub Check run "loop-notify"                         | P3       | Secondary channel                    |
| Comment reaction (eyes/+1) on outcome                  | P3       | GitNexus-style UX                    |
| `pr_require: author:collaborator`                      | P3       | Only org members                     |
| Notification when fix PR links to source issue         | N/A      | integration `open_pr` only           |
| Digest comment for N fixes same PR                     | P4       | After repeat-fix loop countermeasure |
| Cross-repo `target_json.repository`                    | P5       | Phase 6 multi-repo                   |
| L1 comment-only loops using same action                | P2       | Same template, no push fields        |
| Escalation comment at circuit breaker                  | P2       | `consecutive_failures >= 3`          |
| `loop-dismiss` label/token to revoke opt-in mid-flight | P4       |                                      |
| Full diff attachment as artifact link                  | P4       | Avoid inline secrets                 |

## Design Gap Checklist (Self-Review)

| Gap                                            | Status           | Resolution                                            |
| ---------------------------------------------- | ---------------- | ----------------------------------------------------- |
| Silent `push_head` on human PRs                | **Addressed**    | `loop-notify-pr` + `pr_require`                       |
| Label permission errors                        | **Addressed**    | Humans apply label; no bot label APIs                 |
| Skill output drift breaks notify               | **Addressed**    | Layers 1–2 platform-only; skill appendix optional     |
| Notify fails blocks finalize                   | **Addressed**    | `continue-on-error`                                   |
| Integration open_pr needs "original PR" notify | **N/A**          | No original PR in integration mode                    |
| `push_head` + auto-merge confusion             | **Documented**   | `push_head` never auto-merges                         |
| Repeat silent fixes (5+ times)                 | **Partial**      | Attempt counter in comment; circuit breaker separate  |
| Fork PR opt-in                                 | **Excluded**     | `pr_exclude: fork` remains                            |
| Bot-owned PR heads (Renovate)                  | **Configurable** | `pr_include_bots` unchanged                           |
| Secrets in comment body                        | **Mitigated**    | No full diff; sanitize `reject_reason` / log excerpts |
| Comment spam on flaky CI                       | **Partial**      | Update single marker comment; ledger dedupe unchanged |
| Author notification preference                 | **Deferred**     | Label opt-in is coarse gate                           |
| Merge conflict after bot push                  | **Out of scope** | Human resolves; comment includes SHA for context      |

## Resolved decisions

| Topic                | v1 decision                              |
| -------------------- | ---------------------------------------- |
| Label name (dogfood) | `ci-sweeper-ok`                          |
| Marker scope         | `<!-- loop-notify-pr:v1:{loop_name} -->` |
| Opt-in re-check      | Detect only                              |
| Bot label APIs       | Not used at runtime                      |

## Open Questions (deferred)

1. **Run-log field:** Add `notify_comment_url` to JSONL entry? — v1.1
2. **Config repo pin:** Minimum `loop-finalize` / `ci-loop-agent` release tag for notify step? — decide at implementation PR

## References

- [cobusgreyling ci-sweeper — comment on existing PR](https://github.com/cobusgreyling/loop-engineering/blob/main/patterns/ci-sweeper.md)
- `github-pr-body` skill — `pr_comment.sh` marker update pattern
