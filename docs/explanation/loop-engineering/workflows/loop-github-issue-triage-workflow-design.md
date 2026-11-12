# Issue Triage Workflow Design

Workflow and domain design for the `github-issue-triage` entity loop.

| Layer        | Document                                                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                                                       |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (entity)                                                          |
| Spec         | [Issue Triage Entity Loops](../../../superpowers/specs/2026-08-11-issue-triage-entity-loops-design.md)                             |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                                           |

**Artifacts:** `on-loop-github-issue-triage.yaml` · skill `github-issue-triage` · `detect_issue.sh` · `scripts/self/loop/list_triage_issues.sh` · `ci-loop-caller-entity.yaml`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md) (entity subset).

## Purpose

On Issue / issue_comment events, and on a daily schedule for Issues filed by the code-review loop, classify the Issue when confident, apply allowlisted triage labels, and post analysis or clarifying questions as comments (L1). Does not open PRs.

Behaviors to know:

- `target_json` is required at every level including L1, because Deliver Message reads the Issue number from `handoff_key`. This is a contract change for external callers of `ci-loop-agent.yaml`.
- Engines other than claude cannot write to `LOOP_MESSAGE_DIR` (only claude gets the write permission through `--add-dir`). With those engines, no message file exists and Deliver Message posts nothing (`unchanged`). This is a known limitation without an engine-specific flag.
- Deliver Message runs only when the agent job succeeded and the verdict is not `REJECT`. A failed triage run no longer gets the agent-applied `triage:failed` label or a comment; the run-log shows `error`.
- A delivery failure (label or post) fails the finalize step and records `failure_stage` `deliver_message`; an agent failure is recorded as `agent_execute`.
- The delivery outcome is `issue_commented`, or `unchanged` when the message is missing or blank.

## Use cases

| Use case                                      | Trigger                                                          | Outcome                                                                    | Transition              |
| --------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------- | ----------------------- |
| Triage an Issue that a person files           | `issues` `opened` / `reopened`, or `labeled` with `needs-triage` | Triage labels and one triage comment on the Issue                          | -                       |
| Re-triage after the person answers a question | `issue_comment` on an Issue that carries `triage:needs-info`     | Labels are updated and a new triage comment is posted                      | T2 -> T1 / T2 / T3      |
| Triage Issues that the code-review loop filed | Daily `schedule` (07:00 UTC), up to 3 Issues per run             | Triage labels and one triage comment per Issue; the Issue is not autofixed | T0 -> T1 / T2 / T3 / T4 |
| Triage one named Issue on demand              | `workflow_dispatch` with `issue_number`                          | Same as the Webhook path, for any Issue without `triage:failed`            | -                       |

## Out of scope

- Issue→PR autofix (axis 2 — see [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md))
- PR revision from review feedback (axis 3 — see [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md))
- Mention / `@` triggers on triage events
- Interactive AskUserQuestion path (automation-first)

## Intake paths

Two paths start this workflow, and each handles a different set of Issues. [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention) holds the gating rules.

- **Webhook path** (`issues`, `issue_comment`, `workflow_dispatch`): handles Issues that humans create or comment on. The `if` row in [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention) holds the gating rules, including the rejection of `loop:code-review` Issues on the `issues` branch.
- **Schedule path** (`schedule`, daily at 07:00 UTC): handles Issues that the code-review loop filed. The `list` job runs `scripts/self/loop/list_triage_issues.sh` and outputs `issues` (a JSON array of Issue numbers) and `count`. The `loop` job is a matrix over those numbers (`fail-fast: false`, `max-parallel: 3`) and passes `handoff_artifact_suffix: -issue-<N>`. Schedule runs share the `loop-state-main` concurrency group; other events keep one group per Issue.

The lister selects an Issue when all of these hold:

- The Issue is open, is not a pull request, and carries the label `loop:code-review`.
- The Issue has no label that starts with `triage:`.
- The author is a Bot and the body contains `<!-- code-review:fp:`.
- The Issue is not already handled: a comment with `<!-- github-issue-triage:v1 -->` exists and no human comment is newer than the latest such comment. Human means any comment author whose `user.type` is not `Bot`; the lister does not check `author_association`.
- The run-log holds fewer than 3 failure rows for `target_key` `entity:issue:<N>` within the last 7 days. A failure row has `outcome` `error`, `rejected` or `unchanged` (for triage: `message.md` is empty or `message_labels.json` is invalid, so nothing was delivered); `skipped` is not counted.

The lister reads at most 200 Issues, orders the remainder by oldest last attempt (never-attempted Issues first), and returns at most 3. `detect_issue.sh` still decides each Issue: for `ISSUE_EVENT_NAME=schedule` it skips any Issue with a `triage:*` label, and it hydrates title, body and labels from the API when `ISSUE_NUMBER` is set and those fields are empty.

## State model

This loop uses the triage states `T0`-`T4` defined in [Loop Issue Handoff](../loop-issue-handoff.md#triage-states). The handoff table tracks Issues that the code-review loop filed. Rows for Issues that a person filed on the Webhook path use `-` in the Transition column, because no state table tracks them.

## User actions

Each row is one action a person can take, the loop response, and what the person sees next. The Transition column references [Loop Issue Handoff](../loop-issue-handoff.md#triage-states).

| User action                                                                                                                                                                | Loop response                                                                                                                                                                        | Values changed                                                                                                                                                                                                            | Result and next action                                                                               | Transition              |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ----------------------- |
| Create or reopen an Issue (author with MEMBER, OWNER or COLLABORATOR role, or anyone in a private repository)                                                              | The Webhook path triages the Issue and applies labels and a comment (L1). On reopen, detect skips an Issue that carries `triage:ready` without `needs-triage` or `triage:needs-info` | `needs-triage`, `triage:needs-info` or `triage:ready`, and a type label; one comment with `<!-- github-issue-triage:v1 -->`; run-log `issue_commented` (or `unchanged`); concurrency group `loop-github-issue-triage-<N>` | `triage:ready` or `triage:needs-info` is applied. To have a `bug` fixed automatically, add `autofix` | -                       |
| Add `needs-triage` or `triage:needs-info` (repository owner, or the Issue author with MEMBER, OWNER or COLLABORATOR role; anyone in a private repository)                  | The Webhook path re-triages the Issue                                                                                                                                                | Triage labels per the FSM in the skill; one new marker comment; run-log `issue_commented` (or `unchanged`)                                                                                                                | Labels and the comment are updated                                                                   | -                       |
| Answer the question on a `triage:needs-info` Issue with a comment                                                                                                          | The Webhook path (`issue_comment`) re-triages the Issue. This also applies to `loop:code-review` Issues                                                                              | `triage:needs-info` is kept or replaced by `triage:ready`; one new marker comment; run-log `issue_commented` (or `unchanged`)                                                                                             | Labels are updated                                                                                   | T2 -> T1 / T2 / T3      |
| Do nothing (Issue filed by code-review)                                                                                                                                    | The daily schedule triages up to 3 Issues that match the conditions in [Intake paths](#intake-paths)                                                                                 | Triage labels; one marker comment; run-log row for `entity:issue:<N>`; handoff artifact suffix `-issue-<N>`; concurrency group `loop-state-main`                                                                          | Labels and a comment are applied. The Issue does not become an autofix input                         | T0 -> T1 / T2 / T3 / T4 |
| Comment on a low-confidence code-review Issue                                                                                                                              | The next schedule run re-triages it when a human comment is newer than the marker comment                                                                                            | One new marker comment; labels per the new classification; run-log `issue_commented`                                                                                                                                      | A new triage comment is posted. The Issue is not triaged again until you comment                     | T4 -> T0                |
| Add `needs-triage` by hand to a `loop:code-review` Issue                                                                                                                   | Nothing runs immediately, because the Webhook `issues` branch rejects the label `loop:code-review`                                                                                   | `needs-triage` only                                                                                                                                                                                                       | To run now, start `workflow_dispatch` with the Issue number                                          | -                       |
| Start `workflow_dispatch` with an Issue number                                                                                                                             | The workflow triages that Issue. Detect reads the current labels from the API and skips only when `triage:failed` is present                                                         | Same as the Webhook path; concurrency group `loop-github-issue-triage-<N>`                                                                                                                                                | Same as the Webhook path                                                                             | -                       |
| Re-run a failed run from the Actions page                                                                                                                                  | The run repeats with the original event. Webhook runs read the labels from the original event payload, so label changes made after the event are not seen                            | A new run-log row                                                                                                                                                                                                         | Check the new run. When labels changed since the event, start `workflow_dispatch` instead            | -                       |
| Keep a `triage:failed` Issue (an approved loop run delivers it from `message_labels.json`, or a person or an interactive run applies it; a failed run does not deliver it) | Neither the Webhook path nor the schedule picks it up                                                                                                                                | None                                                                                                                                                                                                                      | After you fix the cause, remove the label and start `workflow_dispatch`                              | -                       |
| Remove `triage:failed` and start `workflow_dispatch`                                                                                                                       | The workflow re-triages the Issue                                                                                                                                                    | `triage:failed` removed by the person; new triage labels; one marker comment; run-log `issue_commented` (or `unchanged`)                                                                                                  | Same as the Webhook path                                                                             | T3 -> T1 / T2 / T3 / T4 |
| Remove `triage:ready` from an Issue                                                                                                                                        | Nothing runs until a human comment is newer than the marker comment                                                                                                                  | `triage:ready` removed by the person                                                                                                                                                                                      | To re-triage, comment on the Issue                                                                   | -                       |
| Comment on a code-review Issue after removing `triage:ready`                                                                                                               | The next schedule run picks the Issue up                                                                                                                                             | None until the schedule run; then as in the schedule row                                                                                                                                                                  | A new triage comment is posted                                                                       | T1 -> T0                |
| Add only the label `loop:code-review` to a human-created Issue                                                                                                             | The schedule does not pick it up (see the conditions in [Intake paths](#intake-paths))                                                                                               | `loop:code-review` only                                                                                                                                                                                                   | To triage by hand, start `workflow_dispatch` with the Issue number                                   | -                       |
| Wait after an agent failure (no label or comment is applied)                                                                                                               | The next schedule run picks the Issue up again until the retry limit in [Intake paths](#intake-paths) excludes it                                                                    | Run-log `error`, `rejected` or `unchanged` for `entity:issue:<N>` (counted by the lister)                                                                                                                                 | Fix the cause. The Issue returns to the schedule when the failures leave the window                  | T0 -> T0                |
| Change `.loop/loop-budget.json`, the caller inputs, or `finalize_label_allowlist` by PR after a failure                                                                    | Nothing runs on merge. The next event, schedule run, or `workflow_dispatch` uses the new values                                                                                      | `.loop/loop-budget.json` caps (they override caller `budget_*`); caller inputs                                                                                                                                            | Start `workflow_dispatch` for the Issue that failed                                                  | -                       |
| Labels and comments that the loop itself posts (finalize uses a GitHub App token, which raises webhooks)                                                                   | Nothing runs: the `if` gate rejects a Bot sender and a Bot comment author, and `bug`, `feature`, `question`, `documentation` and `triage:ready` are outside the label intake list    | None                                                                                                                                                                                                                      | -                                                                                                    | -                       |

Not applicable: 3, 4, 6, 7 — the loop uses no mention token, opens no PR, and pushes no branch.

## Unhandled cases

| Case                                                                                                                | Why nothing follows                                                                                                                                                                             | Disposition |
| ------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| A person edits the Issue title or body (for example, to answer a question instead of commenting)                    | `issues` `edited` is not an intake event. The person comments, or starts `workflow_dispatch`, to re-triage                                                                                      | Accepted    |
| A person removes `needs-triage`, `triage:needs-info` or a type label                                                | `issues` `unlabeled` is not an intake event. Removing a label expresses a decision that needs no new triage                                                                                     | Accepted    |
| A person closes the Issue                                                                                           | Closed Issues need no triage; `issues` `closed` is not an intake event, and the lister reads open Issues only                                                                                   | Accepted    |
| A MEMBER who is neither the repository owner nor the Issue author adds `needs-triage` (public repository)           | The `labeled` gate admits only the repository owner or the Issue author, while the `issue_comment` gate admits any MEMBER, OWNER or COLLABORATOR. The person starts `workflow_dispatch` instead | Follow-up   |
| A user without MEMBER, OWNER or COLLABORATOR role files an Issue or answers a question (public repository)          | The gate refuses untrusted authors. A member re-triages by adding `needs-triage` (owner or author) or with `workflow_dispatch`                                                                  | Accepted    |
| A person comments on an Issue that carries `triage:ready` or only `needs-triage` (Webhook path)                     | The `issue_comment` gate requires `triage:needs-info`. The person adds `needs-triage` or starts `workflow_dispatch`                                                                             | Accepted    |
| A person leaves a `triage:needs-info` Issue unanswered                                                              | The loop waits for the author; no timeout exists                                                                                                                                                | Accepted    |
| A Webhook run ends without delivery (agent error, `REJECT`, `unchanged`, or budget skip) on an Issue a person filed | No label or comment tells the person, and only the schedule path retries (code-review Issues only). The Issue looks untouched until someone checks the Actions run                              | Follow-up   |
| Any non-Bot user's comment makes a handled code-review Issue eligible again on the schedule path                    | `list_triage_issues.sh` treats every non-Bot comment as human and does not check `author_association`, unlike the autofix scan. On a public repository, outside comments can spend triage runs  | Follow-up   |
| A non-claude engine runs the loop                                                                                   | Only claude can write to `LOOP_MESSAGE_DIR`, so nothing is delivered (`unchanged`)                                                                                                              | Limitation  |

## Failure and recovery

| Failure kind                                                                                | How it is recorded                                                                                                                       | Who acts   | What they do                                                             | How the loop resumes                                                                                    |
| ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| Agent job fails                                                                             | Run-log `outcome` `error`, `failure_stage` `agent_execute`; no label or comment                                                          | Maintainer | Fix the cause                                                            | Schedule path: the next run retries until 3 failures in 7 days. Webhook path: start `workflow_dispatch` |
| Checker rejects                                                                             | Run-log `outcome` `rejected`; no delivery                                                                                                | Maintainer | Check the checker reason; adjust the maker or checker instructions by PR | Same as an agent failure                                                                                |
| Message missing or invalid                                                                  | Run-log `outcome` `unchanged`; counted as a failure by the lister                                                                        | Maintainer | Check the engine and the maker output                                    | Same as an agent failure                                                                                |
| Delivery fails (label or comment post)                                                      | Run-log `outcome` `error`, `failure_stage` `deliver_message`; labels may be partly applied                                               | Maintainer | Fix the token or label problem                                           | Start `workflow_dispatch`; the schedule retries code-review Issues while no `triage:*` label is present |
| Daily budget used up                                                                        | Run-log `outcome` `skipped`, `skip_reason` `budget` (not counted by the lister)                                                          | Maintainer | Wait, or raise the cap in `.loop/loop-budget.json` by PR                 | Schedule path: the next day. Webhook path: start `workflow_dispatch`                                    |
| Retry limit reached (3 failures in 7 days)                                                  | The lister leaves the Issue out                                                                                                          | Maintainer | Fix the cause                                                            | The Issue returns when failures leave the window, or start `workflow_dispatch` now                      |
| Unsafe partial failure (the agent reports it in a run that succeeds, or an interactive run) | `triage:failed` on the Issue: a message run writes it to `message_labels.json` and Deliver Message applies it after the checker approves | Maintainer | Fix the cause and remove `triage:failed`                                 | Start `workflow_dispatch`                                                                               |
| Lister fails (GitHub API)                                                                   | The `list` job fails and the `loop` job does not run                                                                                     | Maintainer | Check the API error                                                      | The next schedule run                                                                                   |

## Caller inputs

Keys are passed in `on-loop-github-issue-triage.yaml` via `with:` on `ci-loop-caller-entity.yaml`. Entity subset of [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

| Input / JSON key             | Description                                                                                     | Dogfood value                                                                                                       |
| ---------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it                  | `medium`                                                                                                            |
| `agent_checker_instructions` | APPROVE/REJECT rubric (allowlisted labels only)                                                 | Inline in caller workflow                                                                                           |
| `agent_checker_max_turns`    | Max checker turns                                                                               | `100`                                                                                                               |
| `agent_checker_model`        | Checker model ID                                                                                | `claude-opus-5`                                                                                                     |
| `agent_checker_skill_name`   | Checker skill                                                                                   | `loop-verifier`                                                                                                     |
| `agent_engine`               | AI engine                                                                                       | `claude`                                                                                                            |
| `agent_loop_max_attempts`    | Max Agent→Verify cycles                                                                         | `3`                                                                                                                 |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it                    | `medium`                                                                                                            |
| `agent_maker_instructions`   | Domain maker task (triage skill)                                                                | Inline in caller workflow                                                                                           |
| `agent_maker_max_turns`      | Max maker turns per attempt                                                                     | `100`                                                                                                               |
| `agent_maker_model`          | Maker model ID                                                                                  | `claude-sonnet-5`                                                                                                   |
| `agent_maker_skill_name`     | Skill package                                                                                   | `github-issue-triage`                                                                                               |
| `agent_tool_allowlist`       | Read-only tool rules for the maker (posting and labels belong to finalize)                      | `gh api -X GET`, `gh issue view`, `gh label list`, `gh repo view`                                                   |
| `budget_max_runs_per_day`    | Daily run cap                                                                                   | `20`                                                                                                                |
| `budget_max_tokens_per_day`  | Daily token cap                                                                                 | `1000000`                                                                                                           |
| `delivery`                   | Platform delivery (`issue_comment` — finalize posts the comment)                                | `issue_comment`                                                                                                     |
| `detect_script`              | Domain detect script                                                                            | `.agents/skills/github-issue-triage/scripts/detect_issue.sh`                                                        |
| `finalize_label_allowlist`   | Labels finalize may add or remove from `message_labels.json`; others are skipped with a warning | `needs-triage`, `bug`, `feature`, `question`, `documentation`, `triage:needs-info`, `triage:ready`, `triage:failed` |
| `environment`                | GitHub Environment for env-scoped secrets                                                       | `default`                                                                                                           |
| `handoff_artifact_suffix`    | Suffix that keeps handoff artifact names unique per matrix Issue                                | `-issue-<N>`                                                                                                        |
| `level`                      | Autonomy (`L1` — no PR)                                                                         | `L1`                                                                                                                |
| `loop_name`                  | Loop identifier                                                                                 | `github-issue-triage`                                                                                               |
| `state_branch`               | `.loop/*` persistence branch                                                                    | `main`                                                                                                              |

### Domain detect environment (`detect_env_json`)

`{}` on webhook paths. `workflow_dispatch` passes `ISSUE_NUMBER`, and the schedule path passes `ISSUE_EVENT_NAME` and `ISSUE_NUMBER` for each matrix Issue. The caller sets it as follows:

```yaml
detect_env_json: ${{ github.event_name == 'schedule' && format('{{"ISSUE_EVENT_NAME":"schedule","ISSUE_NUMBER":{0}}}', toJSON(matrix.issue)) || github.event_name == 'workflow_dispatch' && format('{{"ISSUE_NUMBER":{0}}}', toJSON(matrix.issue)) || '{}' }}
```

Detect script env (explicit or hydrated from `GITHUB_EVENT_PATH`): `ISSUE_NUMBER`, `ISSUE_TITLE`, `ISSUE_BODY`, `ISSUE_LABELS_JSON`, `ISSUE_EVENT_NAME`, `ISSUE_EVENT_ACTION`, `ISSUE_COMMENT_ID`, `ISSUE_ACTOR`, `ISSUE_ACTOR_TYPE`, `ISSUE_COMMENT_USER_TYPE`.

## Caller shape

```text
on-loop-github-issue-triage.yaml
  list → list_triage_issues.sh (schedule only; outputs issues, count)
  loop → matrix over Issue numbers (fail-fast: false, max-parallel: 3); uses ci-loop-caller-entity.yaml
           detect  → loop-entity-detect
                       (detect_issue.sh reads GITHUB_EVENT_PATH;
                        workflow_dispatch / schedule pass ISSUE_NUMBER (schedule also ISSUE_EVENT_NAME) via detect_env_json)
           execute → ci-loop-agent (agent-l1 reads only; finalize-l1 has issues: write and runs loop-finalize (Deliver Message) and the run-log; L1 has no finalize-l2, so no PR)
           record-skip → budget | detect_skip
```

No caller `prepare` job — event mapping lives in the skill detect script (E17).

## Detect contract

Skip when actor or comment author is Bot, or when `triage:failed` is present (E7). For `ISSUE_EVENT_NAME=schedule`, skip any Issue that carries a `triage:*` label. For `issue_comment`, skip unless the Issue carries `triage:needs-info`. For `issues`, skip an Issue that carries `triage:ready` without `needs-triage` or `triage:needs-info`. `workflow_dispatch` skips only for `triage:failed`. When skip=false, emit `result.handoff_key` = `entity:issue:<N>` (S1).

## Skill contract

See `.apm/packages/github/.apm/skills/github-issue-triage/SKILL.md` and `references/category-*.md`.

## Delivery contract

The agent does not write to GitHub. It writes the comment to `message.md` and the label changes (`{"add": [...], "remove": [...]}`) to `message_labels.json` in `LOOP_MESSAGE_DIR`; `loop-agent-once` creates that directory, names it at the end of the prompt, and passes the files to `finalize-l1` as the job output `message_json`. `loop-finalize` (Deliver Message) then adds or removes the labels that are in `finalize_label_allowlist`, and posts the comment once as one Issue comment with the Marker, Meta block and footer. No later step edits the posted comment.

Labels that do not exist yet are created by the workflow before they are added (`ensure_repo_labels`), so the result of `POST .../issues/<n>/labels` naming a missing label no longer matters. The allowlist still bounds which labels can be created.

## Implementation Checklist

- [ ] Run a live `workflow_dispatch` dry run after `AGENT_TOKEN` is refreshed.
- [ ] On the first schedule run, confirm the items in [Deferred dogfood](#deferred-dogfood).

### Deferred dogfood

Live `workflow_dispatch` dry-run requires repository secrets (`AGENT_TOKEN`, optional bot app). Treat end-to-end Actions dogfood as deferred until secrets are available; local verification is Bats + `actionlint`.

The schedule path and the matrix-based Webhook / `workflow_dispatch` path have not been verified on GitHub because the workflows are not run until `AGENT_TOKEN` is refreshed. When they first run, check that `fromJSON` works when the `list` job is skipped, that the matrix expression resolves for each event, that the `loop` job `if` is evaluated before an empty matrix is expanded, and that the `loop-state-main` concurrency group with `queue: max` queues as expected.

## References

- [Loop Issue Handoff](../loop-issue-handoff.md)
- [Loop Engineering Design](../loop-engineering-design.md)
- [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md)
- [Loop Caller Inputs Reference](loop-caller-inputs-reference.md)
