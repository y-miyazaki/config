# Detect Path Filter Design

Implementation design note for loop detect scripts and shared `scripts/lib/repo_paths.sh`.

> **Publication scope:** This file lives under `docs/superpowers/` and is **not** published on the MkDocs site. The runtime contract is defined in `scripts/lib/repo_paths.sh` (header + function docs) and detect-script environment variables.

## Problem

Detect scripts mixed three concerns:

1. **Enumeration** — git diff, `git ls-files`, `git grep`, `git log`, or `find`
2. **Filtering** — agents/generated dirs, hidden segments, `.gitignore`, domain extras
3. **Domain logic** — when to expand work sets (docs triage) vs full-repo scan (tech-debt)

Filtering was duplicated as `find -prune` blocks and per-sensor `path_is_pruned` checks, without consistent `.gitignore` handling.

## Model

Enumeration strategy differs by detect type:

| Type         | Work-set source                   | Example                 |
| ------------ | --------------------------------- | ----------------------- |
| Delta-driven | `git diff` (+ optional expansion) | `loop-docs-triage`      |
| Full-scan    | `**/*` patterns / tracked tree    | `loop-report-tech-debt` |
| Event-driven | External events                   | `loop-ci-sweeper`       |

**Filtering is identical** across types: every enumerated path passes through `repo_path_should_skip()`.

Full-scan is delta-driven with a fixed `**/*` work set — only enumeration differs.

## Shared library (`scripts/lib/repo_paths.sh`)

Synced to skill `scripts/lib/` via `scripts/self/ai/sync_skill_lib.sh`.

### Predicate layer

| Function                               | Role                                                                                |
| -------------------------------------- | ----------------------------------------------------------------------------------- |
| `repo_path_is_generated_or_agent`      | `.git`, `apm_modules`, `node_modules`, build dirs, agent roots                      |
| `repo_path_has_excluded_dot_directory` | Dot-prefixed directory segments except `.github` and `.apm`                         |
| `repo_path_is_gitignored`              | `git check-ignore` (skip when `REPO_PATHS_INCLUDE_GITIGNORED=true`)                 |
| `repo_path_matches_extra_prune`        | Caller/detect-specific roots                                                        |
| `repo_path_should_skip_base`           | Compose all of the above                                                            |
| `repo_path_should_skip`                | Merge env/call-time extras via `repo_list_extra_prune_roots`, then delegate to base |
| `repo_list_extra_prune_roots`          | Emit merged `REPO_PATHS_EXTRA_PRUNES` and call-time roots on stdout                 |

### Enumeration helpers

| Function                      | Role                                                                           |
| ----------------------------- | ------------------------------------------------------------------------------ |
| `repo_filter_paths`           | stdin paths → filtered stdout (git diff, git log, find output)                 |
| `repo_emit_tracked_paths`     | `git ls-files` → filtered stdout (optional ERE pattern)                        |
| `repo_append_find_prune_args` | Append standard `find` prune predicate to an argument array                    |
| `repo_apply_git_rename`       | Classify git renames for delta detect scripts (renamed + cross-zone fallbacks) |
| `repo_array_append_unique`    | Append a path to an array when absent                                          |

`repo_append_find_prune_args` prunes known generated/agent roots and caller extras only. It does **not** implement the full dot-directory rule. **Always** pipe find output through `repo_filter_paths` — the filter is authoritative; prune is a performance hint.

### Environment flags

| Variable                        | Default         | Effect                                                                  |
| ------------------------------- | --------------- | ----------------------------------------------------------------------- |
| `REPO_PATHS_EXTRA_PRUNES`       | unset           | Comma-separated repository-relative roots excluded by skip + find prune |
| `REPO_PATHS_INCLUDE_AGENTS`     | unset (`false`) | When `true`, do not exclude agent directories                           |
| `REPO_PATHS_INCLUDE_GITIGNORED` | unset (`false`) | When `true`, do not exclude gitignored paths                            |

Callers that need domain-specific exclusions set `REPO_PATHS_EXTRA_PRUNES` (or pass roots to `repo_path_should_skip` / `repo_append_find_prune_args`). Do not hardcode repository paths inside `repo_paths.sh`.

## Detect script contract

1. Source `lib/all.sh` (includes `repo_paths.sh`).
2. Set `REPO_PATHS_EXTRA_PRUNES` when domain-specific roots must be excluded (before enumeration).
3. Apply filtering uniformly:
   - **Git streams** → pipe through `repo_filter_paths` or call `repo_path_should_skip` inline (`git grep` lines).
   - **Tracked enumeration** → `repo_emit_tracked_paths '<ere>'`.
   - **Find** → `repo_append_find_prune_args` + `repo_filter_paths` on output.
   - **Git renames** → `repo_apply_git_rename` (both scannable → `renamed_files` only; cross-zone → `renamed_files` plus scannable side in `deleted_files` or `changed_files`).

## Consumers

| Script                               | `REPO_PATHS_EXTRA_PRUNES`                   | Notes                    |
| ------------------------------------ | ------------------------------------------- | ------------------------ |
| `detect_report_tech_debt.sh`         | Parent of `REPORT_TECH_DEBT_DIR` when unset | Full-scan sensors        |
| `loop-docs-triage/detect_changes.sh` | none (lib default)                          | Delta + doc expansion    |
| `docs-updater/detect_changes.sh`     | none                                        | Hook-triggered doc drift |

## Out of scope

- Unifying enumeration strategy across detect types
- Changing detect JSON output contracts
- `loop-ci-sweeper` / `loop-changelog` (no repository file walk)

## Spec self-review

- Filter unified; enumeration remains type-specific.
- `.gitignore` and agents exclusion applied consistently.
- Domain extras are caller-controlled via `REPO_PATHS_EXTRA_PRUNES`; skip and find prune share the same resolver.
