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

### Supported use cases

- `issues` opened/reopened/labeled/unlabeled → entity detect + L1 agent
- `issue_comment` created (human answers while awaiting info)
- `workflow_dispatch` with `issue_number` for manual re-triage

### Out of scope

- Issue→PR autofix (axis 2 — see [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md))
- PR revision from review feedback (axis 3 — see [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md))
- Mention / `@` triggers on triage events
- Interactive AskUserQuestion path (automation-first)

### Deferred dogfood

Live `workflow_dispatch` dry-run requires repository secrets (`AGENT_TOKEN`, optional bot app). Treat end-to-end Actions dogfood as deferred until secrets are available; local verification is Bats + `actionlint`.

## Caller inputs

Keys are passed in `on-loop-github-issue-triage.yaml` via `with:` on `ci-loop-caller-entity.yaml`. Entity subset of [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

| Input / JSON key                 | Description                                          | Dogfood value                                                            |
| -------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------ |
| `agent_implementer_instructions` | Domain implementer task (triage skill)               | Inline in caller workflow                                                |
| `agent_implementer_max_turns`    | Max implementer turns per attempt                    | `5`                                                                      |
| `agent_implementer_model`        | Implementer model ID                                 | `cursor-grok-4.5-low`                                                    |
| `agent_implementer_skill_name`   | Skill package                                        | `github-issue-triage`                                                    |
| `agent_loop_max_attempts`        | Max Agent→Verify cycles                              | `3`                                                                      |
| `agent_verifier_instructions`    | APPROVE/REJECT rubric (allowlisted labels only)      | Inline in caller workflow                                                |
| `agent_verifier_max_turns`       | Max verifier turns                                   | `3`                                                                      |
| `agent_verifier_model`           | Verifier model ID                                    | `composer-2.5`                                                           |
| `agent_verifier_skill_name`      | Checker skill                                        | `loop-verifier`                                                          |
| `allowlist`                      | File edit allowlist (empty = no file edits)          | `""`                                                                     |
| `branch_state`                   | `.loop/*` persistence branch                         | `main`                                                                   |
| `budget_max_runs_per_day`        | Daily run cap                                        | `20`                                                                     |
| `budget_max_tokens_per_day`      | Daily token cap                                      | `1000000`                                                                |
| `delivery`                       | Platform delivery (`none` — L1 comments/labels only) | `none`                                                                   |
| `denylist`                       | Denylist globs                                       | `""`                                                                     |
| `detect_script`                  | Domain detect script                                 | `.agents/skills/github-issue-triage/scripts/detect_issue.sh`             |
| `dispatch_hook_script`           | Trusted post-detect hook (autofix dispatch)          | `.agents/skills/github-issue-triage/scripts/hooks/on_detect_dispatch.sh` |
| `engine`                         | AI engine                                            | `cursor`                                                                 |
| `environment`                    | GitHub Environment for env-scoped secrets            | `default`                                                                |
| `level`                          | Autonomy (`L1` — no PR)                              | `L1`                                                                     |
| `loop_name`                      | Loop identifier                                      | `github-issue-triage`                                                    |
| `may_edit`                       | Agent worktree edit gate                             | `false`                                                                  |
| `no_changes_verdict`             | Verdict when no file diff                            | `APPROVE`                                                                |
| `write_target`                   | Agent artifact type                                  | `report`                                                                 |

### Domain detect environment (`detect_domain_env_json`)

`{}` on webhook paths. `workflow_dispatch` may pass `ISSUE_NUMBER`:

```yaml
detect_domain_env_json: ${{ github.event_name == 'workflow_dispatch' && format('{{"ISSUE_NUMBER":{0}}}', toJSON(inputs.issue_number)) || '{}' }}
```

Detect script env (explicit or hydrated from `GITHUB_EVENT_PATH`): `ISSUE_NUMBER`, `ISSUE_TITLE`, `ISSUE_BODY`, `ISSUE_LABELS_JSON`, `ISSUE_EVENT_NAME`, `ISSUE_EVENT_ACTION`, `ISSUE_COMMENT_ID`, `ISSUE_ACTOR`, `ISSUE_ACTOR_TYPE`, `ISSUE_COMMENT_USER_TYPE`.

## Caller shape

```text
on-loop-github-issue-triage.yaml
  loop → uses ci-loop-caller-entity.yaml
           detect  → loop-entity-detect
                       (detect_issue.sh reads GITHUB_EVENT_PATH;
                        workflow_dispatch may pass ISSUE_NUMBER via detect_domain_env_json)
           execute → ci-loop-agent (issues: write; finalize-l1 run-log; finalize_enabled=false so no PR)
           record-skip → budget | circuit_breaker
```

No caller `prepare` job — event mapping lives in the skill detect script (E17).

## Detect contract

Skip when actor or comment author is Bot, or when `triage:failed` is present (E7). When skip=false, emit `result.handoff_key` = `entity:issue:<N>` (S1).

## Skill contract

See `.apm/packages/github/.apm/skills/github-issue-triage/SKILL.md` and `references/category-*.md`.
