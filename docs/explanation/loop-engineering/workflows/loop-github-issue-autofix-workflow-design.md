# Issue Autofix Workflow Design

| Layer        | Document                                                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                                                       |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (branch)                                                          |
| Spec         | [Issue Autofix and PR Revise Full Design](../../../superpowers/specs/2026-08-11-issue-autofix-pr-revise-full-design.md)            |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                                           |

**Artifacts:** `on-loop-github-issue-autofix.yaml` · skill `github-issue-autofix` · `detect_autofix.sh` · `ci-loop-caller.yaml`

## Purpose

Single intake for Issue→PR autofix: `labeled(autofix)` + `repository_dispatch` (`loop-github-issue-autofix`) + `workflow_dispatch` → **branch** caller (L2, `agent_edit_target: fix`, `delivery: pr_create`).

Detect skips when an open/draft PR already references the Issue with a closing keyword (`Fixes #N`, etc.). PR draft/open is controlled by caller `pr_draft` (**default open**).

A daily `schedule` also runs a second job, `loop-scheduled`, at L1 with `delivery: none`. It observes the Issues that the code-review loop filed and logs a fix plan for each. It does not edit files or open PRs. Promoting it to L2 is not implemented (see [Stage E](#stage-e-not-implemented)).

### Intake paths

Two paths start this workflow, and each handles a different set of Issues. [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention) holds the gating rules.

- **Webhook path** (`issues` labeled `autofix`, `repository_dispatch`, `workflow_dispatch`): the `loop` job runs at L2 for the one Issue that a human named. It makes a `Fixes #N` PR.
- **Schedule path** (`schedule`, daily at 12:00 UTC): the `loop-scheduled` job runs at L1 with `delivery: none`, `detect_items: true`, `detect_branch_match: main` and `detect_max_targets: 3`. The `loop` job is skipped for `schedule`. Schedule runs share the `loop-state-main` concurrency group; other events keep one group per Issue.

`detect_autofix.sh` runs in scan mode (`AUTOFIX_SCAN=true`) on the schedule path and returns the qualifying Issues as `result.items`, one item per Issue with key `issue:<N>`. The platform keeps state per item under `integration:main#issue:<N>`. The script reads these environment variables from `detect_env_json`: `AUTOFIX_SOURCE_LABEL` (`loop:code-review`), `AUTOFIX_SOURCE_MARKER` (`<!-- code-review:fp:`), `AUTOFIX_PR_LABEL` (`loop-automation`), `AUTOFIX_BRANCH_PREFIX` (`loop/github-issue-autofix/`) and `AUTOFIX_MAX_OPEN_PRS` (`3`).

Scan mode selects an Issue when all of these hold:

- The Issue is open, is not a pull request, and carries the source label.
- The Issue has no `autofix` label.
- The author is a Bot (`user.type` is `Bot`) and the body contains the source marker. A human who adds only `loop:code-review` does not make an Issue eligible.

Scan mode then excludes an Issue in these cases:

- An open PR references the Issue with a closing keyword.
- The Issue is already handled: a closed PR with the PR label references the Issue, and no human comment is newer than the latest `closedAt` of such PRs. A human comment after that time makes the Issue eligible again. Closing a PR does not count as a failure.

Scan mode skips the whole run when the number of open PRs that carry the PR label and a head branch with the branch prefix reaches `AUTOFIX_MAX_OPEN_PRS`. This limit applies to scan mode only; the Webhook path is not limited. The script reads the 200 most recent closed PRs, so an older closed PR is not seen. It returns up to 50 Issues, oldest first, without cutting them to `detect_max_targets`. The platform orders the items by `last_run`, applies `detect_max_targets` and drops items that are pending or stopped by the circuit breaker. An `autofix` label added later moves the Issue to the Webhook path. If the schedule already picked the Issue up, both paths can run until the schedule run ends.

L1 writes no state, so `last_run` ordering does not advance and each run tends to see the same oldest Issues. The L1 plan appears only in the log of the `agent-l1` job. The caller still passes the checker inputs, because `ci-loop-caller.yaml` requires `agent_checker_instructions`.

### Stage E (not implemented)

Stage E is planned after at least two weeks of L1 observation. It would promote `loop-scheduled` to L2 with `delivery: pr_create`, and would make the Webhook path return one item per Issue so that both paths share the per-Issue key for pending state and the circuit breaker. None of this exists today. Until then, the Webhook path keeps its existing key, and the circuit breaker of the schedule path does not stop the Webhook path.

### User actions

Each row is one action a person can take, the loop response, and what the person sees next. The Transition column references [Loop Issue Handoff](../loop-issue-handoff.md#autofix-states). Rows that depend on stage E say so.

| User action                                                              | Loop response                                                                                                         | Result and next action                                                              | Transition |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ---------- |
| Add the `autofix` label to an Issue (human)                              | The Webhook path implements the fix and creates a `Fixes #N` PR (L2)                                                  | Review and merge the PR                                                             | A3         |
| Start `workflow_dispatch` or `repository_dispatch` with an Issue number  | Same as above                                                                                                         | Same as above                                                                       | A3         |
| Do nothing (Issue filed by code-review)                                  | The daily schedule picks up to 3 Issues that match [Intake paths](#intake-paths) and logs a fix plan (L1). No PR is created | Read the plan in the `agent-l1` job log. To get a PR now, add `autofix`             | A1, A2     |
| Do nothing (Issue filed by code-review), after stage E                   | The schedule creates a PR (L2). Not implemented                                                                       | Review and merge the PR                                                             | A2, A3     |
| Merge an autofix PR                                                      | `Fixes #N` closes the Issue                                                                                           | -                                                                                   | A6         |
| Close an autofix PR without merging (Issue stays open)                   | The schedule does not pick up the Issue until a human comments (see [Intake paths](#intake-paths))                    | To retry, comment on the Issue. To drop it, close the Issue                         | A4         |
| Comment on the Issue after closing the PR                                | The next schedule run picks up the Issue again                                                                        | Write the direction of the fix in the comment so the agent can read it              | A1         |
| Close an Issue, or reopen a closed Issue                                 | A closed Issue is not picked up. A reopened Issue is picked up again when it matches [Intake paths](#intake-paths)    | -                                                                                   | A6, A1     |
| Remove `loop:code-review` from an Issue                                  | The schedule no longer picks up the Issue. The code-review loop can file the finding again                            | To stop it, close the Issue instead of removing the label                           | -          |
| Add `autofix` to an Issue that the schedule already picked up            | The schedule stops listing the Issue and the Webhook path handles it. Both can run until the schedule run ends        | If two PRs result, keep the first and close the other                               | A1         |
| Open autofix PRs reach `AUTOFIX_MAX_OPEN_PRS`                            | The schedule skips the run. The Webhook path is not limited                                                           | Merge or close a PR; the next schedule run resumes                                  | -          |
| The checker rejects the same Issue three times in a row (stage E)        | The Issue key is not picked up and the Webhook path stops too. Not implemented                                        | Remove the key from `.loop/state-github-issue-autofix.json` by PR, or wait 30 days  | A5         |
| The daily budget is used up                                              | The run is skipped (`skip_reason=budget`)                                                                             | The next day resumes. Change `budget_*` in the caller to raise the cap              | -          |

Skill execution boundaries: `github-issue-autofix` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

## Caller inputs

Keys are passed in `on-loop-github-issue-autofix.yaml` via `with:` on `ci-loop-caller.yaml`. Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

| Input / JSON key             | Description                                                                                  | Dogfood value                                                                                                                            |
| ---------------------------- | -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it               | `medium`                                                                                                                                 |
| `agent_checker_instructions` | APPROVE/REJECT rubric                                                                        | Inline in caller workflow                                                                                                                |
| `agent_checker_max_turns`    | Max checker turns                                                                            | `100`                                                                                                                                    |
| `agent_checker_model`        | Checker model ID                                                                             | `claude-opus-5`                                                                                                                          |
| `agent_checker_skill_name`   | Checker skill                                                                                | `loop-verifier`                                                                                                                          |
| `agent_edit_allowlist`       | File edit allowlist (`**` = unrestricted)                                                    | `**`                                                                                                                                     |
| `agent_edit_target`          | Agent artifact type                                                                          | `fix`                                                                                                                                    |
| `agent_engine`               | AI engine                                                                                    | `claude`                                                                                                                                 |
| `agent_loop_max_attempts`    | Max Agent→Verify cycles                                                                      | `3`                                                                                                                                      |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it                 | `medium`                                                                                                                                 |
| `agent_maker_instructions`   | Minimal fix from detect JSON; PR body with `Fixes #N`                                        | Inline in caller workflow                                                                                                                |
| `agent_maker_max_turns`      | Max maker turns per attempt                                                                  | `100`                                                                                                                                    |
| `agent_maker_model`          | Maker model ID                                                                               | `claude-sonnet-5`                                                                                                                        |
| `agent_maker_skill_name`     | Skill package                                                                                | `github-issue-autofix`                                                                                                                   |
| `agent_tool_allowlist`       | Tool permission rules for the maker (read Issue, check existing PRs, run validation scripts) | `gh api -X GET`, `gh issue view`, `gh pr list`, `gh pr view`, `validate.sh` of github-actions, go, markdown, and shell-script validation |
| `agent_unchanged_verdict`    | Verdict when no file diff                                                                    | `REJECT`                                                                                                                                 |
| `budget_max_runs_per_day`    | Daily run cap                                                                                | `10`                                                                                                                                     |
| `budget_max_tokens_per_day`  | Daily token cap                                                                              | `1000000`                                                                                                                                |
| `delivery`                   | Where the output is delivered                                                                | `pr_create`                                                                                                                              |
| `detect_branch_match`        | Integration branch to fix against                                                            | `main`                                                                                                                                   |
| `detect_script`              | Domain detect script                                                                         | `.agents/skills/github-issue-autofix/scripts/detect_autofix.sh`                                                                          |
| `environment`                | GitHub Environment for env-scoped secrets                                                    | `default`                                                                                                                                |
| `level`                      | Autonomy (`L2` — review PR)                                                                  | `L2`                                                                                                                                     |
| `loop_name`                  | Loop identifier                                                                              | `github-issue-autofix`                                                                                                                   |
| `pr_draft`                   | Create fix PR as draft when true                                                             | `false` (default open)                                                                                                                   |
| `state_branch`               | `.loop/*` persistence branch                                                                 | `main`                                                                                                                                   |

### Scheduled job (`loop-scheduled`)

The job passes the same keys as above except the following. It has no `agent_edit_*`, `delivery: pr_create` or `pr_draft`, and its maker and checker instructions ask for a plan only.

| Input / JSON key      | Dogfood value                                                         |
| --------------------- | --------------------------------------------------------------------- |
| `agent_tool_allowlist` | `gh api -X GET`, `gh issue view`, `gh pr list`, `gh pr view` (no validation scripts) |
| `delivery`            | `none`                                                                |
| `detect_items`        | `true`                                                                |
| `detect_max_targets`  | `3`                                                                   |
| `level`               | `L1`                                                                  |

### Domain detect environment (`detect_env_json`)

```yaml
detect_env_json: ${{ format('{{"ISSUE_NUMBER":{0}}}', toJSON(format('{0}', github.event.issue.number || github.event.client_payload.issue_number || inputs.issue_number || ''))) }}
```

| JSON key / env var | Description         | Notes               |
| ------------------ | ------------------- | ------------------- |
| `ISSUE_NUMBER`     | Target Issue number | Required to proceed |

## Caller shape

```text
on-loop-github-issue-autofix.yaml
  loop → uses ci-loop-caller.yaml (not schedule)
           detect  → detect_autofix.sh
           execute → ci-loop-agent (level L2)
           finalize → pr_create (pr_draft from inputs)
  loop-scheduled → uses ci-loop-caller.yaml (schedule only)
           detect  → detect_autofix.sh (scan mode; result.items)
           execute → ci-loop-agent (level L1; plan in the agent-l1 job log)
           finalize → delivery none
```

Concurrency: `loop-state-main` for `schedule`; otherwise `loop-github-issue-autofix-${issue_number || run_id}`. Workflow-level `permissions` is `{}`; each job declares its own.

## Triage handoff

Triage marks `triage:ready` and tells the human that adding `autofix` requests a fix PR. Autofix starts only from the `autofix` label, `workflow_dispatch`, or `repository_dispatch` with `client_payload.issue_number`; neither triage nor the Agent dispatches. To retry after a run that opened no PR (REJECT, budget, closed PR), remove and re-add `autofix`, or run `workflow_dispatch` with `issue_number`.
