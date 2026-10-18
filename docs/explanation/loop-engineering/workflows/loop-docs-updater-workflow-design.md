# Docs Updater Workflow Design

Workflow and domain design for the docs-updater loop (`on-loop-docs-updater.yaml`).

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-docs-updater.yaml` · skill `docs-updater` · `docs-updater/scripts/detect_changes.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Detect documentation drift from code changes on integration branches and open fix PRs after the docs-updater skill runs.

### Supported use cases

- Cron scan of integration branches for git-diff facts (`changed_files`, `affected_docs`, …)
- Semantic review and fix of high-priority stale references or missing doc content
- Open an L2 review PR to the watch integration branch
- Coordinate with peer loops via [workflow concurrency](../multi-branch-loops-design.md#cross-loop-coordination-workflow-concurrency) when multiple loops target the same branch

### Out of scope

- PR head healing (`detect_pr_enabled` default off)
- Creating documentation from scratch; non-documentation file edits
- Loop state and detect script management

### docs-updater dual paths

| Path               | Trigger                     | Input                                                                    |
| ------------------ | --------------------------- | ------------------------------------------------------------------------ |
| Interactive / hook | Pre-commit, user-invoked    | `scripts/detect_changes.sh` JSON (mechanical facts)                      |
| Loop               | `on-loop-docs-updater.yaml` | Same detect script facts in prompt; skill builds `findings[]` in Execute |

Both paths share `docs-updater/scripts/detect_changes.sh` for mechanical facts only. The **entry skill** (Execute) builds semantic `findings[]` — detect and the caller do not emit semantic classifications.

### Detect scope axis (normative)

Normative cross-skill definition: [Detect scope axis and interactive discovery](../../../superpowers/specs/2026-08-10-detect-scope-axis-and-interactive-discovery-design.md).

| Path                  | `--scope`             | Notes                                                                                       |
| --------------------- | --------------------- | ------------------------------------------------------------------------------------------- |
| Loop (state cursor)   | `range --since <sha>` | Unchanged — detect limits to `<since>..HEAD` changes                                        |
| git hook / pre-commit | `staged`              | Index diff only; untracked files are not visible until added                                |
| Interactive free-form | `all`                 | **Breaking (2026-08-10):** full candidate-doc enumeration — not `git diff HEAD` + untracked |

Loop callers must not rely on `--scope all` for worktree sync; use `staged` (hook) or `range` (automation).

#### Detect → findings pipeline (loop domain)

1. **Detect script** emits mechanical facts: `changed_files`, `deleted_files`, `renamed_files`, `affected_docs`, `commit_range`, `skip`.
2. **Execute agent** (docs-updater on the automation path) maps facts into `findings[]` with `file`, `reason`, and `source_commit`, then classifies and patches per skill checklists.
3. Field semantics and `## Constraints` edit gate: [common-loop-triage-format.md](../common-loop-triage-format.md) and skill `references/category-input-schema.md` / `category-automation-envelope.md` (automation path only).

### Modes

| Mode           | Default | Behavior                                       |
| -------------- | ------- | ---------------------------------------------- |
| `integration`  | on      | Detect on watch branch → fix PR to same branch |
| `pull_request` | off     | not supported for this loop                    |

## Caller inputs

Keys are passed in `on-loop-docs-updater.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_checker_instructions`, `agent_maker_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Input / JSON key             | Description                                                                                                                                                                                                               | Dogfood value                                                             |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `agent_maker_max_turns`      | Max maker agent turns per loop attempt (one Agent→Verify cycle).                                                                                                                                                          | `100`                                                                     |
| `agent_maker_model`          | Maker model ID. Cursor: `agent --list-models`.                                                                                                                                                                            | `claude-sonnet-5`                                                         |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                              | `medium`                                                                  |
| `agent_loop_max_attempts`    | Max Agent→Verify retry cycles before finalize records failure.                                                                                                                                                            | `3`                                                                       |
| `agent_checker_instructions` | Checker APPROVE/REJECT rubric. Doc-only edits; factual consistency; no sensitive data.                                                                                                                                    | Inline in caller workflow                                                 |
| `agent_checker_max_turns`    | Max checker agent turns per verification.                                                                                                                                                                                 | `100`                                                                     |
| `agent_checker_model`        | Checker model ID. Cursor: `agent --list-models`.                                                                                                                                                                          | `claude-opus-5`                                                           |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                            | `medium`                                                                  |
| `agent_edit_allowlist`       | Comma-separated globs the maker may modify. Must align with docs-updater scope.                                                                                                                                           | `docs/**/*.md,README.md,mkdocs.yml`                                       |
| `detect_branch_match`        | Comma-separated integration branch patterns to watch for doc drift.                                                                                                                                                       | `main`                                                                    |
| `state_branch`               | Branch for `.loop/*` persistence, and state migration (it no longer doubles as a watch fallback).                                                                                                                         | `main`                                                                    |
| `budget_max_runs_per_day`    | Daily run cap keyed by `loop_name`. Caller input; `.loop/loop-budget.json` overrides when present.                                                                                                                        | `1`                                                                       |
| `budget_max_tokens_per_day`  | Daily aggregated token cap across loops.                                                                                                                                                                                  | `1000000`                                                                 |
| `detect_script`              | Domain detect script path (shared with docs-updater hook path).                                                                                                                                                           | `.agents/skills/docs-updater/scripts/detect_changes.sh`                   |
| `agent_engine`               | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                                                                                                                                     | `claude`                                                                  |
| `delivery`                   | Platform delivery after APPROVE (`pr_create` for dogfood).                                                                                                                                                                | `pr_create`                                                               |
| `agent_checker_path_pattern` | Extended regex to infer file paths from checker text.                                                                                                                                                                     | See caller workflow                                                       |
| `level`                      | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR.                                                                                                                                                                    | `L2`                                                                      |
| `loop_name`                  | Loop identifier; state file `.loop/state-docs-updater.json`.                                                                                                                                                              | `docs-updater`                                                            |
| `detect_max_targets`         | Max targets per cron tick after priority filters.                                                                                                                                                                         | `3`                                                                       |
| `agent_edit_allowed`         | Agent worktree edit gate (`true` for dogfood).                                                                                                                                                                            | `true`                                                                    |
| `agent_unchanged_verdict`    | `APPROVE` or `REJECT` when maker produces no file diff.                                                                                                                                                                   | `REJECT`                                                                  |
| `pr_body`                    | Optional static prefix (dogfood: `""`). `loop-finalize` composes agent Overview/Summary + mechanical sections. See [Loop PR Body Readable Design](../../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md). | `""`                                                                      |
| `pr_title`                   | PR title when `delivery` is `pr_create`.                                                                                                                                                                                  | `chore(docs-updater): automated documentation update (loop-docs-updater)` |
| `agent_maker_instructions`   | Domain instructions: run docs-updater automation path; address documented findings.                                                                                                                                       | Inline in caller workflow                                                 |
| `detect_pr_enabled`          | Enumerate open PR heads. docs-updater uses integration branches only.                                                                                                                                                     | `false`                                                                   |
| `agent_maker_skill_name`     | Skill package to invoke.                                                                                                                                                                                                  | `docs-updater`                                                            |
| `agent_tool_allowlist`       | Tool permission rules for the maker                                                                                                                                                                                       | `git remote get-url`                                                      |

### Domain detect environment (`detect_env_json`)

| JSON key                   | Description                                          | Dogfood value            |
| -------------------------- | ---------------------------------------------------- | ------------------------ |
| `DOCS_UPDATER_DOC_GLOBS`   | Comma-separated doc file globs for git-diff analysis | `docs/**/*.md,README.md` |
| `DOCS_UPDATER_EXTRA_FILES` | Additional non-glob paths                            | `mkdocs.yml`             |

When `DOCS_UPDATER_DOC_GLOBS` is unset, detect falls back to a repository-wide `*.md` find with standard `repo_paths` pruning (excludes `.agents/`, generated trees, etc.). Production callers should set globs explicitly; the fallback is mainly for local runs and tests.

#### Hook / manual (appendix)

Not a loop caller; configure via environment when invoking `detect_changes.sh` outside defaults.

| Env var                    | Description                 | Default      |
| -------------------------- | --------------------------- | ------------ |
| `DOCS_UPDATER_DOCS_ROOT`   | Documentation tree root     | `docs`       |
| `DOCS_UPDATER_SITE_CONFIG` | Site navigation config path | `mkdocs.yml` |

| `agent_edit_target` | Agent artifact when `agent_edit_allowed` is true (`fix` for dogfood). | `fix` |

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

**Skill** (`docs-updater` automation path) builds `findings[]` with semantic `reason` from these facts.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `delivery` = `pr_create`

**Do not** use ci-sweeper workflow-run / `gh run list` detect.

### Stable filters (detect only)

- Circuit breaker on `targets[key].consecutive_failures`
- Budget (platform)

No infra/env classification — not applicable.

### State fields (per target key)

| Field                  | Role                                                                |
| ---------------------- | ------------------------------------------------------------------- |
| `last_sha`             | Scan cursor; advances when fix PR merges (`on-loop-state-promote`)  |
| `pending`              | Written at finalize on `pr_create`; promoted to `last_sha` on merge |
| `outcome`              | `pr_created`, `rejected`, `unchanged`, …                            |
| `consecutive_failures` | Circuit breaker                                                     |

No `workflow_run_id` / ci ledger.

## Execute

- Worktree from `target.from` on integration branch
- Checker diff baseline: `to.branch`
- `verifier_context`: detect fact summary (changed files, affected docs). Platform always wires; may be brief

## Finalize

PR body is composed by `loop-finalize` from agent `## Overview` / `## Summary` (skill-owned) plus mechanical sections. Dogfood sets `pr_body: ""`. See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

Always `delivery: pr_create` to `to.branch` at L2. Other deliveries (`pr_push`) are not used by this loop.

No `finalize_script`.

**Merge-gated cursor:** Same platform rule as all L2 `pr_create` loops — `pending` at finalize, `last_sha` on fix PR merge via `on-loop-state-promote.yaml`. See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy).

## State delivery

See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) for platform rules.

**Target (dogfood):** merge-gated `pending` + `on-loop-state-promote` — same as changelog.

Persistence: `state-docs-updater.json` on `state_branch` via [finalize inside ci-loop-agent](../loop-caller-workflows-design.md#finalize-inside-ci-loop-agent).

## Implementation Checklist

Shared platform: [Multi-Branch — Shared platform checklist](../multi-branch-loops-design.md#shared-platform-checklist-all-loops).

### Loop-specific

- [x] `docs-updater/scripts/detect_changes.sh` (facts output)
- [x] `on-loop-docs-updater.yaml` dogfood caller via `ci-loop-caller`
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.affected_docs` branch)
- [x] `docs-updater` skill automation path + references
- [x] Bats suite for detect script (TEST-00)

## Cross-Loop Note

If `ci-sweeper` and docs-updater both target `integration:main`, [workflow concurrency](../multi-branch-loops-design.md#cross-loop-coordination-workflow-concurrency) and separate concurrency groups apply. CI failure on `main` is ci-sweeper priority; doc-only drift is docs-updater.

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
