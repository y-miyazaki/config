# Issue Autofix Workflow Design

| Layer        | Document                                                                 |
| ------------ | ------------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)             |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (branch)|
| Spec         | [Issue Autofix and PR Revise Full Design](../../../superpowers/specs/2026-08-11-issue-autofix-pr-revise-full-design.md) |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                 |

**Artifacts:** `on-loop-issue-autofix.yaml` · skill `issue-autofix` · `detect_autofix.sh` · `ci-loop-caller.yaml`

## Purpose

Single intake for Issue→PR autofix: `labeled(autofix)` + `repository_dispatch` (`loop-issue-autofix`) + `workflow_dispatch` → **branch** caller (L2, `may_edit: true`, `write_target: fix`, `delivery: open_pr`).

Detect skips when an open/draft PR already references the Issue with a closing keyword (`Fixes #N`, etc.). PR draft/open is controlled by caller `pr_draft` (**default open**).

## Caller shape

```text
on-loop-issue-autofix.yaml
  loop → uses ci-loop-caller.yaml
           detect  → detect_autofix.sh
           execute → ci-loop-agent (may_edit=true)
           finalize → open_pr (pr_draft from inputs)
```

Concurrency: `loop-autofix-${issue_number || run_id}`.

## Triage handoff

When Issue has `triage:ready` and `autofix`, triage detect emits dispatch flags; trusted hook posts `repository_dispatch` (`loop-issue-autofix`). Agent never dispatches.
