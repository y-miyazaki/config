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

### Supported use cases

- `issues` labeled `autofix` → branch caller detect + L2 agent + fix PR
- `repository_dispatch` (`loop-github-issue-autofix`) with `client_payload.issue_number` — an external or manual entry; nothing in this repository sends it
- `workflow_dispatch` with `issue_number` (optional `pr_draft`) for manual autofix

### Out of scope

- Issue triage / label classification (axis 1 — see [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md))
- PR revision from review feedback (axis 3 — see [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md))
- L3 auto-merge on the fix PR
- Automatic autofix without the `autofix` label (`repository_dispatch` / `workflow_dispatch` remain explicit human paths)
- Agent-initiated `repository_dispatch`
- PR head mode (`detect_pr_enabled` default off) — fixes target the integration branch via `pr_create`
- Second fix PR when an open/draft PR already references the Issue with a closing keyword (`Fixes #N`, etc.)

Skill execution boundaries: `github-issue-autofix` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

## Caller inputs

Keys are passed in `on-loop-github-issue-autofix.yaml` via `with:` on `ci-loop-caller.yaml`. Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

| Input / JSON key             | Description                                                                    | Dogfood value                                                   |
| ---------------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it | `medium`                                                        |
| `agent_checker_instructions` | APPROVE/REJECT rubric                                                          | Inline in caller workflow                                       |
| `agent_checker_max_turns`    | Max checker turns                                                              | `100`                                                           |
| `agent_checker_model`        | Checker model ID                                                               | `claude-opus-5`                                                 |
| `agent_checker_skill_name`   | Checker skill                                                                  | `loop-verifier`                                                 |
| `agent_edit_allowlist`       | File edit allowlist (`**` = unrestricted)                                      | `**`                                                            |
| `agent_edit_target`          | Agent artifact type                                                            | `fix`                                                           |
| `agent_engine`               | AI engine                                                                      | `claude`                                                        |
| `agent_loop_max_attempts`    | Max Agent→Verify cycles                                                        | `3`                                                             |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it   | `medium`                                                        |
| `agent_maker_instructions`   | Minimal fix from detect JSON; PR body with `Fixes #N`                          | Inline in caller workflow                                       |
| `agent_maker_max_turns`      | Max maker turns per attempt                                                    | `100`                                                           |
| `agent_maker_model`          | Maker model ID                                                                 | `claude-sonnet-5`                                               |
| `agent_maker_skill_name`     | Skill package                                                                  | `github-issue-autofix`                                          |
| `agent_tool_allowlist`       | Tool permission rules for the maker (read Issue, check existing PRs)           | `gh api`, `gh issue view`, `gh pr list`, `gh pr view`           |
| `agent_unchanged_verdict`    | Verdict when no file diff                                                      | `REJECT`                                                        |
| `budget_max_runs_per_day`    | Daily run cap                                                                  | `10`                                                            |
| `budget_max_tokens_per_day`  | Daily token cap                                                                | `1000000`                                                       |
| `delivery`                   | Where the output is delivered                                                  | `pr_create`                                                     |
| `detect_branch_match`        | Integration branch to fix against                                              | `main`                                                          |
| `detect_script`              | Domain detect script                                                           | `.agents/skills/github-issue-autofix/scripts/detect_autofix.sh` |
| `environment`                | GitHub Environment for env-scoped secrets                                      | `default`                                                       |
| `level`                      | Autonomy (`L2` — review PR)                                                    | `L2`                                                            |
| `loop_name`                  | Loop identifier                                                                | `github-issue-autofix`                                          |
| `pr_draft`                   | Create fix PR as draft when true                                               | `false` (default open)                                          |
| `state_branch`               | `.loop/*` persistence branch                                                   | `main`                                                          |

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
  loop → uses ci-loop-caller.yaml
           detect  → detect_autofix.sh
           execute → ci-loop-agent (level L2)
           finalize → pr_create (pr_draft from inputs)
```

Concurrency: `loop-github-issue-autofix-${issue_number || run_id}`.

## Triage handoff

Triage marks `triage:ready` and tells the human that adding `autofix` requests a fix PR. Autofix starts only from the `autofix` label, `workflow_dispatch`, or `repository_dispatch` with `client_payload.issue_number`; neither triage nor the Agent dispatches. To retry after a run that opened no PR (REJECT, budget, closed PR), remove and re-add `autofix`, or run `workflow_dispatch` with `issue_number`.
