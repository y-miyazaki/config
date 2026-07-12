# Changelog Loop Workflow Design

Workflow and domain design for the `loop-changelog` (`changelog`) loop.

| Layer | Document |
| Platform | [Multi-Branch Loops Design](../multi-branch-loops-design.md) |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants | [Loop Engineering Design](../loop-engineering-design.md) |

**Artifacts:** `on-loop-changelog.yaml` · skill `loop-changelog` · `scripts/detect_changelog_commits.sh`

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

## Recommended `env`

```yaml
env:
  CHANGELOG_FILE: CHANGELOG.md
  CHANGELOG_MERGE_COMMITS: "false"
  DEFAULT_LEVEL: L2
  LOOP_ALLOWLIST: CHANGELOG.md
  LOOP_DETECT_SCRIPT: .agents/skills/loop-changelog/scripts/detect_changelog_commits.sh
  LOOP_FINALIZE_INTEGRATION: open_pr
  LOOP_INTEGRATION_BRANCHES: main
  LOOP_NAME: changelog
  LOOP_PULL_REQUESTS: "false"
  LOOP_STATE_PUSH_BRANCH: main
  SKILL_NAME: loop-changelog
```

Full `LOOP_*` definitions: [canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

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
