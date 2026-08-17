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

### Supported use cases

- `issue_comment` on a PR conversation containing the configured mention (dogfood: `@loop`)
- `pull_request_review_comment` (inline review) with the mention token
- `repository_dispatch` (`loop-github-pr-revise`) or `workflow_dispatch` with explicit `feedback` and `pr_number`

### Out of scope

- Issue triage (axis 1 — see [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md))
- Issue→PR autofix (axis 2 — see [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md))
- L3 auto-merge on stacked fix PRs
- Mention-less triggers (any human comment starts revise)
- Bot-authored comments and acting without the mention token on webhooks
- Auto-resolving review threads (human resolve only)
- Copilot Coding Agent as the maker (LE Agent via `ci-loop-agent` only)
- Comment gather / one-session batching improvements (`#683`)
- Last-run-only discard of earlier fixes on the PR head
- Force-push or `cancel-in-progress` to recover merge conflicts (fail closed on `push_head`)

Skill execution boundaries: `github-pr-revise` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

## Caller inputs

Keys are passed in `on-loop-github-pr-revise.yaml` via `with:` on `ci-loop-caller.yaml`. Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

| Input / JSON key                 | Description                                                           | Dogfood value                                                 |
| -------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------- |
| `ack_trigger_comment`            | Post `eyes` reaction on trigger comment via `ack-trigger`             | `true`                                                        |
| `agent_maker_instructions` | Apply human feedback; address full `result.comments` array            | Inline in caller workflow                                     |
| `agent_maker_max_turns`    | Max maker turns per attempt                                     | `8`                                                           |
| `agent_maker_model`        | Maker model ID                                                  | `cursor-grok-4.5-low`                                         |
| `agent_maker_skill_name`   | Skill package                                                         | `github-pr-revise`                                            |
| `agent_loop_max_attempts`        | Max Agent→Verify cycles                                               | `3`                                                           |
| `agent_checker_instructions`    | APPROVE/REJECT rubric (mention gate, full comment batch)              | Inline in caller workflow                                     |
| `agent_checker_max_turns`       | Max checker turns                                                    | `3`                                                           |
| `agent_checker_model`           | Checker model ID                                                     | `composer-2.5`                                                |
| `agent_checker_skill_name`      | Checker skill                                                         | `loop-verifier`                                               |
| `allowlist`                      | File edit allowlist (empty = skill default)                           | `""`                                                          |
| `branch_match`                   | Fallback integration watch (scoped PR mode drops integration targets) | `main`                                                        |
| `branch_state`                   | `.loop/*` persistence branch                                          | `main`                                                        |
| `budget_max_runs_per_day`        | Daily run cap                                                         | `10`                                                          |
| `budget_max_tokens_per_day`      | Daily token cap                                                       | `1000000`                                                     |
| `delivery`                       | Platform delivery after APPROVE                                       | `open_pr`                                                     |
| `denylist`                       | Denylist globs                                                        | `""`                                                          |
| `detect_script`                  | Domain detect script                                                  | `.agents/skills/github-pr-revise/scripts/detect_pr_revise.sh` |
| `engine`                         | AI engine                                                             | `cursor`                                                      |
| `environment`                    | GitHub Environment for env-scoped secrets                             | `default`                                                     |
| `git_landing_pull_request`       | PR-head landing (`push_head` default; `open_pr` stacked)              | `push_head`                                                   |
| `level`                          | Autonomy (`L2`)                                                       | `L2`                                                          |
| `loop_name`                      | Loop identifier                                                       | `github-pr-revise`                                            |
| `may_edit`                       | Agent worktree edit gate                                              | `true`                                                        |
| `no_changes_verdict`             | Verdict when no file diff                                             | `REJECT`                                                      |
| `pr_enabled`                     | Watch open PR heads (required for PR revise)                          | `true`                                                        |
| `pr_exclude`                     | PR exclusion tokens                                                   | `fork,label:no-loop`                                          |
| `scoped_pr_number`               | Fetch only this PR; drops integration watch                           | From webhook / dispatch / `inputs.pr_number`                  |
| `write_target`                   | Agent artifact type                                                   | `fix`                                                         |

### Domain detect environment (`detect_domain_env_json`)

```yaml
detect_domain_env_json: ${{ format('{{"PR_NUMBER":"{0}","PR_MENTION":"{1}"}}', github.event.pull_request.number || github.event.issue.number || github.event.client_payload.pr_number || inputs.pr_number || '', inputs.mention || '@loop') }}
```

| JSON key / env var | Description                                | Dogfood value                                             |
| ------------------ | ------------------------------------------ | --------------------------------------------------------- |
| `PR_NUMBER`        | Target PR number                           | From event / dispatch / `workflow_dispatch` input         |
| `PR_MENTION`       | Mention token required on comment webhooks | `@loop` (override via `workflow_dispatch.inputs.mention`) |

`scoped_pr_number` scopes `loop-detect` to the webhook PR so comment events do not scan `main`. See [Loop Caller Inputs Reference — Scope](loop-caller-inputs-reference.md#scope-scoped_pr_number).

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

| Stage      | Behavior                                                                                                                                      |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Start ACK  | `eyes` reaction on each gathered `result.comments[].comment_id` (fallback: trigger `comment.id`) via `ack-trigger` when `ack_trigger_comment` |
| Done reply | Inline review: threaded REST reply; conversation comment: follow-up PR comment (`loop-notify-pr`)                                             |
| Marker     | Run-level `loop-notify-pr` marker comment unchanged                                                                                           |
| Resolve    | Human only — no auto-resolve                                                                                                                  |

Detect JSON includes `result.comment_id`, `result.event_name`, inline review fields, and `result.comments` (batched open `@mention` feedback). See [Detect result](#detect-result).

## Concurrency and push_head landing

Same-PR revise runs **serialize**; earlier product fixes must remain on the PR head.

| Rule                 | Behavior                                                                                                                     |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Concurrency group    | `loop-github-pr-revise-<pr_number>` on `on-loop-github-pr-revise.yaml`                                                       |
| `cancel-in-progress` | `false` — do not kill in-flight revise work                                                                                  |
| `queue`              | `max` — queued mentions wait; one worker per PR at a time                                                                    |
| `push_head` landing  | `loop-finalize` `push_target.sh` checks out latest `to.branch`, merges the agent branch with `--no-ff`, pushes without force |
| Conflict             | Merge or non-fast-forward push fails the finalize step (fail closed; no tip overwrite)                                       |

`open_pr` finalize is unchanged. Prefer keeping lost-commit prevention on the shared `push` / `push_head` path rather than force-push or cancel-newest policies.

## Detect result

`detect_pr_revise.sh` emits `result` facts consumed via file-backed detect JSON / loop-detect prompt:

| Field            | Source                                                        | Notes                                                                                                               |
| ---------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `pr_number`      | PR / issue / dispatch payload                                 | Required to proceed                                                                                                 |
| `mention`        | `PR_MENTION` (default `@loop`)                                | Mention gate on comment webhooks                                                                                    |
| `comment_body`   | Trigger `comment.body` or dispatch feedback                   | Backward-compatible scalar for the webhook that started the run                                                     |
| `comment_id`     | Trigger `comment.id`                                          | JSON number when present                                                                                            |
| `event_name`     | `GITHUB_EVENT_NAME`                                           | When set on webhook path                                                                                            |
| `path`           | Trigger `comment.path`                                        | Set for `pull_request_review_comment`; empty for `issue_comment`                                                    |
| `line`           | Trigger `comment.line` or `comment.original_line`             | JSON number when present                                                                                            |
| `start_line`     | Trigger `comment.start_line` or `comment.original_start_line` | JSON number when present (multi-line comments)                                                                      |
| `subject_type`   | Trigger `comment.subject_type`                                | `line` / `file` when present                                                                                        |
| `side`           | Trigger `comment.side`                                        | `LEFT` / `RIGHT` when present                                                                                       |
| `diff_hunk`      | Trigger `comment.diff_hunk`                                   | Inline hunk text when present                                                                                       |
| `in_reply_to_id` | Trigger `comment.in_reply_to_id`                              | JSON number when present                                                                                            |
| `comments`       | Gathered open human `@mention` comments                       | Array of `{comment_id, body, path, line, start_line, side, diff_hunk, in_reply_to_id, source, actor, subject_type}` |
| `actor`          | comment user or sender login                                  | Informational                                                                                                       |

### Comment batching

On `issue_comment` / `pull_request_review_comment` when `GITHUB_REPOSITORY` and a token are available, detect lists PR conversation and review comments, keeps human maintainer comments that contain the mention token, and drops comments that already have an `eyes` reaction (claimed by a prior run). The maker and checker must address the full `comments` array. When gather runs and the array is empty, detect skips so queued follow-up runs do not push a false success. Without gather prerequisites, detect falls back to a one-element `comments` array from the trigger fields. Dispatch paths keep a single synthetic entry from explicit feedback.

Hydration reads trigger fields from `GITHUB_EVENT_PATH` when the corresponding `PR_*` env vars are unset. `PR_COMMENTS_JSON` may pre-supply the array (tests / callers).
