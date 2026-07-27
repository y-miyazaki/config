@AGENTS.md

# Project Instructions

## Repository Rules

### Project Overview

Shared configuration distribution source — no application code. Deliverables: APM packages, reusable GitHub Actions workflows, Renovate policy presets.

### Edit Targets

Single reference when a change may touch package sources, `scripts/`, docs, or generated install output — including work that spans multiple directories.

### APM: project-specific vs distributable (MUST)

- **This repository only:** APM maintainer rules, Loop platform behavior, sync/edit workflows, and any assumption about this repo's layout or CI → [.apm/AGENTS.md](.apm/AGENTS.md) or this file (`CLAUDE.md`). Use `docs/` for extended design.
- **Distributable:** `.apm/packages/**` is installed into **other repositories**. Instructions, skills, `references/`, hooks, and MCP config there MUST use **generalized, portable** wording. Do not embed this repository's paths, Loop caller names, `may_edit` authoring conventions, or other consumer-specific rules in package sources — those belong in `.apm/AGENTS.md` or here.

| Edit here (source of truth)                                                                                          | Do not edit                                                                         |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `.apm/packages/<pkg>/` (instructions, skills, hooks, MCP config)                                                     | `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/` |
| `scripts/lib/`                                                                                                       | `.apm/packages/*/.apm/skills/*/scripts/lib/`                                        |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh`                  | Paired skill `scripts/` copy                                                        |
| `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`                                            | Generated `## Guidelines` in instructions (unless accepting overwrite on next sync) |
| Repo-only paths (for example `scripts/terraform/module_updater.sh`, `.github/actions/**/lib/`, `.github/workflows/`) | —                                                                                   |

**Post-change:** Agent `stop` hooks run `scripts/self/apm/sync_apm_artifacts.sh` for mirrored rows above (sync, `apm install --update`, drift check, `apm audit --ci`). Do not run sync manually unless hooks are unavailable or you need validation-only (`--check`). Repo-only rows: update matching Bats under `test/bats/` in the same change. Skill-copy edits to `validate.sh`: `sync_validate_mirror.sh --from-skill`.

- Cross-cutting rules for `scripts/` apply even when not touching `.apm/` — nested `.apm/AGENTS.md` is not loaded for `scripts/` work alone.
- Shell style and Bats: stem `shell-script` and `bats` instructions (distributed under `.cursor/rules/`).
- `validate.sh` path-layout differences (skill vs repo): [.apm/AGENTS.md § Validation Scripts Mirror](.apm/AGENTS.md#validation-scripts-mirror-scripts--skill).
- Package authoring (distributable rules, maintainer routing): [.apm/AGENTS.md](.apm/AGENTS.md).

### Workflow Conventions

- Reusable workflows use `workflow_call` trigger.
- File names: `ci-*` (CI), `cd-*` (CD), `on-*` (event-triggered callers).
- Workflow/action key ordering: companion github-actions-workflow rules (stem `github-actions-workflow`), ORD-01.

### Temporary Artifacts

Write to `tmp/`.

### Documentation Editing

When structure, modules, or features change, update related `README.md` and `docs/` accordingly.

## Token Optimization

### MCP Policies

- lean-ctx, fetch should be used for all context fetching for optimization
