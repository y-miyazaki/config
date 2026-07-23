# Docs Triage Workflow Design

Workflow and domain design for the docs-triage loop (`on-loop-docs-triage.yaml`).

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-docs-triage.yaml` · skill `docs-updater` (loop path) · `scripts/detect_changes.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Detect documentation drift from code changes on integration branches and open fix PRs after Skill triage.

### Supported use cases

- Cron scan of integration branches for git-diff facts (`changed_files`, `affected_docs`, …)
- Semantic triage and fix of High-Priority stale references or missing doc content
- Open an L2 review PR to the watch integration branch
- Coordinate with peer loops via [workflow concurrency](../multi-branch-loops-design.md#cross-loop-coordination-workflow-concurrency) when multiple loops target the same branch

### Out of scope

- PR head healing (`pull_requests` default off)
- Creating documentation from scratch; non-documentation file edits
- Loop state and detect script management

### docs-updater dual paths

| Path               | Trigger                    | Input                                    |
| ------------------ | -------------------------- | ---------------------------------------- |
| Interactive / hook | Pre-commit, user-invoked   | `scripts/detect_changes.sh` JSON         |
| Loop               | `on-loop-docs-triage.yaml` | `findings[]` from `loop-prompt-generate` |

Both paths share `docs-updater/scripts/detect_changes.sh` for mechanical facts. The loop caller maps detect output into semantic `findings[]` before invoking the skill.

### Modes

| Mode           | Default | Behavior                                       |
| -------------- | ------- | ---------------------------------------------- |
| `integration`  | on      | Detect on watch branch → fix PR to same branch |
| `pull_request` | off     | not supported for this loop                    |

## Caller inputs

Keys are passed in `on-loop-docs-triage.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_verifier_criteria`, `prompt_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Input / JSON key                                     | Description                                                                                                                                                                                                               | Dogfood value                                            |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `agent_implementer_max_turns`                        | Max implementer agent turns per loop attempt (one Agent→Verify cycle).                                                                                                                                                    | `5`                                                      |
| `agent_implementer_model`                            | Implementer model ID. Cursor: `agent --list-models`.                                                                                                                                                                      | `cursor-grok-4.5-low`                                    |
| `agent_loop_max_attempts`                            | Max Agent→Verify retry cycles before finalize records failure.                                                                                                                                                            | `3`                                                      |
| `agent_verifier_criteria`                            | Verifier APPROVE/REJECT rubric. Doc-only edits; factual consistency; no sensitive data.                                                                                                                                   | Inline in caller workflow                                |
| `agent_verifier_max_turns`                           | Max verifier agent turns per verification.                                                                                                                                                                                | `3`                                                      |
| `agent_verifier_model`                               | Verifier model ID. Cursor: `agent --list-models`.                                                                                                                                                                         | `composer-2.5`                                           |
| `allowlist`                                          | Comma-separated globs the implementer may modify. Must align with triage scope.                                                                                                                                           | `docs/**/*.md,README.md,mkdocs.yml`                      |
| `branch_match`                                       | Comma-separated integration branch patterns to watch for doc drift.                                                                                                                                                       | `main`                                                   |
| `branch_state`                                       | Branch for `.loop/*` persistence, state migration, and watch fallback.                                                                                                                                                    | `main`                                                   |
| `budget_max_runs_per_day`                            | Daily run cap keyed by `loop_name`. Caller input; `.loop/loop-budget.json` overrides when present.                                                                                                                        | `1` (caller); effective `5` via `.loop/loop-budget.json` |
| `budget_max_tokens_per_day`                          | Daily aggregated token cap across loops.                                                                                                                                                                                  | `500000`                                                 |
| `detect_domain_env_json` → `DOCS_TRIAGE_DOC_GLOBS`   | Comma-separated globs for documentation files in git-diff analysis.                                                                                                                                                       | `docs/**/*.md,README.md`                                 |
| `detect_domain_env_json` → `DOCS_TRIAGE_EXTRA_FILES` | Additional non-glob paths (site config) included in doc impact scan.                                                                                                                                                      | `mkdocs.yml`                                             |
| `detect_script`                                      | Domain detect script path (shared with docs-updater hook path).                                                                                                                                                           | `.agents/skills/docs-updater/scripts/detect_changes.sh`  |
| `engine`                                             | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                                                                                     | `cursor`                                                 |
| `delivery`                                           | Platform delivery after APPROVE (`open_pr` for dogfood).                                                                                                                                                                  | `open_pr`                                                |
| `infer_files_pattern`                                | Extended regex to infer file paths from verifier text.                                                                                                                                                                    | See caller workflow                                      |
| `level`                                              | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR.                                                                                                                                                                    | `L2`                                                     |
| `loop_name`                                          | Loop identifier; state file `.loop/state-docs-triage.json`.                                                                                                                                                               | `docs-triage`                                            |
| `max_targets_per_schedule`                           | Max targets per cron tick after priority filters.                                                                                                                                                                         | `3`                                                      |
| `may_edit`                                           | Agent worktree edit gate (`true` for dogfood).                                                                                                                                                                            | `true`                                                   |
| `no_changes_verdict`                                 | `APPROVE` or `REJECT` when implementer produces no file diff.                                                                                                                                                             | `REJECT`                                                 |
| `pr_body`                                            | Optional static prefix (dogfood: `""`). `loop-finalize` composes agent Overview/Summary + mechanical sections. See [Loop PR Body Readable Design](../../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md). | `""`                                                     |
| `pr_title`                                           | PR title when finalize strategy is `open_pr`.                                                                                                                                                                             | `fix(docs): automated documentation update`              |
| `prompt_instructions`                                | Domain instructions: run docs-updater loop path; address triage findings.                                                                                                                                                 | Inline in caller workflow                                |
| `pull_requests`                                      | Enumerate open PR heads. Docs-triage uses integration branches only.                                                                                                                                                      | `false`                                                  |
| `skill_name`                                         | Skill package to invoke.                                                                                                                                                                                                  | `docs-updater`                                           |
| `write_target`                                       | Agent artifact when `may_edit` is true (`fix` for dogfood).                                                                                                                                                               | `fix`                                                    |

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

**Skill** (`docs-updater` loop path) builds `findings[]` with semantic `reason` from these facts.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `finalize` = `open_pr`

**Do not** use ci-sweeper workflow-run / `gh run list` detect.

### Stable filters (detect only)

- Circuit breaker on `targets[key].consecutive_failures`
- Budget (platform)

No infra/env classification — not applicable.

### State fields (per target key)

| Field                  | Role                                                               |
| ---------------------- | ------------------------------------------------------------------ |
| `last_sha`             | Scan cursor; advances when fix PR merges (`on-loop-state-promote`) |
| `pending`              | Written at finalize on `open_pr`; promoted to `last_sha` on merge  |
| `outcome`              | `pr-created`, `rejected`, `no-op`, …                               |
| `consecutive_failures` | Circuit breaker                                                    |

No `workflow_run_id` / ci ledger.

## Execute

- Worktree from `target.from` on integration branch
- Verifier diff baseline: `to.branch`
- `verifier_context`: detect fact summary (changed files, affected docs). Platform always wires; may be brief

## Finalize

PR body is composed by `loop-finalize` from agent `## Overview` / `## Summary` (skill-owned) plus mechanical sections. Dogfood sets `pr_body: ""`. See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

Always `open_pr` to `to.branch` at L2. L3 `push` rarely appropriate for docs-triage; if enabled, requires explicit promotion review.

No `domain_persistence_script`.

**Merge-gated cursor:** Same platform rule as all L2 `open_pr` loops — `pending` at finalize, `last_sha` on fix PR merge via `on-loop-state-promote.yaml`. See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy).

## State delivery

See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) for platform rules.

**Target (dogfood):** merge-gated `pending` + `on-loop-state-promote` — same as changelog.

Persistence: `state-docs-triage.json` on `branch_state` via [finalize inside ci-loop-agent](../loop-caller-workflows-design.md#finalize-inside-ci-loop-agent).

## Implementation Checklist

Shared platform contract — see [Multi-Branch Loops Design](../multi-branch-loops-design.md#implementation-phases).

### Platform (all loops)

- [x] `docs-updater/scripts/detect_changes.sh` (facts output)
- [x] `on-loop-docs-triage.yaml` dogfood caller via `ci-loop-caller`
- [x] `branch_match` + per-branch `targets["integration:<branch>"]`
- [x] State migration: flat `last_sha` removed (`targets` map only)
- [x] `target_matrix` through detect → matrix execute/finalize
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.affected_docs` branch)
- [x] Merge-gated state via `on-loop-state-promote.yaml` (`pending` → `last_sha`)
- [x] Readable PR body: agent Overview/Summary + finalize Run Metadata (`render_pr_body.sh`, `loop-notify-pr`)

### Loop-specific

- [x] `docs-updater` skill loop path + references
- [x] Bats suite for detect script (TEST-00)

## Cross-Loop Note

If `ci-sweeper` and docs-triage both target `integration:main`, [workflow concurrency](../multi-branch-loops-design.md#cross-loop-coordination-workflow-concurrency) and separate concurrency groups apply. CI failure on `main` is ci-sweeper priority; doc-only drift is docs-triage.

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
