# PR Revise Workflow Design

| Layer        | Document                                                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                                                       |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (branch / PR-head)                                                |
| Spec         | [Issue Autofix and PR Revise Full Design](../../../superpowers/specs/2026-08-11-issue-autofix-pr-revise-full-design.md)            |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                                           |

**Artifacts:** `on-loop-github-pr-revise.yaml` · skill `github-pr-revise` · `detect_pr_revise.sh` · `ci-loop-caller.yaml`

## Purpose

Single intake for PR revision from human feedback: conversation or review comments containing default **`@loop`** (caller `mention` overrides) + `repository_dispatch` / `workflow_dispatch` → **branch / PR-head** caller.

Detect skips bots and comments without the mention token. Default landing: `git_landing_pull_request=push_head` (stacked via `open_pr`).

## Caller shape

```text
on-loop-github-pr-revise.yaml
  loop → uses ci-loop-caller.yaml
           detect  → detect_pr_revise.sh
           ack-trigger (optional) → eyes reaction on trigger comment
           execute → ci-loop-agent (may_edit=true)
           finalize → push_head (default) or open_pr
```

`issue_comment` jobs run only when `github.event.issue.pull_request` is set.

## Trigger UX (ACK + thread reply)

After detect proceeds on a comment webhook:

| Stage | Behavior |
| ----- | -------- |
| Start ACK | `eyes` reaction on each gathered `result.comments[].comment_id` (fallback: trigger `comment.id`) via `ack-trigger` when `ack_trigger_comment` |
| Done reply | Inline review: threaded REST reply; conversation comment: follow-up PR comment (`loop-notify-pr`) |
| Marker | Run-level `loop-notify-pr` marker comment unchanged |
| Resolve | Human only — no auto-resolve |

Detect JSON includes `result.comment_id`, `result.event_name`, inline review fields, and `result.comments` (batched open `@mention` feedback). See [Detect result](#detect-result).

## Concurrency and push_head landing

Same-PR revise runs **serialize**; earlier product fixes must remain on the PR head.

| Rule | Behavior |
| ---- | -------- |
| Concurrency group | `loop-github-pr-revise-<pr_number>` on `on-loop-github-pr-revise.yaml` |
| `cancel-in-progress` | `false` — do not kill in-flight revise work |
| `queue` | `max` — queued mentions wait; one worker per PR at a time |
| `push_head` landing | `loop-finalize` `push_target.sh` checks out latest `to.branch`, merges the agent branch with `--no-ff`, pushes without force |
| Conflict | Merge or non-fast-forward push fails the finalize step (fail closed; no tip overwrite) |
| Out of scope | Comment gather / one-session batching (`#683`); last-run-only discard of earlier fixes |

`open_pr` finalize is unchanged. Prefer keeping lost-commit prevention on the shared `push` / `push_head` path rather than force-push or cancel-newest policies.

## Detect result

`detect_pr_revise.sh` emits `result` facts consumed via file-backed detect JSON / loop-detect prompt:

| Field | Source | Notes |
| ----- | ------ | ----- |
| `pr_number` | PR / issue / dispatch payload | Required to proceed |
| `mention` | `PR_MENTION` (default `@loop`) | Mention gate on comment webhooks |
| `comment_body` | Trigger `comment.body` or dispatch feedback | Backward-compatible scalar for the webhook that started the run |
| `comment_id` | Trigger `comment.id` | JSON number when present |
| `event_name` | `GITHUB_EVENT_NAME` | When set on webhook path |
| `path` | Trigger `comment.path` | Set for `pull_request_review_comment`; empty for `issue_comment` |
| `line` | Trigger `comment.line` or `comment.original_line` | JSON number when present |
| `side` | Trigger `comment.side` | `LEFT` / `RIGHT` when present |
| `diff_hunk` | Trigger `comment.diff_hunk` | Inline hunk text when present |
| `in_reply_to_id` | Trigger `comment.in_reply_to_id` | JSON number when present |
| `comments` | Gathered open human `@mention` comments | Array of `{comment_id, body, path, line, side, diff_hunk, in_reply_to_id, source, actor}` |
| `actor` | comment user or sender login | Informational |

### Comment batching

On `issue_comment` / `pull_request_review_comment` when `GITHUB_REPOSITORY` and a token are available, detect lists PR conversation and review comments, keeps human maintainer comments that contain the mention token, and drops comments that already have an `eyes` reaction (claimed by a prior run). The implementer and verifier must address the full `comments` array. When gather runs and the array is empty, detect skips so queued follow-up runs do not push a false success. Without gather prerequisites, detect falls back to a one-element `comments` array from the trigger fields. Dispatch paths keep a single synthetic entry from explicit feedback.

Hydration reads trigger fields from `GITHUB_EVENT_PATH` when the corresponding `PR_*` env vars are unset. `PR_COMMENTS_JSON` may pre-supply the array (tests / callers).
