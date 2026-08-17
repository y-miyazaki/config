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

Single intake for Issue→PR autofix: `labeled(autofix)` + `repository_dispatch` (`loop-github-issue-autofix`) + `workflow_dispatch` → **branch** caller (L2, `may_edit: true`, `write_target: fix`, `delivery: open_pr`).

Detect skips when an open/draft PR already references the Issue with a closing keyword (`Fixes #N`, etc.). PR draft/open is controlled by caller `pr_draft` (**default open**).

### Supported use cases

- `issues` labeled `autofix` → branch caller detect + L2 agent + fix PR
- `repository_dispatch` (`loop-github-issue-autofix`) from triage trusted hook when `triage:ready` and `autofix`
- `workflow_dispatch` with `issue_number` (optional `pr_draft`) for manual autofix

### Out of scope

- Issue triage / label classification (axis 1 — see [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md))
- PR revision from review feedback (axis 3 — see [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md))
- L3 auto-merge on the fix PR
- Automatic autofix without the `autofix` label (`repository_dispatch` / `workflow_dispatch` remain explicit human paths)
- Agent-initiated `repository_dispatch` (trusted hook only)
- PR head mode (`pr_enabled` default off) — fixes target integration branch via `open_pr`
- Second fix PR when an open/draft PR already references the Issue with a closing keyword (`Fixes #N`, etc.)

Skill execution boundaries: `github-issue-autofix` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

## Caller inputs

Keys are passed in `on-loop-github-issue-autofix.yaml` via `with:` on `ci-loop-caller.yaml`. Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

| Input / JSON key                 | Description                                           | Dogfood value                                                   |
| -------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------- |
| `agent_implementer_instructions` | Minimal fix from detect JSON; PR body with `Fixes #N` | Inline in caller workflow                                       |
| `agent_implementer_max_turns`    | Max implementer turns per attempt                     | `8`                                                             |
| `agent_implementer_model`        | Implementer model ID                                  | `cursor-grok-4.5-low`                                           |
| `agent_implementer_skill_name`   | Skill package                                         | `github-issue-autofix`                                          |
| `agent_loop_max_attempts`        | Max Agent→Verify cycles                               | `3`                                                             |
| `agent_verifier_instructions`    | APPROVE/REJECT rubric                                 | Inline in caller workflow                                       |
| `agent_verifier_max_turns`       | Max verifier turns                                    | `3`                                                             |
| `agent_verifier_model`           | Verifier model ID                                     | `composer-2.5`                                                  |
| `agent_verifier_skill_name`      | Checker skill                                         | `loop-verifier`                                                 |
| `allowlist`                      | File edit allowlist (empty = skill default)           | `""`                                                            |
| `branch_match`                   | Integration branch to fix against                     | `main`                                                          |
| `branch_state`                   | `.loop/*` persistence branch                          | `main`                                                          |
| `budget_max_runs_per_day`        | Daily run cap                                         | `10`                                                            |
| `budget_max_tokens_per_day`      | Daily token cap                                       | `1000000`                                                       |
| `delivery`                       | Platform delivery after APPROVE                       | `open_pr`                                                       |
| `denylist`                       | Denylist globs                                        | `""`                                                            |
| `detect_script`                  | Domain detect script                                  | `.agents/skills/github-issue-autofix/scripts/detect_autofix.sh` |
| `engine`                         | AI engine                                             | `cursor`                                                        |
| `environment`                    | GitHub Environment for env-scoped secrets             | `default`                                                       |
| `git_landing_integration`        | Advanced git landing override                         | `open_pr`                                                       |
| `level`                          | Autonomy (`L2` — review PR)                           | `L2`                                                            |
| `loop_name`                      | Loop identifier                                       | `github-issue-autofix`                                          |
| `may_edit`                       | Agent worktree edit gate                              | `true`                                                          |
| `no_changes_verdict`             | Verdict when no file diff                             | `REJECT`                                                        |
| `pr_draft`                       | Create fix PR as draft when true                      | `false` (default open)                                          |
| `write_target`                   | Agent artifact type                                   | `fix`                                                           |

### Domain detect environment (`detect_domain_env_json`)

```yaml
detect_domain_env_json: ${{ format('{{"ISSUE_NUMBER":{0}}}', toJSON(format('{0}', github.event.issue.number || github.event.client_payload.issue_number || inputs.issue_number || ''))) }}
```

| JSON key / env var | Description         | Notes               |
| ------------------ | ------------------- | ------------------- |
| `ISSUE_NUMBER`     | Target Issue number | Required to proceed |

## Caller shape

```text
on-loop-github-issue-autofix.yaml
  loop → uses ci-loop-caller.yaml
           detect  → detect_autofix.sh
           execute → ci-loop-agent (may_edit=true)
           finalize → open_pr (pr_draft from inputs)
```

Concurrency: `loop-github-issue-autofix-${issue_number || run_id}`.

## Triage handoff

When Issue has `triage:ready` and `autofix`, triage detect emits dispatch flags; trusted hook posts `repository_dispatch` (`loop-github-issue-autofix`). Agent never dispatches.
