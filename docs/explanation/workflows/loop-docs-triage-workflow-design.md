# Docs Triage Workflow Design

Workflow and domain design for the `loop-docs-triage` (`docs-triage`) loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-docs-triage.yaml` · skill `loop-docs-triage` · `scripts/detect_changes.sh`

Shared caller keys (`AGENT_*`, `DEFAULT_*`, `LOOP_*`, `SKILL_NAME`): [Loop Caller `env` Reference](loop-caller-env-reference.md).

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

## Environment variables

All keys in workflow `env:` (alphabetically ordered). Multiline values (`AGENT_VERIFIER_CRITERIA`, `LOOP_PR_BODY`, `LOOP_PROMPT_INSTRUCTIONS`) are defined inline in `on-loop-docs-triage.yaml`.

Shared semantics for keys used across loops: [Loop Caller `env` Reference](loop-caller-env-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Variable                         | Description                                                                                           | Dogfood value                                                  |
| -------------------------------- | ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `AGENT_IMPLEMENTER_MAX_TURNS`    | Max implementer agent turns per loop attempt (one Agent→Verify cycle).                                | `"5"`                                                          |
| `AGENT_IMPLEMENTER_MODEL`        | Implementer model ID. Cursor: `agent --list-models`.                                                  | `grok-4.5-medium`                                              |
| `AGENT_LOOP_MAX_ATTEMPTS`        | Max Agent→Verify retry cycles before finalize records failure.                                        | `"3"`                                                          |
| `AGENT_VERIFIER_CRITERIA`        | Verifier APPROVE/REJECT rubric. Doc-only edits; factual consistency; no sensitive data.               | Inline in workflow YAML                                        |
| `AGENT_VERIFIER_MAX_TURNS`       | Max verifier agent turns per verification.                                                            | `"3"`                                                          |
| `AGENT_VERIFIER_MODEL`           | Verifier model ID. Cursor: `agent --list-models`.                                                     | `composer-2.5`                                                 |
| `DEFAULT_BASE_BRANCH`            | Default branch for state migration fallback.                                                          | `main`                                                         |
| `DEFAULT_ENGINE`                 | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                 | `cursor`                                                       |
| `DEFAULT_LEVEL`                  | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR.                                                | `L2`                                                           |
| `DOCS_TRIAGE_DOC_GLOBS`          | Comma-separated globs for documentation files in git-diff analysis. Forwarded to `detect_changes.sh`. | `docs/**/*.md,README.md`                                       |
| `DOCS_TRIAGE_EXTRA_FILES`        | Additional non-glob paths (site config) included in doc impact scan.                                  | `mkdocs.yml`                                                   |
| `LOOP_ALLOWLIST`                 | Comma-separated globs the implementer may modify. Must align with triage scope.                       | `docs/**/*.md,README.md,mkdocs.yml`                            |
| `LOOP_BUDGET_MAX_RUNS_PER_DAY`   | Daily run cap keyed by `LOOP_NAME`.                                                                   | `"1"`                                                          |
| `LOOP_BUDGET_MAX_TOKENS_PER_DAY` | Daily aggregated token cap across loops.                                                              | `"500000"`                                                     |
| `LOOP_DETECT_SCRIPT`             | Domain detect script path. Not `docs-updater` script (hook/manual only).                              | `.agents/skills/loop-docs-triage/scripts/detect_changes.sh`    |
| `LOOP_FINALIZE_INTEGRATION`      | Finalize strategy for integration targets: `open_pr` or `push` (L3).                                  | `open_pr`                                                      |
| `LOOP_INFER_FILES_PATTERN`       | Extended regex to infer file paths from verifier text.                                                | See workflow YAML                                              |
| `LOOP_INTEGRATION_BRANCHES`      | Comma-separated integration branch patterns to watch for doc drift.                                   | `main`                                                         |
| `LOOP_MAX_TARGETS_PER_SCHEDULE`  | Max targets per cron tick after priority/`acting_on` filters.                                         | `"3"`                                                          |
| `LOOP_NAME`                      | Loop identifier; state file `.loop/state-docs-triage.json`.                                           | `docs-triage`                                                  |
| `LOOP_NO_CHANGES_VERDICT`        | `APPROVE` or `REJECT` when implementer produces no file diff.                                         | `REJECT`                                                       |
| `LOOP_PR_BODY`                   | Static markdown prefix for finalize PR body.                                                          | Inline in workflow YAML                                        |
| `LOOP_PR_TITLE`                  | PR title when finalize strategy is `open_pr`.                                                         | `fix(docs): automated documentation update (loop-docs-triage)` |
| `LOOP_PROMPT_INSTRUCTIONS`       | Domain instructions: address triage findings; preserve doc structure.                                 | Inline in workflow YAML                                        |
| `LOOP_PULL_REQUESTS`             | `"true"` enumerates open PR heads; docs-triage uses integration branches only.                        | `"false"`                                                      |
| `LOOP_STATE_PUSH_BRANCH`         | Branch for `.loop/*` persistence commits.                                                             | `main`                                                         |
| `SKILL_NAME`                     | Skill package to invoke.                                                                              | `loop-docs-triage`                                             |

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
