@AGENTS.md

# Project Instructions

## Edit routing (MUST)

| Edit here (source of truth)                                                                                          | Sync targets (commit; do not hand-edit)                                                                                                                                  |
| -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `.apm/packages/<pkg>/` (instructions, skills, hooks, MCP config)                                                     | `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/` — materialized by `apm install`; commit after sync, edit only under `.apm/packages/` |
| `scripts/lib/`                                                                                                       | `.apm/packages/*/.apm/skills/*/scripts/lib/`                                                                                                                             |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh`                  | Paired skill `scripts/` copy                                                                                                                                             |
| `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`                                            | Generated `## Guidelines` in instructions (unless accepting overwrite on next sync)                                                                                      |
| Repo-only paths (for example `scripts/terraform/module_updater.sh`, `.github/actions/**/lib/`, `.github/workflows/`) | —                                                                                                                                                                        |

**Distributable vs maintainer-only:** `.apm/packages/**` ships to other repositories — portable wording only. This-repo rules → [.apm/AGENTS.md](.apm/AGENTS.md) or this file, never package sources.

## Conventions

| Topic           | Rule             |
| --------------- | ---------------- |
| Temporary files | Write to `tmp/`. |
