@AGENTS.md

# Project Instructions

## Repository Rules

### Project Overview

Shared configuration distribution source — no application code. Deliverables: APM packages, reusable GitHub Actions workflows, Renovate policy presets.

### Edit Targets

Single reference when a change may touch package sources, `scripts/`, docs, or generated install output — including work that spans multiple directories.

| Edit here (source of truth)                                                                                          | Do not edit                                                                         | Post-change                                                                                                                 |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `.apm/packages/<pkg>/` (instructions, skills, hooks, MCP config)                                                     | `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/` | Sync mirrored artifacts per rows below → `apm install --update` → `apm audit --ci`                                          |
| `scripts/lib/`                                                                                                       | `.apm/packages/*/.apm/skills/*/scripts/lib/`                                        | `bash scripts/self/apm/sync_apm_artifacts.sh skill-lib` → `apm install --update`                                            |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh`                  | Paired skill `scripts/` copy                                                        | `bash scripts/self/apm/sync_apm_artifacts.sh validate-mirror` (`--from-skill` when editing skill copy; `--domain` to limit) |
| `docs/explanation/loop-engineering/portable/common-loop-*.md`                                                        | Loop skill reference copies under `.apm/packages/`                                  | `bash scripts/self/apm/sync_apm_artifacts.sh loop-contract` → `apm install --update`                                        |
| `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`                                            | Generated `## Guidelines` in instructions (unless accepting overwrite on next sync) | `bash scripts/self/apm/sync_apm_artifacts.sh guidelines` → `apm install --update`                                           |
| Repo-only paths (for example `scripts/terraform/module_updater.sh`, `.github/actions/**/lib/`, `.github/workflows/`) | —                                                                                   | Update matching Bats under `test/bats/` in the same change                                                                  |

- **Canonical sync entry point:** `bash scripts/self/apm/sync_apm_artifacts.sh` — use `--check` for drift-only CI.
- Cross-cutting rules for `scripts/` apply even when not touching `.apm/` — nested `.apm/AGENTS.md` is not loaded for `scripts/` work alone.
- Shell style and Bats: stem `shell-script` and `bats` instructions (distributed under `.cursor/rules/` after `apm install`).
- `validate.sh` path-layout differences (skill vs repo): [.apm/AGENTS.md § Validation Scripts Mirror](.apm/AGENTS.md#validation-scripts-mirror-scripts--skill).
- Package authoring (distributable rules, maintainer routing): [.apm/AGENTS.md](.apm/AGENTS.md).

### Workflow Conventions

- Reusable workflows use `workflow_call` trigger.
- File names: `ci-*` (CI), `cd-*` (CD), `on-*` (event-triggered callers).
- Keys in `inputs`, `env`, `permissions`, `with` MUST be alphabetically ordered.

### Manual Validation

Run on demand when troubleshooting CI or when explicitly requested:

- Mirror drift: `bash scripts/self/apm/sync_apm_artifacts.sh --check`
- APM integrity: `apm install --update`, `apm audit --ci`

### Temporary Artifacts

Write to `tmp/`.

### Documentation Editing

When structure, modules, or features change, update related `README.md` and `docs/` accordingly.

## Token Optimization

### MCP Policies

- lean-ctx, fetch should be used for all context fetching for optimization
