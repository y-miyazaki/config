# Refactor Workflow Design

Workflow and domain design for the `loop-refactor` (`refactor`) action loop.

| Layer        | Document                                                                                                |
| ------------ | ------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                            |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md)                                      |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                |
| Skill spec   | [Refactor skill & loop design](../../../superpowers/specs/2026-07-21-refactor-skill-and-loop-design.md) |

**Artifacts:** `on-loop-refactor.yaml` · skill `loop-refactor` · `scripts/detect_refactor.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Detect mechanical structure hints on integration branches and open fix PRs after bounded O1/O2 refactors.

### Supported use cases

- Cron scan of integration branches for H1 hints (`duplication_block`, `oversized_unit`)
- Apply one structural refactor per hint with stack validation (A')
- Open an L2 review PR to the watch integration branch
- Coordinate with peer loops via [workflow concurrency](../multi-branch-loops-design.md#cross-loop-coordination-workflow-concurrency)

### Out of scope

- PR head healing (`pull_requests` default off)
- Interactive or architecture-improvement intent (O3 proposal path) — use skill `refactor` manually
- Lint/SAST smell scores as primary detect or repair mission
- `loop-report-tech-debt` report input or Apply under `report-*` names
- Sonar CPD default-on (future caller opt-in for duplication only)

| Package         | Role                                                 | Trigger                 |
| --------------- | ---------------------------------------------------- | ----------------------- |
| `refactor`      | Interactive / agent-invoked O1/O2 + O3 proposal path | User-invoked            |
| `loop-refactor` | Cron loop: detect H1 hints + structural apply        | `on-loop-refactor.yaml` |

### Separation from refactor skill

Detect script path: **`loop-refactor/scripts/detect_refactor.sh`**.

Entry skill (`loop-refactor`) wraps the `refactor` contract: **structural intent only**, one hint → one target, O2 cap. Architecture-improvement language in user prompts is out of scope for this loop.

### Modes

| Mode           | Default | Behavior                                       |
| -------------- | ------- | ---------------------------------------------- |
| `integration`  | on      | Detect on watch branch → fix PR to same branch |
| `pull_request` | off     | not supported for this loop                    |

## Caller inputs

Keys are passed in `on-loop-refactor.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_verifier_criteria`, `prompt_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Input / JSON key                                           | Description                                                                          | Dogfood value                                             |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------- |
| `agent_implementer_max_turns`                              | Max implementer agent turns per loop attempt (one Agent→Verify cycle).               | `5`                                                       |
| `agent_implementer_model`                                  | Implementer model ID. Cursor: `agent --list-models`.                                 | `cursor-grok-4.5-low`                                     |
| `agent_loop_max_attempts`                                  | Max Agent→Verify retry cycles before finalize records failure.                       | `3`                                                       |
| `agent_verifier_criteria`                                  | Verifier APPROVE/REJECT rubric. O1/O2 only; no architecture/GoF/cross-package diffs. | Inline in caller workflow                                 |
| `agent_verifier_max_turns`                                 | Max verifier agent turns per verification.                                           | `3`                                                       |
| `agent_verifier_model`                                     | Verifier model ID. Cursor: `agent --list-models`.                                    | `composer-2.5`                                            |
| `allowlist`                                                | Comma-separated globs the implementer may modify. Tight dogfood scope.               | `.apm/packages/**,scripts/**`                             |
| `branch_match`                                             | Comma-separated integration branch patterns to watch.                                | `main`                                                    |
| `branch_state`                                             | Branch for `.loop/*` persistence, state migration, and watch fallback.               | `main`                                                    |
| `budget_max_runs_per_day`                                  | Daily run cap keyed by `loop_name`.                                                  | `1`                                                       |
| `budget_max_tokens_per_day`                                | Daily aggregated token cap across loops.                                             | `500000`                                                  |
| `detect_domain_env_json` → `REFACTOR_DUP_MIN_LINES`        | Minimum consecutive non-empty lines for `duplication_block` hints.                   | `8`                                                       |
| `detect_domain_env_json` → `REFACTOR_OVERSIZED_FILE_LINES` | File line count threshold for `oversized_unit` hints (size only).                    | `400`                                                     |
| `detect_domain_env_json` → `REFACTOR_SCAN_GLOBS`           | Comma-separated globs for scan roots.                                                | `.apm/packages/**,scripts/**`                             |
| `detect_script`                                            | Domain detect script path.                                                           | `.agents/skills/loop-refactor/scripts/detect_refactor.sh` |
| `engine`                                                   | AI engine (`claude`, `copilot`, `codex`, `cursor`).                                  | `cursor`                                                  |
| `finalize_integration`                                     | Finalize strategy for integration targets: `open_pr` or `push` (L3).                 | `open_pr`                                                 |
| `infer_files_pattern`                                      | Extended regex to infer file paths from verifier text.                               | See caller workflow                                       |
| `level`                                                    | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR.                               | `L2`                                                      |
| `loop_name`                                                | Loop identifier; state file `.loop/state-refactor.json`.                             | `refactor`                                                |
| `max_targets_per_schedule`                                 | Max hints processed per cron tick.                                                   | `1`                                                       |
| `no_changes_verdict`                                       | `APPROVE` or `REJECT` when implementer produces no file diff.                        | `REJECT`                                                  |
| `pr_body`                                                  | Optional static prefix (dogfood: `""`).                                              | `""`                                                      |
| `pr_title`                                                 | PR title when finalize strategy is `open_pr`.                                        | `refactor(loop): structural improvement (loop-refactor)`  |
| `prompt_instructions`                                      | Domain instructions: invoke `refactor` structural path; stack validation via A'.     | Inline in caller workflow                                 |
| `pull_requests`                                            | Enumerate open PR heads. Refactor loop uses integration branches only.               | `false`                                                   |
| `skill_name`                                               | Skill package to invoke.                                                             | `loop-refactor`                                           |

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_refactor.sh` with `targets["integration:<branch>"].last_sha`.

Detect script outputs **facts** (not semantic repair decisions):

| Field          | Role                                                        |
| -------------- | ----------------------------------------------------------- |
| `hints[]`      | Mechanical H1 hints (`duplication_block`, `oversized_unit`) |
| `hint.kind`    | Closed set only                                             |
| `hint.path`    | Primary file path for the hint                              |
| `hint.detail`  | Locator (line range, duplicate peer path, line count)       |
| `commit_range` | Passed through prompt context when scope is `range`         |
| `skip`         | `true` when no hints after allowlist filter                 |

**Skill** (`loop-refactor`) maps the first actionable hint to one `refactor` target per run.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `finalize` = `open_pr`

### Stable filters (detect only)

- Circuit breaker on `targets[key].consecutive_failures`
- Budget (platform)
- Prune generated trees, `docs/report/**`, `node_modules/**`, secrets paths

No infra/env classification — not applicable.

### State fields (per target key)

| Field                  | Role                                                               |
| ---------------------- | ------------------------------------------------------------------ |
| `last_sha`             | Scan cursor; advances when fix PR merges (`on-loop-state-promote`) |
| `pending`              | Written at finalize on `open_pr`; promoted to `last_sha` on merge  |
| `outcome`              | `pr-created`, `rejected`, `no-op`, …                               |
| `consecutive_failures` | Circuit breaker                                                    |

## Execute

- Worktree from `target.from` on integration branch
- Verifier diff baseline: `to.branch`
- `verifier_context`: detect hint summary (kind, path, detail)
- **Intent:** always `structural` — O2 cap; no architecture Phase A/B
- One hint → one target; follow `refactor` skill O1/O2 contract via caller `prompt_instructions` (A')

## Finalize

PR body is composed by `loop-finalize` from agent `## Overview` / `## Summary` (skill-owned) plus mechanical sections. Dogfood sets `pr_body: ""`. See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

Always `open_pr` to `to.branch` at L2.

No `domain_persistence_script`.

**Merge-gated cursor:** Same platform rule as all L2 `open_pr` loops — `pending` at finalize, `last_sha` on fix PR merge via `on-loop-state-promote.yaml`.

## State delivery

See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) for platform rules.

**Target (dogfood):** merge-gated `pending` + `on-loop-state-promote` — same as docs-triage.

Persistence: `state-refactor.json` on `branch_state` via [finalize inside ci-loop-agent](../loop-caller-workflows-design.md#finalize-inside-ci-loop-agent).

## Implementation Checklist

Shared platform contract — see [Multi-Branch Loops Design](../multi-branch-loops-design.md#implementation-phases).

### Platform (all loops)

- [x] `loop-refactor/scripts/detect_refactor.sh` (H1 facts output)
- [x] `on-loop-refactor.yaml` dogfood caller via `ci-loop-caller`
- [x] `branch_match` + per-branch `targets["integration:<branch>"]`
- [x] State migration: flat `last_sha` removed (`targets` map only)
- [x] `target_matrix` through detect → matrix execute/finalize
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.hints` branch)
- [x] Merge-gated state via `on-loop-state-promote.yaml` (`pending` → `last_sha`)
- [x] Readable PR body: agent Overview/Summary + finalize Run Metadata (`render_pr_body.sh`, `loop-notify-pr`)

### Loop-specific

- [x] `loop-refactor` skill + references
- [x] Bats suite for detect script (TEST-00)

## Cross-Loop Note

`loop-refactor` is orthogonal to `loop-ci-sweeper` and `loop-report-tech-debt`. It does not consume tech-debt reports. If CI fails during a refactor PR, `loop-ci-sweeper` owns repair.

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Refactor skill & loop design](../../../superpowers/specs/2026-07-21-refactor-skill-and-loop-design.md)
- [Specification](../../../reference/specification.md)
