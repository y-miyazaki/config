# PR Revise Workflow Design

Workflow and domain design for the `github-pr-revise` branch / PR-head loop.

| Layer        | Document                                                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                                                       |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (branch / PR-head)                                                |
| Spec         | [Issue Autofix and PR Revise Full Design](../../../superpowers/specs/2026-08-11-issue-autofix-pr-revise-full-design.md)            |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                                           |

**Artifacts:** `on-loop-github-pr-revise.yaml` · skill `github-pr-revise` · `detect_pr_revise.sh` · `ci-loop-caller.yaml`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Single intake for PR revision from human feedback: conversation or review comments containing **`@loop`** + `repository_dispatch` / `workflow_dispatch` → **branch / PR-head** caller (L2, `agent_edit_target: fix`).

Detect skips bots and comments without the mention token. Default delivery: `pr_push` (lands on the PR head); manual dispatch can pick `pr_create` (a new stacked PR). The loop never resolves review threads and never force-pushes.

Behaviors to know:

- An `eyes` reaction on a comment is the claim marker. Detect gathers every human `@loop` comment on the PR that has no `eyes` reaction from anyone, and the ACK step adds `eyes` before the agent runs. A claimed comment is never gathered again, even when the run fails.
- Comment webhooks always use the mention `@loop`. The `workflow_dispatch` input `mention` reaches detect only on `workflow_dispatch`, where the mention gate does not apply, so it changes nothing (see [Unhandled cases](#unhandled-cases)).
- Runs on one PR serialize in the concurrency group `loop-github-pr-revise-<pr_number>`; a queued run gathers the mentions posted while the earlier run was in progress (see [Concurrency and pr_push landing](#concurrency-and-pr_push-landing)).
- Detect-level skips (budget, circuit breaker, pending stacked PR, closed PR, no unclaimed comment) post no reaction and no reply; only the run log records them.
- Thread resolution is not read: a resolved thread's unclaimed `@loop` comment is still gathered.

## Use cases

| Use case                                      | Trigger                                                                                        | Outcome                                                                                          | Transition           |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | -------------------- |
| Apply feedback from a PR conversation comment | `issue_comment` `created` on a PR, containing `@loop`                                          | The fix is merged onto the PR head; a follow-up PR comment reports the result                    | V0 -> V1 -> V2 -> V3 |
| Apply inline review feedback                  | `pull_request_review_comment` `created` containing `@loop`                                     | The fix is merged onto the PR head; a threaded reply reports the result                          | V0 -> V1 -> V2 -> V3 |
| Apply several mentions in one run             | More `@loop` comments arrive while a run for the PR is queued or running                       | The next run addresses every unclaimed comment in one session; later queued runs skip            | V1 -> V2 -> V3       |
| Apply explicit feedback without a comment     | `workflow_dispatch` (`feedback`, `pr_number`) or `repository_dispatch` `loop-github-pr-revise` | Same as a comment, with a single synthetic comment entry and no ACK or thread reply              | V0 -> V1 -> V2 -> V3 |
| Deliver the fix as a stacked PR               | `workflow_dispatch` with `delivery: pr_create`                                                 | A new PR from the PR head carrying `loop-automation`; the original PR is pending until it closes | V0 -> V1 -> V2 -> V4 |

## Out of scope

- Issue triage (axis 1 — see [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md))
- Issue→PR autofix (axis 2 — see [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md))
- L3 auto-merge on stacked fix PRs
- Mention-less triggers (any human comment starts revise)
- Bot-authored comments and acting without the mention token on webhooks
- Auto-resolving review threads (human resolve only)
- Copilot Coding Agent as the maker (LE Agent via `ci-loop-agent` only)
- Comment gather / one-session batching improvements (`#683`)
- Last-run-only discard of earlier fixes on the PR head
- Force-push or `cancel-in-progress` to recover merge conflicts (fail closed on `pr_push`)

Skill execution boundaries: `github-pr-revise` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

## Intake paths

Two paths start this workflow. [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention) holds the shared gating rules.

- **Comment path** (`issue_comment` `created`, `pull_request_review_comment` `created`): handles human feedback on a PR. On a public repository the job `if` admits a comment only when it is on a PR (`issue_comment` needs `issue.pull_request`), its author is not a Bot, its body contains the literal `@loop`, and its `author_association` is MEMBER, OWNER or COLLABORATOR. On a private repository the job `if` admits every PR comment and leaves the bot, mention and association checks to detect.
- **Dispatch path** (`workflow_dispatch`, `repository_dispatch` `loop-github-pr-revise`): handles explicit feedback from a maintainer. The job `if` admits it without a mention. `workflow_dispatch` takes `pr_number`, `feedback` (both required), `delivery` (`type: choice`: `pr_push` default, or `pr_create`) and `mention`. `repository_dispatch` reads `client_payload.pr_number` and `client_payload.feedback` (or `client_payload.comment_body`); nothing in this repository sends it. Detect still skips a Bot sender on this path.

Both paths pass `detect_pr_number`, so `loop-detect` looks only at that PR. `loop-detect` drops the PR when it is not open, comes from a fork, or carries `no-loop` (`detect_pr_denylist: fork,label:no-loop`); draft PRs and Bot-authored PRs are not dropped, because a human chose the PR. A dispatch without a PR number skips with `skip_reason` `pr_number_missing`.

## State model

States for one PR. The platform stores the per-PR state under `pull_request:<pr_number>` in `.loop/state-github-pr-revise.json` (`outcome`, `consecutive_failures`, `pending` for `pr_create`). The claim state of each comment is its `eyes` reaction.

| ID  | State                     | Trigger                                                                                                                             | Next state   |
| --- | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| V0  | Idle                      | No unclaimed `@loop` comment and no run for the PR                                                                                  | V1 / V7      |
| V1  | Queued                    | A mention or a dispatch passes the job `if`; the run waits in the concurrency group `loop-github-pr-revise-<pr_number>`             | V2 / V0 / V6 |
| V2  | Running (claimed)         | Detect proceeds; on the comment path the gathered comments get `eyes`                                                               | V3 / V4 / V5 |
| V3  | Pushed                    | Finalize merges the agent branch onto the PR head (`pr_pushed`); `consecutive_failures` resets to 0                                 | V1 / V7      |
| V4  | Stacked PR pending        | Finalize opens a stacked PR (`pr_created`) and writes `pending`; detect skips the PR with `pending_pr` while the stacked PR is open | V0           |
| V5  | Failed after claim        | The run ends `error` or `rejected`; the claimed comments keep `eyes`; the reply reports the outcome                                 | V1 / V6      |
| V6  | Stopped (circuit breaker) | `consecutive_failures` reaches 3 (`rejected` only); detect skips the PR with `circuit_breaker`                                      | V0           |
| V7  | Closed                    | The PR is closed or merged; detect drops it (`no_changes`)                                                                          | V0           |

Transition `V1 -> V0` is a detect skip: no unclaimed comment, or the trigger comment was edited or deleted. A skip for budget, `pending_pr` or `circuit_breaker` leaves the state as it was and uses `-`.

## User actions

Each row is one action a person can take, the loop response, and what the person sees next. The Transition column references [State model](#state-model).

| User action                                                                                                       | Loop response                                                                                                                                                                                 | Values changed                                                                                                                                                                                     | Result and next action                                                                                                 | Transition           |
| ----------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | -------------------- |
| Post a PR conversation comment containing `@loop` (MEMBER, OWNER or COLLABORATOR)                                 | The comment path runs: detect gathers every unclaimed `@loop` comment, ACK adds `eyes`, the maker applies all of them, the checker verifies, and finalize merges onto the PR head             | `eyes` on each gathered comment; commit on the PR head; marker comment `<!-- loop-notify-pr:v1:github-pr-revise -->` upserted; follow-up PR comment; run-log `pr_pushed`; `consecutive_failures` 0 | Review the pushed commit. To ask for more, post a new `@loop` comment                                                  | V0 -> V1 -> V2 -> V3 |
| Post an inline review comment or reply containing `@loop`                                                         | Same as a conversation comment. For a reply, detect adds the replied-to comment as `parent_body`                                                                                              | Same as a conversation comment, with a threaded reply instead of a follow-up PR comment                                                                                                            | Same as a conversation comment. Resolve the thread yourself                                                            | V0 -> V1 -> V2 -> V3 |
| Post another `@loop` comment while a run for the PR is queued or running                                          | A new run queues behind the current one (`queue: max`, no cancel). The next run to start gathers every unclaimed comment; a later queued run that finds none skips                            | `eyes` when gathered; run-log `skipped` for the empty run                                                                                                                                          | One reply covers all gathered comments; the comment that started the run gets the reply                                | V1 -> V2             |
| Post a PR comment without `@loop`                                                                                 | Public repository: nothing runs (the job `if` refuses it). Private repository: a run queues and detect skips it                                                                               | Private repository only: run-log `skipped`                                                                                                                                                         | Add `@loop` in a new comment to request a revision                                                                     | -                    |
| Edit or delete an unclaimed `@loop` comment before its run starts                                                 | Detect reads the current comments through the API. An edited body is used as edited; a deleted comment, or one whose `@loop` was removed, is not gathered. When nothing is left, detect skips | Run-log `skipped` when nothing is left                                                                                                                                                             | The revision follows the current text                                                                                  | V1 -> V0             |
| Edit a comment to add `@loop`                                                                                     | Nothing runs: the intake events are `created` only. The next `@loop` comment gathers the edited comment, because it has no `eyes`                                                             | None                                                                                                                                                                                               | Post a new `@loop` comment, or start `workflow_dispatch`                                                               | -                    |
| Push to the PR branch while a run is queued or running                                                            | `push_target.sh` fetches the latest PR head and merges the agent branch into it with `--no-ff`, without force. A conflict or a non-fast-forward push fails finalize                           | Success: merge commit on the PR head; run-log `pr_pushed`. Conflict: run-log `error` with a finalize `failure_stage`; the reply reports the error                                                  | On conflict, the claimed comments keep `eyes`. Post a new `@loop` comment that restates the feedback                   | V2 -> V3 / V5        |
| Resolve a review thread by hand                                                                                   | Nothing runs; detect does not read thread resolution                                                                                                                                          | None                                                                                                                                                                                               | An unclaimed `@loop` comment in the thread is still gathered by the next run (see [Unhandled cases](#unhandled-cases)) | -                    |
| Close or merge the PR                                                                                             | A later mention: `loop-detect` drops the PR (`no_changes`). A run already running finishes and pushes to the head branch if it still exists                                                   | Run-log `skipped` for later mentions                                                                                                                                                               | Reopen the PR and post a new `@loop` comment to revise it                                                              | V0 -> V7             |
| Reopen a closed PR and post `@loop`                                                                               | The comment path runs; detect also gathers unclaimed `@loop` comments posted while the PR was closed                                                                                          | Same as a conversation comment                                                                                                                                                                     | Same as a conversation comment                                                                                         | V7 -> V0 -> V1       |
| Delete the PR head branch                                                                                         | GitHub closes the PR, so the loop responds as for a closed PR. A running run fails in `push_target.sh`                                                                                        | Running run: run-log `error`                                                                                                                                                                       | Restore the branch and reopen the PR to continue                                                                       | V0 -> V7             |
| Start `workflow_dispatch` with `pr_number`, `feedback` and `delivery: pr_push`                                    | The dispatch path runs with one synthetic comment entry; no ACK and no thread reply                                                                                                           | Commit on the PR head; marker comment upserted; run-log `pr_pushed`                                                                                                                                | Review the pushed commit                                                                                               | V0 -> V1 -> V2 -> V3 |
| Start `workflow_dispatch` with `delivery: pr_create`                                                              | Finalize opens a new PR from the PR head instead of pushing                                                                                                                                   | Stacked PR with `loop-automation`; state `pending` for `pull_request:<pr_number>`; run-log `pr_created`                                                                                            | Merge or close the stacked PR. Until then, mentions on the original PR skip with `pending_pr`                          | V0 -> V1 -> V2 -> V4 |
| Merge or close the stacked PR                                                                                     | `on-loop-state-promote` clears `pending` (the stacked PR carries `loop-automation`); detect also treats a closed or merged pending PR as stale                                                | `pending` removed; `outcome` `pr_merged` (`consecutive_failures` reset to 0) or `pr_closed`                                                                                                        | Post a new `@loop` comment on the original PR to continue                                                              | V4 -> V0             |
| Start `repository_dispatch` `loop-github-pr-revise` with `client_payload.pr_number` and `client_payload.feedback` | Same as `workflow_dispatch` with `delivery: pr_push`. A sender whose type is Bot (for example a GitHub App token) is skipped                                                                  | Same as `workflow_dispatch`; run-log `skipped` for a Bot sender                                                                                                                                    | Send it with a user token                                                                                              | V0 -> V1 -> V2 -> V3 |
| Re-run a failed comment-path run from the Actions page                                                            | The run repeats with the original event. The comments it claimed already have `eyes`, so gather finds none and detect skips                                                                   | Run-log `skipped`                                                                                                                                                                                  | Post a new `@loop` comment that restates the feedback, or start `workflow_dispatch`                                    | V5 -> V1 -> V0       |
| Add the label `no-loop` to the PR                                                                                 | Later mentions: `loop-detect` drops the PR (`no_changes`)                                                                                                                                     | Run-log `skipped`                                                                                                                                                                                  | Remove `no-loop` and post a new `@loop` comment to resume                                                              | -                    |
| Add your own `eyes` reaction to an `@loop` comment                                                                | Detect treats the comment as claimed and does not gather it (see [Unhandled cases](#unhandled-cases))                                                                                         | None                                                                                                                                                                                               | Remove your reaction before the next run                                                                               | -                    |
| The checker rejects three runs in a row on the PR                                                                 | Detect skips every later mention on the PR with `circuit_breaker`; no reaction or reply                                                                                                       | `outcome` `rejected`; `consecutive_failures` 3 for `pull_request:<pr_number>`; run-log `skipped`, `skip_reason` `circuit_breaker`                                                                  | Remove the key from `.loop/state-github-pr-revise.json` by PR, or wait for the 30-day prune                            | V5 -> V6             |
| Remove the key `pull_request:<pr_number>` from `.loop/state-github-pr-revise.json` by PR                          | Nothing runs on merge. The next mention treats the PR as new                                                                                                                                  | Key removed                                                                                                                                                                                        | Post a new `@loop` comment                                                                                             | V6 -> V0             |
| Change `.loop/loop-budget.json` or the caller inputs by PR after a failure                                        | Nothing runs on merge. The next mention or dispatch uses the new values                                                                                                                       | `.loop/loop-budget.json` caps (they override caller `budget_*`); caller inputs                                                                                                                     | Post a new `@loop` comment                                                                                             | -                    |
| Do nothing after a pushed fix                                                                                     | Nothing runs; claimed comments stay claimed                                                                                                                                                   | None                                                                                                                                                                                               | -                                                                                                                      | -                    |
| Comments and reactions that the loop or other bots post (GitHub App token)                                        | Public repository: nothing runs; the job `if` refuses Bot comment authors. Private repository: a run queues and detect skips the Bot author                                                   | Private repository only: run-log `skipped`                                                                                                                                                         | Bot comments, such as an earlier review finding, are context only; reply with `@loop` to act on one                    | -                    |

Not applicable: 5 — the loop reads no Issue; PR close and reopen are covered as rows.

## Unhandled cases

| Case                                                                                                | Why nothing follows                                                                                                                                                                                                                                          | Disposition |
| --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------- |
| A detect-level skip (budget, `circuit_breaker`, `pending_pr`, closed PR) on a human `@loop` comment | ACK and the reply run only when detect proceeds, so the comment gets no reaction and no reply. The person cannot tell the comment was seen; only the run log records the skip                                                                                | Follow-up   |
| The workflow_dispatch input `mention` is set                                                        | The input reaches `PR_MENTION` only on `workflow_dispatch`, where the mention gate does not apply; comment webhooks always use `@loop` (the job `if` literal and the `PR_MENTION` default). The input has no effect                                          | Follow-up   |
| A person resolves a thread whose `@loop` comment is not yet claimed                                 | Gather selects comments by the `eyes` reaction, not by thread resolution, so the next run still applies the resolved request                                                                                                                                 | Follow-up   |
| Anyone adds an `eyes` reaction to an `@loop` comment                                                | Gather counts any `eyes` reaction (`reactions.eyes`), not only the loop's own, so the comment is silently never gathered; when it is the trigger comment, the run skips                                                                                      | Follow-up   |
| The ACK step fails for a gathered comment                                                           | ACK is `continue-on-error` and only warns, so the comment stays unclaimed and the next run gathers and applies it again                                                                                                                                      | Follow-up   |
| Private repository: every PR comment, including the loop's own replies, queues a run                | The job `if` admits all comments on a private repository, so refused classes (Bot authors, no mention) occupy the concurrency queue and each writes a run-log `skipped` row, against invariant 9 in [Loop Engineering Design](../loop-engineering-design.md) | Follow-up   |
| A run fails after ACK (agent error, checker REJECT, conflict)                                       | The claimed comments keep `eyes` and are never gathered again. The reply reports the outcome; the person restates the feedback in a new `@loop` comment                                                                                                      | Accepted    |
| A comment contains `@loop` as part of a longer word (for example `@loopy`)                          | The job `if` uses a substring match, so the run queues; detect uses a word-boundary match and skips it                                                                                                                                                       | Accepted    |
| A person edits a claimed comment                                                                    | Edits are not intake events and claimed comments are not gathered again. The person posts a new `@loop` comment                                                                                                                                              | Accepted    |
| A user without MEMBER, OWNER or COLLABORATOR role mentions `@loop`                                  | Comments are untrusted input. The job `if` (public) and detect refuse the author; a maintainer restates the request                                                                                                                                          | Accepted    |
| A Bot sender on the dispatch path                                                                   | Bot refusal applies on every path so no automation chains revise runs; the skill forbids agent-initiated dispatch                                                                                                                                            | Accepted    |
| A run starts on a PR from a fork                                                                    | `detect_pr_denylist` drops fork PRs; the loop cannot push to a fork head                                                                                                                                                                                     | Accepted    |

## Failure and recovery

| Failure kind                                             | How it is recorded                                                                                             | Who acts   | What they do                                             | How the loop resumes                                                                                      |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Checker rejects, or the maker changes nothing            | Run-log `rejected` (`agent_unchanged_verdict: REJECT`); `consecutive_failures` +1; the reply shows the reason  | Maintainer | Read the reason; restate or narrow the feedback          | A new `@loop` comment (V5 -> V1)                                                                          |
| Three rejections in a row                                | `consecutive_failures` 3; detect skips with `circuit_breaker`; no reaction or reply                            | Maintainer | Fix the cause                                            | Remove the key `pull_request:<pr_number>` by PR, or wait for the 30-day prune of terminal keys (V6 -> V0) |
| Agent job fails                                          | Run-log `error`, `failure_stage` from the agent; `consecutive_failures` unchanged; the reply reports the error | Maintainer | Fix the cause                                            | A new `@loop` comment, or `workflow_dispatch`                                                             |
| Merge conflict or non-fast-forward push on `pr_push`     | Finalize fails closed (no force-push); run-log `error`; the PR head is unchanged                               | PR author  | Resolve the conflict on the PR branch                    | A new `@loop` comment that restates the feedback                                                          |
| Detect fails (comment list API error, invalid PR number) | Detect `status: error`; the `detect` job fails; no ACK                                                         | Maintainer | Check the API error                                      | Comments stay unclaimed; the next `@loop` comment gathers them                                            |
| Daily budget used up                                     | Run-log `skipped`, `skip_reason` `budget`; no reaction or reply                                                | Maintainer | Wait, or raise the cap in `.loop/loop-budget.json` by PR | Comments stay unclaimed; the next `@loop` comment on a later day gathers them                             |
| Notification fails                                       | `loop-notify-pr` warns only (`continue-on-error`)                                                              | Maintainer | Check the run                                            | Nothing to resume; the push already landed                                                                |

## Caller inputs

Keys are passed in `on-loop-github-pr-revise.yaml` via `with:` on `ci-loop-caller.yaml`. Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

| Input / JSON key             | Description                                                                                                       | Dogfood value                                                                                                           |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it                                    | `medium`                                                                                                                |
| `agent_checker_instructions` | APPROVE/REJECT rubric (mention gate, full comment batch)                                                          | Inline in caller workflow                                                                                               |
| `agent_checker_max_turns`    | Max checker turns                                                                                                 | `100`                                                                                                                   |
| `agent_checker_model`        | Checker model ID                                                                                                  | `claude-opus-5`                                                                                                         |
| `agent_checker_skill_name`   | Checker skill                                                                                                     | `loop-verifier`                                                                                                         |
| `agent_edit_allowlist`       | File edit allowlist (`**` = unrestricted)                                                                         | `**`                                                                                                                    |
| `agent_edit_target`          | Agent artifact type                                                                                               | `fix`                                                                                                                   |
| `agent_engine`               | AI engine                                                                                                         | `claude`                                                                                                                |
| `agent_loop_max_attempts`    | Max Agent→Verify cycles                                                                                           | `3`                                                                                                                     |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it                                      | `medium`                                                                                                                |
| `agent_maker_instructions`   | Apply human feedback; address full `result.comments` array                                                        | Inline in caller workflow                                                                                               |
| `agent_maker_max_turns`      | Max maker turns per attempt                                                                                       | `100`                                                                                                                   |
| `agent_maker_model`          | Maker model ID                                                                                                    | `claude-sonnet-5`                                                                                                       |
| `agent_maker_skill_name`     | Skill package                                                                                                     | `github-pr-revise`                                                                                                      |
| `agent_tool_allowlist`       | Tool permission rules for the maker (read PR and diff, run validation scripts; the workflow posts, not the agent) | `gh api -X GET`, `gh pr view`, `gh pr diff`, `validate.sh` of github-actions, go, markdown, and shell-script validation |
| `agent_unchanged_verdict`    | Verdict when no file diff                                                                                         | `REJECT`                                                                                                                |
| `budget_max_runs_per_day`    | Daily run cap                                                                                                     | `10`                                                                                                                    |
| `budget_max_tokens_per_day`  | Daily token cap                                                                                                   | `1000000`                                                                                                               |
| `delivery`                   | Where the output is delivered: `pr_push` (PR head) or `pr_create` (new PR)                                        | `${{ inputs.delivery \|\| 'pr_push' }}`                                                                                 |
| `detect_pr_denylist`         | PR exclusion tokens                                                                                               | `fork,label:no-loop`                                                                                                    |
| `detect_pr_enabled`          | Watch open PR heads (required for `pr_push`)                                                                      | `true`                                                                                                                  |
| `detect_pr_number`           | Fetch only this PR; drops integration watch. `0` = unset (`pr_push` then skips with `pr_number_missing`)          | From webhook / dispatch / `inputs.pr_number`, else `0`                                                                  |
| `detect_script`              | Domain detect script                                                                                              | `.agents/skills/github-pr-revise/scripts/detect_pr_revise.sh`                                                           |
| `environment`                | GitHub Environment for env-scoped secrets                                                                         | `default`                                                                                                               |
| `level`                      | Autonomy (`L2`)                                                                                                   | `L2`                                                                                                                    |
| `loop_name`                  | Loop identifier                                                                                                   | `github-pr-revise`                                                                                                      |
| `state_branch`               | `.loop/*` persistence branch                                                                                      | `main`                                                                                                                  |
| `trigger_comment_ack`        | Post `eyes` reaction on trigger comment via `ack-trigger`                                                         | `true`                                                                                                                  |

### Domain detect environment (`detect_env_json`)

```yaml
detect_env_json: ${{ format('{{"PR_NUMBER":"{0}","PR_MENTION":"{1}"}}', github.event.pull_request.number || github.event.issue.number || github.event.client_payload.pr_number || inputs.pr_number || '', inputs.mention || '@loop') }}
```

| JSON key / env var | Description                                | Dogfood value                                                                                                                         |
| ------------------ | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| `PR_NUMBER`        | Target PR number                           | From event / dispatch / `workflow_dispatch` input                                                                                     |
| `PR_MENTION`       | Mention token required on comment webhooks | `@loop`. `workflow_dispatch.inputs.mention` sets it only on `workflow_dispatch`, which bypasses the mention gate, so it has no effect |

`detect_pr_number` scopes `loop-detect` to the webhook PR so comment events do not scan `main`. See [Loop Caller Inputs Reference — Scope](loop-caller-inputs-reference.md#scope-detect_pr_number).

## Caller shape

```text
on-loop-github-pr-revise.yaml
  loop → uses ci-loop-caller.yaml
           detect  → detect_pr_revise.sh
           ack-trigger (optional) → eyes reaction on trigger comment
           execute → ci-loop-agent (level L2)
           finalize → pr_push (default) or pr_create
           record-skip → budget | circuit_breaker | pending_pr | no_changes | pr_number_missing
```

`issue_comment` jobs run only when `github.event.issue.pull_request` is set.

## Detect contract

`detect_pr_revise.sh` skips when the PR number is missing, the actor is a Bot, or the actor's `author_association` is set and is not MEMBER, OWNER or COLLABORATOR. On comment webhooks it skips when the trigger body lacks the mention token (word-boundary match); on dispatch paths it skips when the feedback is empty. It then resolves `result.comments` (see [Comment batching](#comment-batching)) and skips when gather ran and found no unclaimed comment. A failed comment list call emits `status: error` and exits 1.

### Detect result

`detect_pr_revise.sh` emits `result` facts consumed via file-backed detect JSON / loop-detect prompt:

| Field            | Source                                                        | Notes                                                                                                                                                       |
| ---------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pr_number`      | PR / issue / dispatch payload                                 | Required to proceed                                                                                                                                         |
| `mention`        | `PR_MENTION` (default `@loop`)                                | Mention gate on comment webhooks                                                                                                                            |
| `comment_body`   | Trigger `comment.body` or dispatch feedback                   | Backward-compatible scalar for the webhook that started the run                                                                                             |
| `comment_id`     | Trigger `comment.id`                                          | JSON number when present                                                                                                                                    |
| `event_name`     | `GITHUB_EVENT_NAME`                                           | When set on webhook path                                                                                                                                    |
| `path`           | Trigger `comment.path`                                        | Set for `pull_request_review_comment`; empty for `issue_comment`                                                                                            |
| `line`           | Trigger `comment.line` or `comment.original_line`             | JSON number when present                                                                                                                                    |
| `start_line`     | Trigger `comment.start_line` or `comment.original_start_line` | JSON number when present (multi-line comments)                                                                                                              |
| `subject_type`   | Trigger `comment.subject_type`                                | `line` / `file` when present                                                                                                                                |
| `side`           | Trigger `comment.side`                                        | `LEFT` / `RIGHT` when present                                                                                                                               |
| `diff_hunk`      | Trigger `comment.diff_hunk`                                   | Inline hunk text when present                                                                                                                               |
| `in_reply_to_id` | Trigger `comment.in_reply_to_id`                              | JSON number when present                                                                                                                                    |
| `comments`       | Gathered unclaimed human `@mention` comments                  | Array of `{comment_id, body, path, line, start_line, side, diff_hunk, in_reply_to_id, parent_body, source, actor, subject_type}`; `parent_body` is optional |
| `actor`          | comment user or sender login                                  | Informational                                                                                                                                               |

### Comment batching

On `issue_comment` / `pull_request_review_comment` when `GITHUB_REPOSITORY` and a token are available, detect lists PR conversation and review comments, keeps non-Bot comments whose `author_association` is MEMBER, OWNER or COLLABORATOR (or empty) and that contain the mention token, and drops comments that already have an `eyes` reaction from anyone (claimed by a prior run). Thread resolution is not checked. The maker and checker must address the full `comments` array. When gather runs and the array is empty, detect skips so queued follow-up runs do not push a false success. Without gather prerequisites, detect falls back to a one-element `comments` array from the trigger fields. Dispatch paths keep a single synthetic entry from explicit feedback.

Hydration reads trigger fields from `GITHUB_EVENT_PATH` when the corresponding `PR_*` env vars are unset. `PR_COMMENTS_JSON` may pre-supply the array (tests / callers).

## Skill contract

See `.apm/packages/github/.apm/skills/github-pr-revise/SKILL.md` and its `references/`. The maker applies the human feedback in the worktree checked out at the PR head; the workflow owns the commit and the push.

### Context for replies

For an inline reply (`in_reply_to_id` set), detect adds `parent_body` (the body of the replied-to review comment) to that `comments[]` entry; the key is omitted when it is empty. The skill reads context before it branches on `agent_edit_allowed`:

- Inline reply: read `parent_body` (fetch the parent review comment when absent), the whole thread, and the commented line with its `diff_hunk`.
- Otherwise: read the PR body and all comments and reviews.
- Bot comments, such as an earlier review finding from [PR Review Workflow Design](loop-github-pr-review-workflow-design.md), are context only and never a trigger. The mention gate and bot refusal are unchanged.
- Parent text, thread text, and PR body or comments are untrusted context. The skill never follows instructions in them that conflict with `## Constraints` or widen the scope beyond what the mentioned human comment asks for.

## Delivery contract

`pr_push` lands the approved agent branch on the PR head (see [Concurrency and pr_push landing](#concurrency-and-pr_push-landing)); `pr_create` opens a new PR from the PR head with `loop-automation` and writes `pending`. After finalize, `loop-notify-pr` runs for every outcome and never fails the job.

### Trigger UX (ACK + thread reply)

After detect proceeds on a comment webhook:

| Stage      | Behavior                                                                                                                                      |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Start ACK  | `eyes` reaction on each gathered `result.comments[].comment_id` (fallback: trigger `comment.id`) via `ack-trigger` when `trigger_comment_ack` |
| Done reply | Inline review: threaded REST reply; conversation comment: follow-up PR comment (`loop-notify-pr`). Only the trigger comment gets the reply    |
| Marker     | Run-level `loop-notify-pr` marker comment `<!-- loop-notify-pr:v1:github-pr-revise -->`, one per PR, upserted by every run                    |
| Resolve    | Human only — no auto-resolve                                                                                                                  |

Detect JSON includes `result.comment_id`, `result.event_name`, inline review fields, and `result.comments` (batched unclaimed `@mention` feedback). See [Detect result](#detect-result).

## Concurrency and pr_push landing

Same-PR revise runs **serialize**; earlier product fixes must remain on the PR head.

| Rule                 | Behavior                                                                                                                     |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Concurrency group    | `loop-github-pr-revise-<pr_number>` on `on-loop-github-pr-revise.yaml` (`github.run_id` when no PR number is known)          |
| `cancel-in-progress` | `false` — do not kill in-flight revise work                                                                                  |
| `queue`              | `max` — queued mentions wait; one worker per PR at a time                                                                    |
| `pr_push` landing    | `loop-finalize` `push_target.sh` checks out latest `to.branch`, merges the agent branch with `--no-ff`, pushes without force |
| Conflict             | Merge or non-fast-forward push fails the finalize step (fail closed; no tip overwrite)                                       |

`pr_create` finalize is unchanged. Prefer keeping lost-commit prevention on the `pr_push` path rather than force-push or cancel-newest policies.

## Implementation Checklist

- [ ] Keep the `@loop` literal in the job `if` equal to the `PR_MENTION` default in `detect_env_json`.
- [ ] Keep the job `if` refusing every class detect refuses (Bot author, missing mention, untrusted association) on public repositories.
- [ ] Ship `pr_push` landing changes with `push_target.bats` and a `ci-loop-agent.yaml` pin bump (`.github/workflows/CLAUDE.md`).

## References

- [Loop Engineering Design](../loop-engineering-design.md)
- [Loop Caller Reusable Design](../loop-caller-reusable-design.md)
- [Loop Caller Inputs Reference](loop-caller-inputs-reference.md)
- [PR Review Workflow Design](loop-github-pr-review-workflow-design.md)
- [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md)
