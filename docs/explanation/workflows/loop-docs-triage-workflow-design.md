# Docs Triage Workflow Design

Workflow and domain design for the `loop-docs-triage` (`docs-triage`) loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-docs-triage.yaml` · skill `loop-docs-triage` · `scripts/detect_changes.sh`

## Purpose

Detect documentation drift from code changes on integration branches and open fix PRs after Skill triage.

### Supported use cases

- Cron scan of integration branches for git-diff facts (`changed_files`, `affected_docs`, …)
- Semantic triage and fix of High-Priority stale references or missing doc content
- Open an L2 review PR to the watch integration branch
- Coordinate with peer loops via [acting_on](../multi-branch-loops-design.md#cross-loop-coordination-acting_on) when multiple loops target the same branch

### Out of scope

- PR head healing (`LOOP_PULL_REQUESTS` default off)
- Hook-triggered or user-invoked doc sync — use **`docs-updater`** (common package) instead
- Creating documentation from scratch; non-documentation file edits
- Loop state and detect script management

| Package                 | Role                                       | Trigger                    |
| ----------------------- | ------------------------------------------ | -------------------------- |
| `docs-updater` (common) | Hook/manual git-diff → doc sync            | Pre-commit, user-invoked   |
| `loop-docs-triage`      | Cron loop: detect facts + Skill triage/fix | `on-loop-docs-triage.yaml` |

Detect script path: **`loop-docs-triage/scripts/detect_changes.sh`** (not `docs-updater/scripts/detect_changes.sh`).

Skill execution boundaries: `loop-docs-triage` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

### Modes

| Mode | Default | Behavior |
| `integration` | on | Detect on watch branch → fix PR to same branch |
| `pull_request`| off | not supported for this loop |

## Recommended `env`

```yaml
env:
  DEFAULT_LEVEL: L2
  LOOP_ALLOWLIST: docs/**/*.md,README.md,mkdocs.yml
  LOOP_DETECT_SCRIPT: .agents/skills/loop-docs-triage/scripts/detect_changes.sh
  LOOP_INTEGRATION_BRANCHES: main
  LOOP_NAME: docs-triage
  LOOP_PULL_REQUESTS: "false"
  SKILL_NAME: loop-docs-triage
```

Multi-branch example: `LOOP_INTEGRATION_BRANCHES: main,develop,release/*` with `LOOP_BRANCH_MATCH: glob`.

Full `LOOP_*` definitions: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_changes.sh` with `targets["integration:<branch>"].last_sha`.

Detect script outputs **facts** (not semantic findings):

| Field                                             | Role                                 |
| ------------------------------------------------- | ------------------------------------ |
| `changed_files`, `deleted_files`, `renamed_files` | Git diff summary                     |
| `affected_docs`                                   | Candidate doc paths for agent review |
| `commit_range`                                    | Passed through prompt context        |
| `skip`                                            | `true` when no doc-impacting change  |

**Skill** (`loop-docs-triage`) builds `findings[]` with semantic `reason` from these facts.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `finalize` = `open_pr`

**Do not** use ci-sweeper workflow-run / `gh run list` detect.

### Stable filters (detect only)

- Circuit breaker on `targets[key].consecutive_failures`
- Budget / `acting_on` (platform)

No infra/env classification — not applicable.

### State fields (per target key)

| Field                  | Role                                         |
| ---------------------- | -------------------------------------------- |
| `last_sha`             | Scan cursor; advances on successful finalize |
| `outcome`              | `pr-created`, `rejected`, `no-op`, …         |
| `consecutive_failures` | Circuit breaker                              |

No `workflow_run_id` / ci ledger.

## Execute

- Worktree from `target.from` on integration branch
- Verifier diff baseline: `to.branch`
- `verifier_context`: detect fact summary (changed files, affected docs). Platform always wires; may be brief

## Finalize

Always `open_pr` to `to.branch` at L2. L3 `push` rarely appropriate for loop-docs-triage; if enabled, requires explicit promotion review.

No `domain_persistence_script`.

Persistence: `state-docs-triage.json` on `LOOP_STATE_PUSH_BRANCH` via [finalize job](../loop-caller-workflows-design.md#finalize-job-matrix).

## Implementation Checklist

- [ ] `loop-docs-triage/scripts/detect_changes.sh` (facts output)
- [ ] `LOOP_INTEGRATION_BRANCHES` for additional branches
- [ ] Per-branch `targets["integration:<branch>"]`
- [ ] State migration: flat `last_sha` removed
- [ ] `target_matrix` through detect → matrix execute/finalize
- [ ] `verifier_context` on execute path

## Cross-Loop Note

If `loop-ci-sweeper` and `loop-docs-triage` both target `integration:main`, [acting_on](../multi-branch-loops-design.md#cross-loop-coordination-acting_on) and separate concurrency groups apply. CI failure on `main` is loop-ci-sweeper priority; doc-only drift is loop-docs-triage.

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../reference/specification.md)
