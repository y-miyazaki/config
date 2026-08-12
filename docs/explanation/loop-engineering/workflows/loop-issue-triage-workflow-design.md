# Issue Triage Workflow Design

Workflow and domain design for the `issue-triage` entity loop.

| Layer        | Document                                                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                                                       |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (entity)                                                          |
| Spec         | [Issue Triage Entity Loops](../../../superpowers/specs/2026-08-11-issue-triage-entity-loops-design.md)                             |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                                           |

**Artifacts:** `on-loop-issue-triage.yaml` · skill `issue-triage` · `detect_issue.sh` · `ci-loop-caller-entity.yaml`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md) (entity subset).

## Purpose

On Issue / issue_comment events, classify the Issue when confident, apply allowlisted triage labels, and post analysis or clarifying questions as comments (L1). Does not open PRs.

### Supported use cases

- `issues` opened/reopened/labeled/unlabeled → entity detect + L1 agent
- `issue_comment` created (human answers while awaiting info)
- `workflow_dispatch` with `issue_number` for manual re-triage

### Out of scope

- Issue→PR autofix (axis 2 — see [Issue Autofix Workflow Design](loop-issue-autofix-workflow-design.md))
- PR revision from review feedback (axis 3 — see [PR Revise Workflow Design](loop-pr-revise-workflow-design.md))
- Mention / `@` triggers on triage events
- Interactive AskUserQuestion path (automation-first)

### Deferred dogfood

Live `workflow_dispatch` dry-run requires repository secrets (`AGENT_TOKEN`, optional bot app). Treat end-to-end Actions dogfood as deferred until secrets are available; local verification is Bats + `actionlint`.

## Caller shape

```text
on-loop-issue-triage.yaml
  loop → uses ci-loop-caller-entity.yaml
           detect  → loop-entity-detect
                       (detect_issue.sh reads GITHUB_EVENT_PATH;
                        workflow_dispatch may pass ISSUE_NUMBER via detect_domain_env_json)
           execute → ci-loop-agent (issues: write; finalize_enabled=false)
           record-skip → budget only
```

No caller `prepare` job — event mapping lives in the skill detect script (E17).

## Detect contract

Env (explicit or hydrated from `GITHUB_EVENT_PATH`): `ISSUE_NUMBER`, `ISSUE_TITLE`, `ISSUE_BODY`, `ISSUE_LABELS_JSON`, `ISSUE_EVENT_NAME`, `ISSUE_EVENT_ACTION`, `ISSUE_COMMENT_ID`, `ISSUE_ACTOR`, `ISSUE_ACTOR_TYPE`, `ISSUE_COMMENT_USER_TYPE`.

Skip when actor or comment author is Bot, or when `triage:failed` is present (E7). When skip=false, emit `result.handoff_key` = `entity:issue:<N>` (S1).

## Skill contract

See `.apm/packages/common/.apm/skills/issue-triage/SKILL.md` and `references/category-*.md`.
