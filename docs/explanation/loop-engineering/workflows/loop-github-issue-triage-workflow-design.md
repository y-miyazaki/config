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

The agent does not write to GitHub. It writes the comment to `message.md` and the label changes (`{"add": [...], "remove": [...]}`) to `message_labels.json` in `LOOP_MESSAGE_DIR`; `loop-agent-once` creates that directory, names it at the end of the prompt, and passes the files to `finalize-l1` as the job output `message_json`. `loop-finalize` (Deliver Message) then adds or removes the labels that are in `finalize_label_allowlist`, and posts the comment once as one Issue comment with the Marker, Meta block and footer. No later step edits the posted comment.

Behaviors to know:

- `target_json` is required at every level including L1, because Deliver Message reads the Issue number from `handoff_key`. This is a contract change for external callers of `ci-loop-agent.yaml`.
- Engines other than claude cannot write to `LOOP_MESSAGE_DIR` (only claude gets the write permission through `--add-dir`). With those engines, no message file exists and Deliver Message posts nothing (`unchanged`). This is a known limitation without an engine-specific flag.
- Deliver Message runs only when the agent job succeeded and the verdict is not `REJECT`. A failed triage run no longer gets the agent-applied `triage:failed` label or a comment; the run-log shows `error`.
- A delivery failure (label or post) fails the finalize step and records `failure_stage` `deliver_message`; an agent failure is recorded as `agent_execute`.
- The delivery outcome is `issue_commented`, or `unchanged` when the message is missing or blank.

### Intake paths

Two paths start this workflow, and each handles a different set of Issues. [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention) holds the gating rules.

- **Webhook path** (`issues`, `issue_comment`, `workflow_dispatch`): handles Issues that humans create or comment on. The `if` row in [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention) holds the gating rules, including the rejection of `loop:code-review` Issues on the `issues` branch.
- **Schedule path** (`schedule`, daily at 07:00 UTC): handles Issues that the code-review loop filed. The `list` job runs `scripts/self/loop/list_triage_issues.sh` and outputs `issues` (a JSON array of Issue numbers) and `count`. The `loop` job is a matrix over those numbers (`fail-fast: false`, `max-parallel: 3`) and passes `handoff_artifact_suffix: -issue-<N>`. Schedule runs share the `loop-state-main` concurrency group; other events keep one group per Issue.

The lister selects an Issue when all of these hold:

- The Issue is open, is not a pull request, and carries the label `loop:code-review`.
- The Issue has no label that starts with `triage:`.
- The author is a Bot and the body contains `<!-- code-review:fp:`.
- The Issue is not already handled: a comment with `<!-- github-issue-triage:v1 -->` exists and no human comment is newer than the latest such comment.
- The run-log holds fewer than 3 `error` or `rejected` rows for `target_key` `entity:issue:<N>` within the last 7 days.

The lister reads at most 200 Issues, orders the remainder by oldest last attempt (never-attempted Issues first), and returns at most 3. `detect_issue.sh` still decides each Issue: for `ISSUE_EVENT_NAME=schedule` it skips any Issue with a `triage:*` label, and it hydrates title, body and labels from the API when `ISSUE_NUMBER` is set and those fields are empty.

### User actions

Each row is one action a person can take, the loop response, and what the person sees next. The Transition column references [Loop Issue Handoff](../loop-issue-handoff.md#triage-states).

| User action                                                          | Loop response                                                                                                   | Result and next action                                                                                  | Transition |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ---------- |
| Create an Issue (human with MEMBER, OWNER or COLLABORATOR role)      | The Webhook path triages the Issue and applies labels and a comment (L1)                                        | `triage:ready` or `triage:needs-info` is applied. To have a `bug` fixed automatically, add `autofix`    | -          |
| Add `needs-triage` or `triage:needs-info`                            | The Webhook path re-triages the Issue                                                                           | Labels and the comment are updated                                                                      | -          |
| Answer the question on a `triage:needs-info` Issue with a comment    | The Webhook path (`issue_comment`) re-triages the Issue. This also applies to `loop:code-review` Issues         | Labels are updated                                                                                      | T2         |
| Do nothing (Issue filed by code-review)                              | The daily schedule triages up to 3 Issues that match the conditions in [Intake paths](#intake-paths)                                      | Labels and a comment are applied. The Issue does not become an autofix input                            | T0         |
| Comment on a low-confidence code-review Issue                        | The next schedule run re-triages it when a human comment is newer than the marker comment                    | The comment is updated. The Issue is not triaged again until you comment                                | T4         |
| Add `needs-triage` by hand to a `loop:code-review` Issue             | Nothing runs immediately, because the Webhook `issues` branch rejects the label `loop:code-review`            | To run now, start `workflow_dispatch` with the Issue number                                             | -          |
| Start `workflow_dispatch` with an Issue number                       | The workflow triages that Issue                                                                                 | Same as above                                                                                           | -          |
| Keep a `triage:failed` Issue                                         | Neither the Webhook path nor the schedule picks it up                                                           | After you fix the cause, remove the label and start `workflow_dispatch`                                 | T3         |
| Remove `triage:ready` from an Issue                                  | Nothing runs until a human comment is newer than the marker comment                                         | To re-triage, comment on the Issue                                                                      | T1 / T0    |
| Add only the label `loop:code-review` to a human-created Issue       | The schedule does not pick it up (see the conditions in [Intake paths](#intake-paths))          | To triage by hand, start `workflow_dispatch` with the Issue number                                      | -          |
| Wait after an agent failure (no label or comment is applied)         | The next schedule run picks the Issue up again until the retry limit in [Intake paths](#intake-paths) excludes it               | Fix the cause. The Issue returns to the schedule when the failures leave the window                   | T0         |

### Out of scope

- Issue→PR autofix (axis 2 — see [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md))
- PR revision from review feedback (axis 3 — see [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md))
- Mention / `@` triggers on triage events
- Interactive AskUserQuestion path (automation-first)

### Deferred dogfood

Live `workflow_dispatch` dry-run requires repository secrets (`AGENT_TOKEN`, optional bot app). Treat end-to-end Actions dogfood as deferred until secrets are available; local verification is Bats + `actionlint`.

Labels that do not exist yet are created by the workflow before they are added (`ensure_repo_labels`), so the result of `POST .../issues/<n>/labels` naming a missing label no longer matters. The allowlist still bounds which labels can be created.

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
                        workflow_dispatch may pass ISSUE_NUMBER via detect_env_json)
           execute → ci-loop-agent (agent-l1 reads only; finalize-l1 has issues: write and runs loop-finalize (Deliver Message) and the run-log; L1 has no finalize-l2, so no PR)
           record-skip → budget | circuit_breaker
```

No caller `prepare` job — event mapping lives in the skill detect script (E17).

## Detect contract

Skip when actor or comment author is Bot, or when `triage:failed` is present (E7). For `ISSUE_EVENT_NAME=schedule`, skip any Issue that carries a `triage:*` label. When skip=false, emit `result.handoff_key` = `entity:issue:<N>` (S1).

## Skill contract

See `.apm/packages/github/.apm/skills/github-issue-triage/SKILL.md` and `references/category-*.md`.
