# PR Review Workflow Design

Workflow and domain design for the `github-pr-review` entity loop.

| Layer        | Document                                                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                                                       |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (entity)                                                          |
| Spec         | [Loop `github-pr-review` 設計: PR 初回レビューの自動化](../../../superpowers/specs/2026-10-17-loop-pr-review-design.md)            |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                                           |

**Artifacts:** `on-loop-github-pr-review.yaml` · skill `github-pr-review` · `detect_pr_review.sh` · `render_review.sh` · `ci-loop-caller-entity.yaml`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md) (entity subset).

## Purpose

Review a pull request once when it is opened or marked ready, and post the result as a single `COMMENT` pull request review (L2). The agent only writes a JSON report; after the checker approves, the trusted script `render_review.sh` renders it into `review.json`, and `loop-finalize` (Deliver Message) posts it once. The loop never approves, requests changes, or edits source files.

Behaviors to know:

- The only stored state is the posted review: a Bot-authored review whose body carries `<!-- github-pr-review:v1 -->`. Detect skips a PR that has one, unless `workflow_dispatch` sets `force`.
- `pull_request_target` intake is `opened` and `ready_for_review` only. A push (`synchronize`), a reopen, or a review request starts nothing.
- A run that ends without a review (agent error, `REJECT`, render failure, a push during the run, or a budget skip) leaves nothing on the PR; only the run log records it. The entity caller posts no `loop-notify-pr` comment.
- A human `@loop` reply on a review finding starts [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md), not this loop.

## Use cases

| Use case                           | Trigger                                                | Outcome                                                     | Transition     |
| ---------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------- | -------------- |
| Review a newly opened PR           | `pull_request_target` `opened` (non-draft)             | One `COMMENT` review with inline comments and the marker    | W0 -> W1 -> W2 |
| Review a draft PR when it is ready | `pull_request_target` `ready_for_review`               | One `COMMENT` review, unless a marker review already exists | W4 -> W1 -> W2 |
| Review a PR on demand              | `workflow_dispatch` with `pr_number`                   | One `COMMENT` review for a PR without a marker review       | W3 -> W1 -> W2 |
| Review a PR again                  | `workflow_dispatch` with `pr_number` and `force: true` | A second `COMMENT` review against the current head          | W2 -> W1 -> W2 |

## Out of scope

- Fixing the PR from review feedback (see [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md))
- Approving or requesting changes (the posted event is always `COMMENT`)
- Re-review on every push, fork PRs, draft PRs, and bot-authored PRs
- Issue triage and autofix (see [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md) and [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md))

## Intake paths

Two paths start this workflow. [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention) holds the shared gating rules.

- **Webhook path** (`pull_request_target` `opened`, `ready_for_review`): the job `if` admits a PR that is not a draft, whose head repository is this repository, whose author is not a Bot, and that carries neither `no-loop` nor `loop-automation`. The checks read the event payload, so labels added after the event are not seen.
- **Manual path** (`workflow_dispatch` with `pr_number`, optional `force`): the job `if` admits every dispatch; detect applies the same conditions from `gh pr view`. Run it from the default branch only (see [Rollout](#rollout)).

Both paths share the concurrency group `loop-github-pr-review-<pr_number>` (`cancel-in-progress: false`, `queue: max`).

### Rollout

The caller ships with the `pull_request_target` trigger enabled; the `ci-loop-*` pins already include the fixes below.

Do not dispatch or enable the workflow until a release that contains all of the following platform fixes is pinned in the `ci-loop-*` `uses:` lines of the caller chain (`ci-loop-caller-entity.yaml` → `ci-loop-agent.yaml` → `loop-*` actions):

| Fix        | Change                                                                                                                                        |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| P1, P2, P4 | `loop-finalize` never pushes for `delivery: none`, deletes the agent branch, and passes `GH_TOKEN` / `GITHUB_REPOSITORY` to `finalize_script` |
| B2         | `loop-finalize` (and `render_review.sh`) always runs at L2/L3; the `finalize_enabled` flag no longer exists                                   |
| Deliver    | `loop-finalize` accepts `delivery: pr_review` and `finalize_script`, and Deliver Message posts the review                                     |
| B3         | `loop-entity-detect` emits `target_json.from.branch`, which `ci-loop-agent` uses as the worktree base branch                                  |
| Meta guard | The `finalize-l2` PR review Meta step acts only on `entity:pr:<n>` handoff keys, before it sources any library, and cannot fail the job       |

With older pins, an APPROVE verdict can merge the agent branch, including `.loop-review/pr-<n>.json`, into the base branch, or the review is never posted (see [Finalize with `delivery: pr_review`](#finalize-with-delivery-pr_review)).

| Stage               | Action                                                                                                                                                      |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Before the pin bump | Do not run the workflow with older pins; the fixes in [Rollout](#rollout) must be in the pinned release                                                     |
| After the pin bump  | The trigger is enabled and `zizmor` covers it; do not downgrade the pins                                                                                    |
| Manual dispatch     | Run `workflow_dispatch` from the default branch only; the base checkout, the rules read at base, and `render_review.sh` come from the ref the run starts on |
| Intake gate         | `jobs.loop.if` covers both events                                                                                                                           |

## State model

States for one PR. No state file holds them: the Bot-authored marker review is the only stored state, and the run log records each outcome.

| ID  | State                        | Trigger                                                                                                                  | Next state   |
| --- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------ |
| W0  | Opened, not reviewed         | A person opens a PR                                                                                                      | W1 / W4 / W5 |
| W1  | Review run queued or running | `opened`, `ready_for_review` or `workflow_dispatch` passes the job `if` and waits in `loop-github-pr-review-<pr_number>` | W2 / W3      |
| W2  | Reviewed                     | Deliver Message posts the marker review (run-log `pr_reviewed`)                                                          | W1 / W4 / W6 |
| W3  | Run ended without a review   | Agent error, `REJECT`, `unchanged` (render wrote no file), delivery failure, or a budget skip                            | W1 / W4 / W6 |
| W4  | Draft                        | The PR is opened as a draft or converted to draft                                                                        | W1           |
| W5  | Excluded                     | The PR comes from a fork, has a Bot author, or carries `no-loop` or `loop-automation`                                    | W1           |
| W6  | Closed or merged             | A person closes or merges the PR                                                                                         | W2 / W3      |

`W5 -> W1` needs a person to remove the label and start `workflow_dispatch`; fork and Bot-author PRs stay in W5. `W6 -> W2 / W3` is a reopen, which starts no run and returns the PR to the state it had.

## User actions

Each row is one action a person can take, the loop response, and what the person sees next. The Transition column references [State model](#state-model).

| User action                                                                     | Loop response                                                                                                                                                             | Values changed                                                                                                                                             | Result and next action                                                                                                   | Transition     |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | -------------- |
| Open a non-draft PR from a branch in this repository                            | The Webhook path reviews it: the maker writes the report, the checker verifies, `render_review.sh` renders it, and Deliver Message posts one `COMMENT` review             | Review with `<!-- github-pr-review:v1 -->`, Meta and footer; inline comments; run-log `pr_reviewed`; concurrency group `loop-github-pr-review-<pr_number>` | Read the findings. To have the loop fix one, reply to it with `@loop`                                                    | W0 -> W1 -> W2 |
| Open a draft PR                                                                 | Nothing runs; the job `if` refuses drafts                                                                                                                                 | None                                                                                                                                                       | Mark the PR ready for review when it is ready                                                                            | W0 -> W4       |
| Mark a draft PR ready for review                                                | The Webhook path runs. Detect skips when a marker review already exists                                                                                                   | First time: as for an opened PR. Already reviewed: run-log `skipped`, `skip_reason` `domain:detect` (the detect message is in `skip_detail`)               | First time: read the findings. Already reviewed: start `workflow_dispatch` with `force: true` to review the current head | W4 -> W1 -> W2 |
| Convert a PR to draft                                                           | Nothing runs; `converted_to_draft` is not an intake event                                                                                                                 | None                                                                                                                                                       | The existing review stays                                                                                                | W2 -> W4       |
| Push to the PR branch while a review run is queued or running                   | `render_review.sh` compares the report `head_sha` with the PR head, warns, and writes no file, so nothing is posted                                                       | Run-log `unchanged`; no review                                                                                                                             | The PR shows no review. Start `workflow_dispatch` with the PR number (see [Unhandled cases](#unhandled-cases))           | W1 -> W3       |
| Start `workflow_dispatch` with `pr_number` (no `force`)                         | Detect reads the PR facts through `gh pr view` and skips when a marker review exists or the PR is a draft, a fork, Bot-authored, or labeled `no-loop` / `loop-automation` | As for an opened PR, or run-log `skipped` (`domain:detect`, message in `skip_detail`)                                                                      | Read the findings                                                                                                        | W3 -> W1 -> W2 |
| Start `workflow_dispatch` with `pr_number` and `force: true`                    | Detect ignores the existing marker review and the loop reviews the current head                                                                                           | A second marker review; run-log `pr_reviewed`                                                                                                              | Read the new review; the earlier review stays                                                                            | W2 -> W1 -> W2 |
| Reply to a review finding with `@loop` (MEMBER, OWNER or COLLABORATOR)          | Nothing runs in this loop. [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md) runs and reads the finding as `parent_body`                              | None in this loop                                                                                                                                          | Review the commit that pr-revise pushes                                                                                  | -              |
| Reply to a review finding without `@loop`                                       | Nothing runs in either loop                                                                                                                                               | None                                                                                                                                                       | Add `@loop` in a new reply to ask for a fix                                                                              | -              |
| Close or merge the PR                                                           | Nothing runs. A run that is already queued or running still posts its review, because detect does not check the PR state                                                  | None (or the review from the in-flight run)                                                                                                                | -                                                                                                                        | W2 -> W6       |
| Add `no-loop` or `loop-automation` to the PR                                    | Later dispatches skip. A run already queued uses the labels from its event payload                                                                                        | Label only                                                                                                                                                 | Remove the label and start `workflow_dispatch` to review                                                                 | W0 -> W5       |
| Re-run a failed run from the Actions page                                       | The run repeats with the original event. Detect checks the marker review again, and `render_review.sh` drops the review when the PR head has moved                        | A new run-log row                                                                                                                                          | When the head moved, start `workflow_dispatch` instead                                                                   | W3 -> W1 -> W2 |
| Change `.loop/loop-budget.json` or the caller inputs by PR after a failure      | Nothing runs on merge. The next event or dispatch uses the new values                                                                                                     | `.loop/loop-budget.json` caps (they override caller `budget_*`); caller inputs                                                                             | Start `workflow_dispatch` for the PR that was not reviewed                                                               | -              |
| Do nothing after the review                                                     | Nothing runs                                                                                                                                                              | None                                                                                                                                                       | The review stays as posted                                                                                               | -              |
| PRs, reviews and comments that the loop or other bots create (GitHub App token) | Nothing runs: the job `if` refuses Bot-authored PRs and PRs with `loop-automation`, and posting a review raises no `opened` or `ready_for_review` event                   | None                                                                                                                                                       | The review's inline comments are Bot comments, which pr-revise also refuses as triggers                                  | -              |

Not applicable: 3, 4, 5 — the loop uses no mention token (an `@loop` reply belongs to pr-revise, as in the reply row), opens no PR and keeps no branch a person can act on, and reads no Issue.

## Unhandled cases

| Case                                                                                                                      | Why nothing follows                                                                                                                                                                                                             | Disposition |
| ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| A run ends without a review (agent error, `REJECT`, render failure, a push during the run, delivery failure, budget skip) | No comment or status on the PR tells the person, and `opened` fires once, so the PR is never reviewed unless someone checks the Actions run and dispatches. A push soon after opening a PR is common and drops the whole review | Follow-up   |
| A person pushes new commits (`synchronize`) and wants a new review                                                        | Re-review on every push is out of scope. The person starts `workflow_dispatch` with `force: true`                                                                                                                               | Accepted    |
| A person reopens a PR                                                                                                     | `reopened` is not an intake event; a PR that was never reviewed stays unreviewed. The person starts `workflow_dispatch`                                                                                                         | Accepted    |
| A person requests a review again (`review_requested`)                                                                     | Not an intake event; the loop is not a requestable reviewer. The person starts `workflow_dispatch` with `force: true`                                                                                                           | Accepted    |
| A person resolves a review thread from the loop                                                                           | The review is a `COMMENT` with no state to update; nothing reads thread resolution                                                                                                                                              | Accepted    |
| A person edits the PR title or body                                                                                       | Not an intake event; the review reads the PR body only when it runs                                                                                                                                                             | Accepted    |
| A run posts its review after the PR was closed or merged, or a dispatch names a closed PR                                 | Detect does not check the PR state. The extra review is harmless, and a dispatch is an explicit choice                                                                                                                          | Accepted    |
| A person pastes the marker into their own review                                                                          | Only a Bot-authored review counts, so a human cannot suppress the review                                                                                                                                                        | Accepted    |
| A PR from a fork or by a Bot author                                                                                       | The head is never trusted under `pull_request_target`; Bot PRs (loop and dependency PRs) are out of scope                                                                                                                       | Accepted    |
| A person dispatches from a branch other than the default branch                                                           | The base checkout, the rules, and `render_review.sh` come from that ref; nothing enforces the default branch. Only a person who can already push workflow changes can dispatch                                                  | Accepted    |
| GitHub accepts or rejects a stale `commit_id` for inline comments                                                         | Unverified. A rejection (HTTP 422) posts `fallback_body`                                                                                                                                                                        | Limitation  |

## Failure and recovery

| Failure kind                                                            | How it is recorded                                                                                       | Who acts   | What they do                                                     | How the loop resumes                                        |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------- | ----------------------------------------------------------- |
| Agent job fails                                                         | Run-log `error`, `failure_stage` from the agent; no review                                               | Maintainer | Fix the cause                                                    | Start `workflow_dispatch` (W3 -> W1)                        |
| Checker rejects, or the maker writes no report                          | Run-log `rejected` (`agent_unchanged_verdict: REJECT`); no review                                        | Maintainer | Check the reason; adjust the maker or checker instructions by PR | Start `workflow_dispatch`                                   |
| Render writes no file (PR head moved, invalid report, unavailable SHAs) | `::warning::render_review` in the finalize log; run-log `unchanged`                                      | Maintainer | Check the warning                                                | Start `workflow_dispatch`                                   |
| Delivery fails (HTTP error other than an inline 422)                    | The finalize step fails; run-log `error`, `failure_stage` `deliver_message`; the agent branch is deleted | Maintainer | Fix the token or API problem                                     | Start `workflow_dispatch`                                   |
| Inline comments rejected (HTTP 422)                                     | Delivery retries once with `fallback_body`; run-log `pr_reviewed`                                        | -          | -                                                                | Not a failure; the review is posted without inline comments |
| Detect fails (API error, missing PR facts)                              | Detect `status: error`; the `detect` job fails                                                           | Maintainer | Check the API error                                              | Start `workflow_dispatch`                                   |
| Daily budget used up                                                    | Run-log `skipped`, `skip_reason` `budget`                                                                | Maintainer | Wait, or raise the cap in `.loop/loop-budget.json` by PR         | Start `workflow_dispatch` the next day                      |

## Caller inputs

Keys are passed in `on-loop-github-pr-review.yaml` via `with:` on `ci-loop-caller-entity.yaml`. Entity subset of [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

| Input / JSON key             | Description                                                                    | Dogfood value                                                               |
| ---------------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it | `medium`                                                                    |
| `agent_checker_instructions` | APPROVE/REJECT rubric (evidence kinds, in-diff lines, base-read evidence)      | Inline in caller workflow                                                   |
| `agent_checker_max_turns`    | Max checker turns                                                              | `100`                                                                       |
| `agent_checker_model`        | Checker model ID                                                               | `claude-opus-5`                                                             |
| `agent_checker_skill_name`   | Checker skill                                                                  | `loop-verifier`                                                             |
| `agent_edit_allowlist`       | File edit allowlist (`**` = unrestricted)                                      | `**`                                                                        |
| `agent_edit_target`          | Agent artifact type (the report file is the only file written)                 | `report`                                                                    |
| `agent_engine`               | AI engine                                                                      | `claude`                                                                    |
| `agent_loop_max_attempts`    | Max Agent→Verify cycles                                                        | `3`                                                                         |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it   | `medium`                                                                    |
| `agent_maker_instructions`   | Domain maker task (review skill, read-only engine review, repo exclusions)     | Inline in caller workflow                                                   |
| `agent_maker_max_turns`      | Max maker turns per attempt                                                    | `100`                                                                       |
| `agent_maker_model`          | Maker model ID                                                                 | `claude-sonnet-5`                                                           |
| `agent_maker_skill_name`     | Skill package                                                                  | `github-pr-review`                                                          |
| `agent_tool_allowlist`       | Read-only tool allowlist for the maker                                         | `gh api -X GET`, `gh issue view`, `gh pr diff`, `gh pr view`, `git show`    |
| `agent_unchanged_verdict`    | Verdict when no file diff (a missing report is a failed run)                   | `REJECT`                                                                    |
| `budget_max_runs_per_day`    | Daily run cap                                                                  | `20`                                                                        |
| `budget_max_tokens_per_day`  | Daily token cap                                                                | `1000000`                                                                   |
| `delivery`                   | Platform delivery (`pr_review` — finalize posts one `COMMENT` review)          | `pr_review`                                                                 |
| `detect_env_json`            | Detect env (`PR_EXCLUDE_LABELS`, and on dispatch `PR_FORCE`, `PR_NUMBER`)      | See [Domain detect environment](#domain-detect-environment-detect_env_json) |
| `detect_script`              | Domain detect script                                                           | `.agents/skills/github-pr-review/scripts/detect_pr_review.sh`               |
| `environment`                | GitHub Environment for env-scoped secrets                                      | `default`                                                                   |
| `finalize_script`            | Trusted render step run once in finalize; writes `review.json`                 | `.agents/skills/github-pr-review/scripts/render_review.sh`                  |
| `level`                      | Autonomy                                                                       | `L2`                                                                        |
| `loop_name`                  | Loop identifier                                                                | `github-pr-review`                                                          |
| `state_branch`               | `.loop/*` persistence branch                                                   | `main`                                                                      |

### Domain detect environment (`detect_env_json`)

`PR_EXCLUDE_LABELS` is `no-loop,loop-automation` on every path. `workflow_dispatch` also passes `PR_NUMBER` and `PR_FORCE`:

```yaml
detect_env_json: ${{ github.event_name == 'workflow_dispatch' && format('{{"PR_EXCLUDE_LABELS":"no-loop,loop-automation","PR_FORCE":"{0}","PR_NUMBER":"{1}"}}', inputs.force, inputs.pr_number) || '{"PR_EXCLUDE_LABELS":"no-loop,loop-automation"}' }}
```

Unset `PR_*` values are hydrated from `GITHUB_EVENT_PATH`; on `workflow_dispatch`, missing PR facts come from `gh pr view`.

## Caller shape

```text
on-loop-github-pr-review.yaml
  loop → uses ci-loop-caller-entity.yaml
           detect  → loop-entity-detect (detect_pr_review.sh)
           execute → ci-loop-agent (maker writes .loop-review/pr-<n>.json; checker verifies)
           finalize → delivery pr_review: no push to the base, agent branch deleted;
                      render_review.sh writes review.json, Deliver Message posts one COMMENT review
           record-skip → budget | domain:<reason> (+ skip_detail)
```

The head is never checked out or executed. The loop runs from the base checkout, and PR facts come from the event payload and read-only `gh` calls. Concurrency group `loop-github-pr-review-<pr>` with `cancel-in-progress: false` and `queue: max`. The entity caller keeps no per-target state, so there is no circuit breaker and no `loop-notify-pr` comment.

## Detect contract

`detect_pr_review.sh` emits `skip: true` when any of these holds: the PR is a draft, a fork PR (head repository differs from base), bot-authored, labeled `no-loop` or `loop-automation`, or a Bot-authored review carrying the marker `<!-- github-pr-review:v1 -->` already exists (unless `PR_FORCE` is `true`). It does not check whether the PR is open. The job `if` in the caller refuses the same classes, except the marker review, for `pull_request_target` so no run is queued for them (see [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention)). Detect fails closed: when a required fact cannot be obtained, it emits an error envelope.

When `skip` is `false`, `result` carries `pr_number`, `base_sha`, `head_sha`, `changed_files`, `report_path` (`.loop-review/pr-<n>.json`), and `handoff_key` (`entity:pr:<n>`).

## Skill contract

See `.apm/packages/github/.apm/skills/github-pr-review/SKILL.md` and its `references/`. Summary:

- Findings need one of three evidence kinds: `rule` or `criteria` (verbatim quote from a file that exists at the base commit) or `bug` (diff line plus the concrete failing input or state).
- Severities are `Critical`, `Warning`, `Suggestion`. Pre-existing problems are not reported.
- Rules are read from the base commit with `git show <base_sha>:<path>`, never from the PR head.
- The agent never posts. `gh` is read-only in the maker, and the platform posts the rendered review.

## Delivery contract

After `finalize_script`, Deliver Message in `loop-finalize` posts `review.json` when `delivery` is `pr_review`, the agent job succeeded, and the verdict is not `REJECT`. It reads the PR number from `target_json` (`handoff_key` `entity:pr:<n>`), not from the file.

| Rule              | Behavior                                                                                                                                                                                          |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Marker, Meta      | The platform adds the marker `<!-- github-pr-review:v1 -->` first when missing, and Meta and the footer last, to both `body` and `fallback_body`, so the review goes out once, complete           |
| Event             | Always `COMMENT`; nothing in the file can change it                                                                                                                                               |
| Inline failure    | When GitHub rejects the post with HTTP 422 and `comments` is non-empty, delivery retries once with `fallback_body` and no `comments`; other failures are not retried and fail the finalize step   |
| Stale `commit_id` | A `commit_id` that GitHub no longer accepts for inline comments is rejected with HTTP 422, so the review is posted from `fallback_body`. Whether GitHub accepts a stale `commit_id` is unverified |
| No file           | A missing or blank file posts nothing and lowers the outcome to `unchanged`                                                                                                                       |
| Outcome           | `pr_reviewed` after a post; `rejected` for a `REJECT` verdict; `unchanged` when nothing is posted                                                                                                 |

### Render contract (`render_review.sh`)

`render_review.sh` runs as `finalize_script` in finalize. It renders only when the verdict is `APPROVE`, and it never posts. It writes `review.json` (`{"body", "commit_id", "comments", "fallback_body"}`) to `LOOP_MESSAGE_DIR`. `GH_TOKEN` is used for reads only (`gh pr view`, `gh pr diff`).

| Rule                  | Behavior                                                                                                                                                                         |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Trusted SHAs          | Report `base_sha` / `head_sha` are not trusted. The PR's SHAs come from `gh pr view` and drive evidence checks, all links, and `commit_id`                                       |
| Stale head            | A report `head_sha` that is missing or differs from the PR head writes no file (the PR moved). A `base_sha` mismatch only warns                                                  |
| Evidence verification | `rule` / `criteria` findings are kept only when `evidence.quote` is an exact substring of `evidence.path` as committed at the trusted base SHA (via `git`, not the working tree) |
| Invalid findings      | Dropped; the review body reports the dropped count                                                                                                                               |
| Finding limit         | At most 20 findings are rendered; the most severe are kept (report order breaks ties) and the review body reports the omitted count                                              |
| In-diff placement     | Findings whose lines are in the PR diff become inline `comments`; others move to the review body                                                                                 |
| Link labels           | A path containing a backtick, bracket, or backslash is rendered as escaped text instead of a code span                                                                           |
| Fallback body         | `fallback_body` is the same review with every finding in the body, for the delivery retry                                                                                        |
| Exit status           | Always `0`. Failures emit `::warning::` and write no file, so nothing is posted and finalize does not fail                                                                       |

The agent branch holding the report is read by the script from `EXECUTE_BRANCH`.

### Finalize with `delivery: pr_review`

At L2, `loop-finalize` always runs. For `pr_review` it never pushes the agent branch to the target branch, and deletes the agent branch after delivery (also for `none` and `issue_comment`, and for a `REJECT` verdict). The report is persisted only through `finalize_script` and Deliver Message, so `finalize_script` reads the report from the agent branch before it is deleted. When Deliver Message fails, the branch is deleted too; the run log holds the diagnostics.

`finalize_script` receives `GH_TOKEN` (read-only use), `GITHUB_REPOSITORY`, `LOOP_MESSAGE_DIR` (the only place besides the repository root it may write), and `OUTCOME`. `OUTCOME` is the planned value (`pr_reviewed`) and may later become `unchanged` or `error`. The platform passes no Meta block; Deliver Message adds Meta and the footer, and nothing edits the review afterwards.

## Implementation Checklist

- [ ] Keep the job `if` refusing every class detect refuses on `pull_request_target` (draft, fork, Bot author, `no-loop`, `loop-automation`).
- [ ] Keep the `ci-loop-*` pins at a release that contains the fixes in [Rollout](#rollout).

## References

- [Loop Engineering Design](../loop-engineering-design.md)
- [Loop Caller Inputs Reference](loop-caller-inputs-reference.md)
- [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md): its reply path ([Context for replies](loop-github-pr-revise-workflow-design.md#context-for-replies)) reads the parent finding of an inline reply, so a human `@loop` reply on a review finding is understood in context.
