# Issue Triage Workflow Design

Workflow and domain design for the `github-issue-triage` entity loop.

| Layer        | Document                                                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                                                       |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (entity)                                                          |
| Spec         | [Issue Triage Entity Loops](../../../superpowers/specs/2026-08-11-issue-triage-entity-loops-design.md)                             |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                                           |

**Artifacts:** `on-loop-github-issue-triage.yaml` · skill `github-issue-triage` · `detect_issue.sh` · `ci-loop-caller-entity.yaml`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md) (entity subset).

## Purpose

On Issue / issue_comment events, classify the Issue when confident, apply allowlisted triage labels, and post analysis or clarifying questions as comments (L1). Does not open PRs.

The agent does not write to GitHub. It writes the comment to `message.md` and the label changes (`{"add": [...], "remove": [...]}`) to `message_labels.json` in `LOOP_MESSAGE_DIR`; `loop-agent-once` creates that directory, names it at the end of the prompt, and passes the files to `finalize-l1` as the job output `message_json`. `loop-finalize` (Deliver Message) then adds or removes the labels that are in `finalize_label_allowlist`, and posts the comment once as one Issue comment with the Marker, Meta block and footer. No later step edits the posted comment.

Behaviors to know:

- `target_json` is required at every level including L1, because Deliver Message reads the Issue number from `handoff_key`. This is a contract change for external callers of `ci-loop-agent.yaml`.
- Engines other than claude cannot write to `LOOP_MESSAGE_DIR` (only claude gets the write permission through `--add-dir`). With those engines, no message file exists and Deliver Message posts nothing (`unchanged`). This is a known limitation without an engine-specific flag.
- Deliver Message runs only when the agent job succeeded and the verdict is not `REJECT`. A failed triage run no longer gets the agent-applied `triage:failed` label or a comment; the run-log shows `error`.
- A delivery failure (label or post) fails the finalize step and records `failure_stage` `deliver_message`; an agent failure is recorded as `agent_execute`.
- The delivery outcome is `issue_commented`, or `unchanged` when the message is missing or blank.

### Supported use cases

- `issues` opened/reopened/labeled → entity detect + L1 agent (label removal does not re-trigger triage)
  - `labeled` intake is limited to `needs-triage` and `triage:needs-info`. Classification labels the agent applies itself and `triage:ready` (detect skips it) stay out, and `autofix` belongs to [Autofix Design](loop-github-issue-autofix-workflow-design.md)
  - Bot senders are refused in the job `if`, so agent-applied labels never re-enter the queue (see [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention))
- `issue_comment` created by a non-bot author while `triage:needs-info` is present (human answers while awaiting info)
- `workflow_dispatch` with `issue_number` for manual re-triage

### Out of scope

- Issue→PR autofix (axis 2 — see [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md))
- PR revision from review feedback (axis 3 — see [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md))
- Mention / `@` triggers on triage events
- Interactive AskUserQuestion path (automation-first)

### Deferred dogfood

Live `workflow_dispatch` dry-run requires repository secrets (`AGENT_TOKEN`, optional bot app). Treat end-to-end Actions dogfood as deferred until secrets are available; local verification is Bats + `actionlint`.

Open dogfood check: whether GitHub creates a label that does not exist when `POST .../issues/<n>/labels` names it is unverified. The allowlist bounds the effect either way. Record the result here after the first live run.

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
| `agent_tool_allowlist`       | Read-only tool rules for the maker (posting and labels belong to finalize)                      | `gh api -X GET`, `gh issue view`, `gh label list`                                                                   |
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

`{}` on webhook paths. `workflow_dispatch` may pass `ISSUE_NUMBER`:

```yaml
detect_env_json: ${{ github.event_name == 'workflow_dispatch' && format('{{"ISSUE_NUMBER":{0}}}', toJSON(inputs.issue_number)) || '{}' }}
```

Detect script env (explicit or hydrated from `GITHUB_EVENT_PATH`): `ISSUE_NUMBER`, `ISSUE_TITLE`, `ISSUE_BODY`, `ISSUE_LABELS_JSON`, `ISSUE_EVENT_NAME`, `ISSUE_EVENT_ACTION`, `ISSUE_COMMENT_ID`, `ISSUE_ACTOR`, `ISSUE_ACTOR_TYPE`, `ISSUE_COMMENT_USER_TYPE`.

## Caller shape

```text
on-loop-github-issue-triage.yaml
  loop → uses ci-loop-caller-entity.yaml
           detect  → loop-entity-detect
                       (detect_issue.sh reads GITHUB_EVENT_PATH;
                        workflow_dispatch may pass ISSUE_NUMBER via detect_env_json)
           execute → ci-loop-agent (agent-l1 reads only; finalize-l1 has issues: write and runs loop-finalize (Deliver Message) and the run-log; L1 has no finalize-l2, so no PR)
           record-skip → budget | circuit_breaker
```

No caller `prepare` job — event mapping lives in the skill detect script (E17).

## Detect contract

Skip when actor or comment author is Bot, or when `triage:failed` is present (E7). When skip=false, emit `result.handoff_key` = `entity:issue:<N>` (S1).

## Skill contract

See `.apm/packages/github/.apm/skills/github-issue-triage/SKILL.md` and `references/category-*.md`.
