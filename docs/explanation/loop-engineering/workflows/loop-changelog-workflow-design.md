# Changelog Loop Workflow Design

Workflow and domain design for the `loop-changelog` (`changelog`) loop.

| Layer | Document |
| Platform | [Multi-Branch Loops Design](../multi-branch-loops-design.md) |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants | [Loop Engineering Design](../loop-engineering-design.md) |

**Artifacts:** `on-loop-changelog.yaml` · skill `loop-changelog` · `scripts/detect_changelog_commits.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## Purpose

Maintain [Keep a Changelog](https://keepachangelog.com/) `CHANGELOG.md` on integration branches: preserve existing release sections, append to `## [Unreleased]`, promote undocumented releases detected from git tags and pin/finalize commits, then open **one domain-only** L2 review PR (`CHANGELOG.md` only). Loop state advances on merge via `on-loop-state-promote`.

### Supported use cases

- Preserve existing `## [x.y.z] - date` sections and formatting
- Create a Keep a Changelog template when `CHANGELOG.md` is missing, then populate `## [Unreleased]`
- Ingest [Conventional Commits](https://www.conventionalcommits.org/) and other explicit prefixed subjects (for example `renovate(scope):`, `chore(deps):`)
- Promote detect `releases[]` into `## [x.y.z] - date` sections (from git tags and pin/finalize subjects)
- Add commit links when `repository_url` is resolved (GitHub Actions `GITHUB_*` or git remote; optional `CHANGELOG_REPOSITORY_URL` override)
- Open an L2 review PR to the watch integration branch; L3 enables GitHub auto-merge on that fix PR. Wire/default finalize is `open_pr` (dogfood sets `finalize_integration: open_pr`)

### Out of scope

- Creating git tags (tags are inputs to detect; the loop documents them in `CHANGELOG.md` only)
- PR head mode (`pr_enabled` default off) — changelog updates target integration branches only
- Commits without a clear `prefix: description` or `prefix(scope): description` shape
- Implementer edits to loop state (finalize bundles state after verification)

Skill execution boundaries: `loop-changelog` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

### User-facing invariants

| Invariant | Rationale |
| One review PR (domain only) | Reviewers judge `CHANGELOG.md` only; loop state advances on merge via `on-loop-state-promote` |
| No orphan state PRs | `acting_on` persistence during execute does not open state PRs; merge-gated `pending` lands on `branch_state` |
| Release sections from facts | Skill may add `## [version] - date` only for versions in detect `releases[]` — never invented versions |

### Modes

| Mode | Default | Behavior |
| `integration` | on | Detect on watch branch → fix PR to same branch |
| `pull_request`| off | not supported for this loop |

## Caller inputs

Keys are passed in `on-loop-changelog.yaml` via `with:` on `ci-loop-caller.yaml` (alphabetically ordered). Multiline values (`agent_verifier_criteria`, `pr_body`, `prompt_instructions`) are defined inline in the caller workflow.

Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Legacy env name mapping: [Loop Caller `env` Reference](loop-caller-env-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Input / JSON key                                     | Description                                                                                               | Dogfood value                                                       |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `agent_implementer_max_turns`                        | Max implementer agent turns per loop attempt (one Agent→Verify cycle).                                    | `5`                                                                 |
| `agent_implementer_model`                            | Implementer model ID. Cursor: `agent --list-models`.                                                      | `grok-4.5-medium`                                                   |
| `agent_loop_max_attempts`                            | Max Agent→Verify retry cycles before finalize records failure.                                            | `3`                                                                 |
| `agent_verifier_criteria`                            | Verifier rubric: Unreleased mapping, detect `releases[]` promotion, no hallucinated versions.             | Inline in caller workflow                                           |
| `agent_verifier_max_turns`                           | Max verifier agent turns per verification.                                                                | `3`                                                                 |
| `agent_verifier_model`                               | Verifier model ID. Cursor: `agent --list-models`.                                                         | `composer-2.5`                                                      |
| `allowlist`                                          | Comma-separated globs the implementer may modify. Enforced in `loop-execute`.                             | `CHANGELOG.md`                                                      |
| `branch_match`                                       | Comma-separated branch patterns to watch for changelog drift.                                             | `main`                                                              |
| `branch_state`                                       | Branch for run-log/budget persistence and state **read** baseline.                                        | `main`                                                              |
| `budget_max_runs_per_day`                            | Daily run cap keyed by `loop_name`. Exceeded → `skip_reason=budget`.                                      | `1`                                                                 |
| `budget_max_tokens_per_day`                          | Daily aggregated token cap across loops.                                                                  | `500000`                                                            |
| `detect_domain_env_json` → `CHANGELOG_FILE`          | Target changelog path. Forwarded to `detect_changelog_commits.sh`.                                        | `CHANGELOG.md`                                                      |
| `detect_domain_env_json` → `CHANGELOG_MERGE_COMMITS` | `true` includes merge commits; `false` passes `--no-merges` to detect script.                             | `false`                                                             |
| `detect_script`                                      | Domain detect script path. Invoked once per scan context by `loop-detect`.                                | `.agents/skills/loop-changelog/scripts/detect_changelog_commits.sh` |
| `engine`                                             | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                     | `cursor`                                                            |
| `infer_files_pattern`                                | Extended regex to infer file paths from verifier text for allowlist checks.                               | `CHANGELOG\.md`                                                     |
| `level`                                              | Autonomy: `L2` human merge on bot fix PR; `L3` GitHub auto-merge on bot fix PR.                           | `L2`                                                                |
| `loop_name`                                          | Loop identifier; state file `.loop/state-changelog.json`. Align workflow name `on-loop-<loop_name>.yaml`. | `changelog`                                                         |
| `max_targets_per_schedule`                           | Max targets per cron tick after priority/`acting_on` filters.                                             | `3`                                                                 |
| `no_changes_verdict`                                 | `APPROVE` or `REJECT` when implementer produces no file diff.                                             | `REJECT`                                                            |
| `pr_body`                                            | Static markdown prefix for finalize PR body (notes bundled state).                                        | Inline in caller workflow                                           |
| `pr_title`                                           | PR title when finalize strategy is `open_pr`.                                                             | `chore(changelog): update CHANGELOG.md (loop-changelog)`            |
| `prompt_instructions`                                | Domain instructions appended to implementer prompt by `loop-prompt-generate`.                             | Inline in caller workflow                                           |
| `pull_requests`                                      | Wire name for `pr_enabled`. Changelog uses integration branches only.                                     | `false`                                                             |
| `skill_name`                                         | Skill package to invoke. Must match `.agents/skills/loop-changelog/`.                                     | `loop-changelog`                                                    |

Platform handler: `on-loop-state-promote.yaml` (`pull_request` `closed`) promotes `pending` → `last_sha` on merge.

## Detect

### Integration mode only

Per watch branch, `loop-detect` checks out the branch and invokes `detect_changelog_commits.sh` with `targets["integration:<branch>"].last_sha`.

Detect script outputs **facts** (not formatted changelog prose):

| Field | Role |
| `changelog_file` | Target path (default `CHANGELOG.md`) |
| `changelog_exists` | Whether the changelog file already exists on the scanned branch |
| `commit_range` | Active git range label |
| `commits` | Changelog-worthy commits (`sha`, `type`, `subject`, …) |
| `releases` | Undocumented versions from tags and pin/finalize subjects (`version`, `tag`, `tag_sha`, `date`, `commit_shas`) |
| `compare_url` | Optional GitHub compare URL for `commit_range` (empty when unknown) |
| `repository` | `owner/repo` when resolved |
| `repository_url` | Web base for commit links (`GITHUB_*`, git remote, or override) |
| `skip` | `true` when no unreleased commits and no undocumented releases |

**Skill** (`loop-changelog`) creates the Keep a Changelog template when `changelog_exists` is false, groups commits under `## [Unreleased]`, and promotes `releases[]` into versioned sections.

`loop-detect` emits per-branch `target_json`:

- `from.ref` = HEAD on watch branch
- `to.branch` = watch branch
- `finalize` = `open_pr`

### Stable filters (detect only)

- Explicit `prefix: description` or `prefix(scope): description` subjects
- Conventional types (`feat:`, `fix:`, `chore:`, …) and tool prefixes (`renovate`, `dependabot`, …)
- Skip loop maintenance commits (`chore(changelog):`, subjects containing `(loop-changelog)`)
- Release detection: semver git tags (`v*.*.*`) and pin/finalize/align subjects in range not yet in `CHANGELOG.md`
- Optional `--no-merges` when `CHANGELOG_MERGE_COMMITS` is `false`
- `--scope all` is bounded by `CHANGELOG_MAX_COMMITS` (default 100) for local debugging only
- Circuit breaker on `targets[key].consecutive_failures`
- Budget / workflow `concurrency` (platform)

### State fields (per target key)

| Field | Role |
| `last_sha` | Scan cursor; advances when fix PR merges (`on-loop-state-promote`) |
| `pending` | Written at finalize (`pr-created`); holds `{ sha, pr, … }` until merge |
| `outcome` | `pr-created`, `rejected`, `no-op`, … |
| `consecutive_failures` | Circuit breaker |

## Execute

- Worktree from `target.from` on integration branch
- Verifier diff baseline: `to.branch`
- `verifier_context`: detect commit and release summary
- `Set Acting On` during execute (coordination only; no state PR)

## Finalize

Always `open_pr` to `to.branch` at L2.

1. Optional domain persistence (none for changelog)
2. Create PR (`CHANGELOG.md` only)
3. **Write state** to `branch_state` with `pending` (merge-gated; `last_sha` unchanged)
4. Append run log to `branch_state`

On `REJECT`, state writes failure metadata to `branch_state` without advancing `last_sha`.

On fix PR merge, `on-loop-state-promote` promotes `pending.sha` → `last_sha`.

No `domain_persistence_script`.

## Implementation Checklist

- [x] `loop-changelog/scripts/detect_changelog_commits.sh` (facts output + `releases[]`)
- [x] Merge-gated state via `on-loop-state-promote.yaml`
- [x] `branch_match` for additional branches
- [x] Per-branch `targets["integration:<branch>"]`
- [x] `target_matrix` through detect → matrix execute/finalize
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.commits` branch)
- [ ] Bump remote pins (`loop-detect`, `ci-loop-agent`, `loop-finalize`, `loop-state-write`) to release SHA containing merge-gated `pending` / `loop-state-promote`

## Cross-Loop Note

Changelog runs are doc-metadata only (`CHANGELOG.md`). Coordinate with `loop-docs-triage` via workflow `concurrency` when both target `integration:main`.

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)

