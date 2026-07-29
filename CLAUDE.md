@AGENTS.md

# Project Instructions

## Precedence

When instructions conflict:

1. Explicit user instructions
2. [AGENTS.md](AGENTS.md) (repository-wide behavior)
3. Domain rules for the paths being edited (override `.cursor/rules/` and other agent defaults on those paths):
   - [.apm/AGENTS.md](.apm/AGENTS.md) — `.apm/packages/**`
   - [.github/workflows/AGENTS.md](.github/workflows/AGENTS.md) — `.github/workflows/**`, `.github/actions/**`
   - This file — edit routing and cross-cutting repo conventions
4. Codebase conventions and companion stems under `.cursor/rules/`
5. General best practices

Design detail belongs in `docs/`, not here.

## Instruction authoring

Meta-rules for this repository's instruction files (not for distributable package sources — see [.apm/AGENTS.md](.apm/AGENTS.md)):

| File | Write |
| ---- | ----- |
| Root [AGENTS.md](AGENTS.md) | Cross-agent behavior (safety, verification, communication). |
| This file (`CLAUDE.md`) | Precedence, edit routing, pointers — keep as `@AGENTS.md` shim. |
| Nested `AGENTS.md` (for example `.apm/`, `.github/workflows/`) | **MUST / MUST NOT** for that path scope only. |

| Rule | Requirement |
| ---- | ----------- |
| Content | Rules and judgments the agent cannot infer from code. Not directory inventories or design essays. |
| Length | Prefer tables; aim for ~100 lines per file. Background → `docs/explanation/`. |
| Duplication | Domain rules live in one nested `AGENTS.md`; other files link, do not copy. |
| Distributable format | `*.instructions.md` and synced `.cursor/rules/*.mdc` follow companion `instructions` / `agent-skills` stems; review with `instructions-review` / `agent-skills-review` on PRs. |

## Repository

Shared configuration **distribution source** — no application code. Deliverables: APM packages, reusable GitHub Actions workflows, Renovate policy presets.

## Edit routing (MUST)

| Edit here (source of truth)                                                                                          | Do not edit                                                                         |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `.apm/packages/<pkg>/` (instructions, skills, hooks, MCP config)                                                     | `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/` |
| `scripts/lib/`                                                                                                       | `.apm/packages/*/.apm/skills/*/scripts/lib/`                                        |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh`                  | Paired skill `scripts/` copy                                                        |
| `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`                                            | Generated `## Guidelines` in instructions (unless accepting overwrite on next sync) |
| Repo-only paths (for example `scripts/terraform/module_updater.sh`, `.github/actions/**/lib/`, `.github/workflows/`) | —                                                                                   |

**Distributable vs maintainer-only:** `.apm/packages/**` ships to other repositories — portable wording only. This-repo rules (Loop callers, sync paths, `may_edit` conventions) → [.apm/AGENTS.md](.apm/AGENTS.md) or this file, never package sources.

## Post-change (MUST)

| Change touches | Action |
| -------------- | ------ |
| Mirrored rows in the table above | Agent `stop` hooks run `scripts/self/apm/sync_apm_artifacts.sh` (sync, `apm install --update`, drift check, `apm audit --ci`). Do not run manually unless hooks are unavailable or `--check` only. |
| Repo-only paths (`.github/`, `test/bats/`, …) | Update paired Bats in the same change (TEST-00). |
| `scripts/*/validate.sh` from skill direction | `sync_validate_mirror.sh --from-skill` |

Cross-cutting `scripts/` rules apply even when not touching `.apm/` — `.apm/AGENTS.md` is not loaded for `scripts/` work alone.

## Conventions

| Topic | Rule |
| ----- | ---- |
| Temporary files | Write to `tmp/`. |
| Documentation | When structure, modules, or features change, update related `README.md` and `docs/`. |
| Shell / Bats | Companion stems `shell-script`, `bats` (`.cursor/rules/`). |
| Workflows / actions | [.github/workflows/AGENTS.md](.github/workflows/AGENTS.md) — not duplicated here. |
| APM package authoring | [.apm/AGENTS.md](.apm/AGENTS.md). |
| Context fetching | Prefer lean-ctx and fetch MCP tools. |
