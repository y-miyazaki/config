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
           execute → ci-loop-agent (may_edit=true)
           finalize → push_head (default) or open_pr
```

`issue_comment` jobs run only when `github.event.issue.pull_request` is set.

## Trigger UX (ACK + thread reply)

After detect proceeds on a comment webhook:

| Stage | Behavior |
| ----- | -------- |
| Start ACK | `eyes` reaction on `comment.id` (`ci-loop-caller`) |
| Done reply | Inline review: threaded REST reply; conversation comment: follow-up PR comment (`loop-notify-pr`) |
| Marker | Run-level `loop-notify-pr` marker comment unchanged |
| Resolve | Human only — no auto-resolve |

Detect JSON includes `result.comment_id` and `result.event_name` when hydrated from the webhook.

