@AGENTS.md

# Project Instructions

## Repository Rules

### Project Overview

Shared configuration distribution source — no application code. Deliverables: APM packages, reusable GitHub Actions workflows, Renovate policy presets.

### Edit Targets

Single reference when a change may touch package sources, `scripts/`, docs, or generated install output — including work that spans multiple directories.

| Edit here (source of truth)                                                                                          | Do not edit                                                                         |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `.apm/packages/<pkg>/` (instructions, skills, hooks, MCP config)                                                     | `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/` |
| `scripts/lib/`                                                                                                       | `.apm/packages/*/.apm/skills/*/scripts/lib/`                                        |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh`                  | Paired skill `scripts/` copy                                                        |
| `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`                                            | Generated `## Guidelines` in instructions (unless accepting overwrite on next sync) |
| Loop skill PR body templates/envelopes (changelog, ci-sweeper, docs-updater, refactor, tech-debt)                    | `.agents/`, `.claude/`, … skill mirrors                                             |
| Repo-only paths (for example `scripts/terraform/module_updater.sh`, `.github/actions/**/lib/`, `.github/workflows/`) | —                                                                                   |

**Post-change:** `bash scripts/self/apm/sync_apm_artifacts.sh` for all mirrored rows above (sync, `apm install --update`, drift check, `apm audit --ci`; `--check` for validation only). Repo-only rows: update matching Bats under `test/bats/` in the same change. Skill-copy edits to `validate.sh`: `sync_validate_mirror.sh --from-skill`.

- Cross-cutting rules for `scripts/` apply even when not touching `.apm/` — nested `.apm/AGENTS.md` is not loaded for `scripts/` work alone.
- Shell style and Bats: stem `shell-script` and `bats` instructions (distributed under `.cursor/rules/` after `apm install`).
- `validate.sh` path-layout differences (skill vs repo): [.apm/AGENTS.md § Validation Scripts Mirror](.apm/AGENTS.md#validation-scripts-mirror-scripts--skill).
- Package authoring (distributable rules, maintainer routing): [.apm/AGENTS.md](.apm/AGENTS.md).

### Workflow Conventions

- Reusable workflows use `workflow_call` trigger.
- File names: `ci-*` (CI), `cd-*` (CD), `on-*` (event-triggered callers).
- Keys in `inputs`, `env`, `permissions`, `with` MUST be alphabetically ordered.

### Temporary Artifacts

Write to `tmp/`.

### Documentation Editing

When structure, modules, or features change, update related `README.md` and `docs/` accordingly.

## Token Optimization

### MCP Policies

- lean-ctx, fetch should be used for all context fetching for optimization
