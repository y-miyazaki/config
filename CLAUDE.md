@AGENTS.md

# Project Instructions

## Edit routing (MUST)

| Edit here (source of truth)                                                                                          | Do not edit                                                                         |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `.apm/packages/<pkg>/` (instructions, skills, hooks, MCP config)                                                     | `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/` |
| `scripts/lib/`                                                                                                       | `.apm/packages/*/.apm/skills/*/scripts/lib/`                                        |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh`                  | Paired skill `scripts/` copy                                                        |
| `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`                                            | Generated `## Guidelines` in instructions (unless accepting overwrite on next sync) |
| Repo-only paths (for example `scripts/terraform/module_updater.sh`, `.github/actions/**/lib/`, `.github/workflows/`) | —                                                                                   |

**Distributable vs maintainer-only:** `.apm/packages/**` ships to other repositories — portable wording only. This-repo rules → [.apm/AGENTS.md](.apm/AGENTS.md) or this file, never package sources.

## Post-change (MUST)

| Change touches                                | Action                                                                                                                                                                                             |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mirrored rows in the table above              | Agent `stop` hooks run `scripts/self/apm/sync_apm_artifacts.sh` (sync, `apm install --update`, drift check, `apm audit --ci`). Do not run manually unless hooks are unavailable or `--check` only. |
| Repo-only paths (`.github/`, `test/bats/`, …) | Update paired Bats in the same change (TEST-00).                                                                                                                                                   |
| `scripts/*/validate.sh` from skill direction  | `sync_validate_mirror.sh --from-skill`                                                                                                                                                             |

Cross-cutting `scripts/` rules apply even when not touching `.apm/` — `.apm/AGENTS.md` is not loaded for `scripts/` work alone.

## Conventions

| Topic           | Rule             |
| --------------- | ---------------- |
| Temporary files | Write to `tmp/`. |
