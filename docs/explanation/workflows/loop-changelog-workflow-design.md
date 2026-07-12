# Changelog Loop Workflow Design

Workflow and domain design for the `loop-changelog` (`changelog`) loop.

| Layer | Document |
| Platform | [Multi-Branch Loops Design](../multi-branch-loops-design.md) |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants | [Loop Engineering Design](../loop-engineering-design.md) |

**Artifacts:** `on-loop-changelog.yaml` · skill `loop-changelog` · `scripts/detect_changelog_commits.sh`

Shared caller keys (`AGENT_*`, `DEFAULT_*`, `LOOP_*`, `SKILL_NAME`): [Loop Caller `env` Reference](loop-caller-env-reference.md).

## Purpose

Maintain [Keep a Changelog](https://keepachangelog.com/) `CHANGELOG.md` on integration branches: **released version sections are the immutable baseline**; the loop appends only to `## [Unreleased]` from changelog-worthy commits since the last processed SHA, then opens a review PR.

### Supported use cases

- Preserve existing `## [x.y.z] - date` sections and formatting; edit only `## [Unreleased]`
- Create a Keep a Changelog template when `CHANGELOG.md` is missing, then populate `## [Unreleased]`
- Ingest [Conventional Commits](https://www.conventionalcommits.org/) and other explicit prefixed subjects (for example `renovate(scope):`, `chore(deps):`)
- Add commit links when `repository_url` is resolved (GitHub Actions `GITHUB_*` or git remote; optional `CHANGELOG_REPOSITORY_URL` override)
- Open an L2 review PR to the watch integration branch (`LOOP_FINALIZE_INTEGRATION: open_pr`)

### Out of scope

- **Release cut:** moving `## [Unreleased]` into a versioned section, bumping semver headers, or creating git tags (manual or separate release workflow)
- PR head mode (`LOOP_PULL_REQUESTS` default off) — changelog updates target integration branches only
- Commits without a clear `prefix: description` or `prefix(scope): description` shape
- Non-changelog files; loop state and detect script management

Skill execution boundaries: `loop-changelog` SKILL.md (`USE FOR` / `DO NOT USE FOR`).

### Modes

| Mode | Default | Behavior |
| `integration` | on | Detect on watch branch → fix PR to same branch |
| `pull_request`| off | not supported for this loop |

## Environment variables

All keys in workflow `env:` (alphabetically ordered). Multiline values (`AGENT_VERIFIER_CRITERIA`, `LOOP_PR_BODY`, `LOOP_PROMPT_INSTRUCTIONS`) are defined inline in `on-loop-changelog.yaml`.

Shared semantics for keys used across loops: [Loop Caller `env` Reference](loop-caller-env-reference.md). Platform branch/finalize caps: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Variable                         | Description                                                                                                     | Dogfood value                                                       |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `AGENT_IMPLEMENTER_MAX_TURNS`    | Max implementer agent turns per loop attempt (one Agent→Verify cycle).                                          | `"5"`                                                               |
| `AGENT_IMPLEMENTER_MODEL`        | Implementer model ID. Cursor: `agent --list-models`.                                                            | `grok-4.5-medium`                                                   |
| `AGENT_LOOP_MAX_ATTEMPTS`        | Max Agent→Verify retry cycles before finalize records failure.                                                  | `"3"`                                                               |
| `AGENT_VERIFIER_CRITERIA`        | Verifier APPROVE/REJECT rubric (markdown). Checks Keep a Changelog shape, commit mapping, and no version bumps. | Inline in workflow YAML                                             |
| `AGENT_VERIFIER_MAX_TURNS`       | Max verifier agent turns per verification.                                                                      | `"3"`                                                               |
| `AGENT_VERIFIER_MODEL`           | Verifier model ID. Cursor: `agent --list-models`.                                                               | `composer-2.5`                                                      |
| `CHANGELOG_FILE`                 | Target changelog path. Forwarded to `detect_changelog_commits.sh`. YAML anchor reused by `LOOP_ALLOWLIST`.      | `CHANGELOG.md`                                                      |
| `CHANGELOG_MERGE_COMMITS`        | `"true"` includes merge commits; `"false"` passes `--no-merges` to detect script.                               | `"false"`                                                           |
| `DEFAULT_BASE_BRANCH`            | Default branch for state migration when legacy flat `last_sha` is copied into `targets`.                        | `main`                                                              |
| `DEFAULT_ENGINE`                 | AI engine (`claude`, `copilot`, `codex`, `cursor`). Maps `AGENT_TOKEN` to engine env.                           | `cursor`                                                            |
| `DEFAULT_LEVEL`                  | Autonomy level (`L1`, `L2`, `L3`). L2 opens review PR; L3 may auto-merge when `finalize=open_pr`.               | `L2`                                                                |
| `LOOP_ALLOWLIST`                 | Comma-separated globs the implementer may modify. Enforced in `loop-execute`.                                   | `CHANGELOG.md`                                                      |
| `LOOP_BUDGET_MAX_RUNS_PER_DAY`   | Daily run cap keyed by `LOOP_NAME`. Exceeded → `skip_reason=budget`.                                            | `"1"`                                                               |
| `LOOP_BUDGET_MAX_TOKENS_PER_DAY` | Daily aggregated token cap across loops.                                                                        | `"500000"`                                                          |
| `LOOP_DETECT_SCRIPT`             | Domain detect script path. Invoked once per scan context by `loop-detect`.                                      | `.agents/skills/loop-changelog/scripts/detect_changelog_commits.sh` |
| `LOOP_FINALIZE_INTEGRATION`      | Finalize strategy for integration targets: `open_pr` or `push` (L3).                                            | `open_pr`                                                           |
| `LOOP_INFER_FILES_PATTERN`       | Extended regex to infer file paths from verifier text for allowlist checks.                                     | `CHANGELOG\.md`                                                     |
| `LOOP_INTEGRATION_BRANCHES`      | Comma-separated branch patterns to watch for changelog drift.                                                   | `main`                                                              |
| `LOOP_MAX_TARGETS_PER_SCHEDULE`  | Max targets per cron tick after priority/`acting_on` filters.                                                   | `"3"`                                                               |
| `LOOP_NAME`                      | Loop identifier; state file `.loop/state-changelog.json`. Align workflow name `on-loop-<LOOP_NAME>.yaml`.       | `changelog`                                                         |
| `LOOP_NO_CHANGES_VERDICT`        | `APPROVE` or `REJECT` when implementer produces no file diff.                                                   | `REJECT`                                                            |
| `LOOP_PR_BODY`                   | Static markdown prefix for finalize PR body (attribution, review notice).                                       | Inline in workflow YAML                                             |
| `LOOP_PR_TITLE`                  | PR title when finalize strategy is `open_pr`.                                                                   | `chore(changelog): update CHANGELOG.md (loop-changelog)`            |
| `LOOP_PROMPT_INSTRUCTIONS`       | Domain instructions appended to implementer prompt by `loop-prompt-generate`.                                   | Inline in workflow YAML                                             |
| `LOOP_PULL_REQUESTS`             | `"true"` enumerates open PR heads; changelog uses integration branches only.                                    | `"false"`                                                           |
| `LOOP_STATE_PUSH_BRANCH`         | Branch for `.loop/*` persistence commits (state, budget, run-log).                                              | `main`                                                              |
| `SKILL_NAME`                     | Skill package to invoke. Must match `.agents/skills/loop-changelog/`.                                           | `loop-changelog`                                                    |

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

Persistence: `state-changelog.json` on `LOOP_STATE_PUSH_BRANCH` via finalize.

## Implementation Checklist

- [x] `loop-changelog/scripts/detect_changelog_commits.sh` (facts output)
- [x] `LOOP_INTEGRATION_BRANCHES` for additional branches
- [x] Per-branch `targets["integration:<branch>"]`
- [x] `target_matrix` through detect → matrix execute/finalize
- [x] `verifier_context` on execute path (`build_verifier_context_from_result` `.commits` branch)

## Cross-Loop Note

Changelog runs are doc-metadata only (`CHANGELOG.md`). Coordinate with `loop-docs-triage` via [acting_on](../multi-branch-loops-design.md#cross-loop-coordination-acting_on) when both target `integration:main`.

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../reference/specification.md)
