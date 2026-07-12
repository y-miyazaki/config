# Changelog Loop Workflow Design

Workflow and domain design for the `loop-changelog` (`changelog`) loop.

| Layer | Document |
| Platform | [Multi-Branch Loops Design](../multi-branch-loops-design.md) |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants | [Loop Engineering Design](../loop-engineering-design.md) |

**Artifacts:** `on-loop-changelog.yaml` · skill `loop-changelog` · `scripts/detect_changelog_commits.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Maintain [Keep a Changelog](https://keepachangelog.com/) `CHANGELOG.md` on integration branches: **released version sections are the immutable baseline**; the loop appends only to `## [Unreleased]` from changelog-worthy commits since the last processed SHA, then opens a review PR.

### Supported use cases

- Preserve existing `## [x.y.z] - date` sections and formatting; edit only `## [Unreleased]`
- Create a Keep a Changelog template when `CHANGELOG.md` is missing, then populate `## [Unreleased]`
- Ingest [Conventional Commits](https://www.conventionalcommits.org/) and other explicit prefixed subjects (for example `renovate(scope):`, `chore(deps):`)
- Add commit links when `repository_url` is resolved (GitHub Actions `GITHUB_*` or git remote; optional `CHANGELOG_REPOSITORY_URL` override)
- Open an L2 review PR to the watch integration branch (`finalize_integration: open_pr`)

### Out of scope

- **Release cut:** moving `## [Unreleased]` into a versioned section, bumping semver headers, or creating git tags (manual or separate release workflow)
- PR head mode (`pull_requests` default off) — changelog updates target integration branches only
- Commits without a clear `prefix: description` or `prefix(scope): description` shape
- Non-changelog files; loop state and detect script management

Skill execution boundaries: `loop-changelog` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

### Modes

| Mode | Default | Behavior |
| `integration` | on | Detect on watch branch → fix PR to same branch |
| `pull_request`| off | not supported for this loop |

## Caller inputs

Keys are passed in `on-loop-changelog.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_verifier_criteria`, `pr_body`, `prompt_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Legacy env name mapping: [Loop Caller `env` Reference](loop-caller-env-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Input / JSON key                                     | Description                                                                                                     | Dogfood value                                                       |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `agent_implementer_max_turns`                        | Max implementer agent turns per loop attempt (one Agent→Verify cycle).                                          | `5`                                                                 |
| `agent_implementer_model`                            | Implementer model ID. Cursor: `agent --list-models`.                                                            | `grok-4.5-medium`                                                   |
| `agent_loop_max_attempts`                            | Max Agent→Verify retry cycles before finalize records failure.                                                  | `3`                                                                 |
| `agent_verifier_criteria`                            | Verifier APPROVE/REJECT rubric (markdown). Checks Keep a Changelog shape, commit mapping, and no version bumps. | Inline in caller workflow                                           |
| `agent_verifier_max_turns`                           | Max verifier agent turns per verification.                                                                      | `3`                                                                 |
| `agent_verifier_model`                               | Verifier model ID. Cursor: `agent --list-models`.                                                               | `composer-2.5`                                                      |
| `allowlist`                                          | Comma-separated globs the implementer may modify. Enforced in `loop-execute`.                                   | `CHANGELOG.md`                                                      |
| `branch_match`                                       | Comma-separated branch patterns to watch for changelog drift.                                                   | `main`                                                              |
| `branch_state`                                       | Branch for `.loop/*` persistence, state migration, and watch fallback.                                          | `main`                                                              |
| `budget_max_runs_per_day`                            | Daily run cap keyed by `loop_name`. Exceeded → `skip_reason=budget`.                                            | `1`                                                                 |
| `budget_max_tokens_per_day`                          | Daily aggregated token cap across loops.                                                                        | `500000`                                                            |
| `detect_domain_env_json` → `CHANGELOG_FILE`          | Target changelog path. Forwarded to `detect_changelog_commits.sh`.                                              | `CHANGELOG.md`                                                      |
| `detect_domain_env_json` → `CHANGELOG_MERGE_COMMITS` | `true` includes merge commits; `false` passes `--no-merges` to detect script.                                   | `false`                                                             |
| `detect_script`                                      | Domain detect script path. Invoked once per scan context by `loop-detect`.                                      | `.agents/skills/loop-changelog/scripts/detect_changelog_commits.sh` |
| `engine`                                             | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                           | `cursor`                                                            |
| `finalize_integration`                               | Finalize strategy for integration targets: `open_pr` or `push` (L3).                                            | `open_pr`                                                           |
| `infer_files_pattern`                                | Extended regex to infer file paths from verifier text for allowlist checks.                                     | `CHANGELOG\.md`                                                     |
| `level`                                              | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR; L3 may auto-merge when `finalize=open_pr`.               | `L2`                                                                |
| `loop_name`                                          | Loop identifier; state file `.loop/state-changelog.json`. Align workflow name `on-loop-<loop_name>.yaml`.       | `changelog`                                                         |
| `max_targets_per_schedule`                           | Max targets per cron tick after priority/`acting_on` filters.                                                   | `3`                                                                 |
| `no_changes_verdict`                                 | `APPROVE` or `REJECT` when implementer produces no file diff.                                                   | `REJECT`                                                            |
| `pr_body`                                            | Static markdown prefix for finalize PR body (attribution, review notice).                                       | Inline in caller workflow                                           |
| `pr_title`                                           | PR title when finalize strategy is `open_pr`.                                                                   | `chore(changelog): update CHANGELOG.md (loop-changelog)`            |
| `prompt_instructions`                                | Domain instructions appended to implementer prompt by `loop-prompt-generate`.                                   | Inline in caller workflow                                           |
| `pull_requests`                                      | Enumerate open PR heads. Changelog uses integration branches only.                                              | `false`                                                             |
| `skill_name`                                         | Skill package to invoke. Must match `.agents/skills/loop-changelog/`.                                           | `loop-changelog`                                                    |

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_changelog_commits.sh` with `targets["integration:<branch>"].last_sha`.

Detect script outputs **facts** (not formatted changelog prose):

| Field | Role |
| `changelog_file` | Target path (default `CHANGELOG.md`) |
| `changelog_exists` | Whether the changelog file already exists on the scanned branch |
| `commit_range` | Active git range label |
| `commits` | Changelog-worthy commits (`sha`, `type`, `subject`, …) |
| `compare_url` | Optional GitHub compare URL for `commit_range` (empty when unknown) |
| `repository` | `owner/repo` when resolved |
| `repository_url` | Web base for commit links (`GITHUB_*`, git remote, or override) |
| `skip` | `true` when no unreleased changelog-worthy commits |

**Skill** (`loop-changelog`) creates the Keep a Changelog template when `changelog_exists` is false, then groups commits under `## [Unreleased]`.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `finalize` = `open_pr`

### Stable filters (detect only)

- Explicit `prefix: description` or `prefix(scope): description` subjects
- Conventional types (`feat:`, `fix:`, `chore:`, …) and tool prefixes (`renovate`, `dependabot`, …)
- Skip loop maintenance commits (`chore(changelog):`, subjects containing `(loop-changelog)`)
- Optional `--no-merges` when `CHANGELOG_MERGE_COMMITS` is `false`
- `--scope all` is bounded by `CHANGELOG_MAX_COMMITS` (default 100) for local debugging only
- Circuit breaker on `targets[key].consecutive_failures`
- Budget / `acting_on` (platform)

### State fields (per target key)

| Field | Role |
| `last_sha` | Scan cursor; advances on successful finalize |
| `outcome` | `pr-created`, `rejected`, `no-op`, … |
| `consecutive_failures` | Circuit breaker |

## Execute

- Worktree from `target.from` on integration branch
- Verifier diff baseline: `to.branch`
- `verifier_context`: detect commit summary (types, subjects, count)

## Finalize

Always `open_pr` to `to.branch` at L2. L3 `push` is not recommended for changelog automation.

No `domain_persistence_script`.

Persistence: `state-changelog.json` on `branch_state` via finalize.

## Implementation Checklist

- [x] `loop-changelog/scripts/detect_changelog_commits.sh` (facts output)
- [x] `branch_match` for additional branches
- [x] Per-branch `targets["integration:<branch>"]`
- [x] `target_matrix` through detect → matrix execute/finalize
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.commits` branch)

## Cross-Loop Note

Changelog runs are doc-metadata only (`CHANGELOG.md`). Coordinate with `loop-docs-triage` via [acting_on](../multi-branch-loops-design.md#cross-loop-coordination-acting_on) when both target `integration:main`.

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../reference/specification.md)
