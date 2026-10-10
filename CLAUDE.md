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

## Permission parity (MUST)

These four files express one permission policy for different agents. They are repo-owned and hand-edited: `apm install` does not materialize them, so the `.cursor/` sync-target row above does not apply to `cli.json` or `permissions.json`.

| File                       | Permission surface                                                                                             |
| -------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `.claude/settings.json`    | `permissions.allow` / `deny` / `ask` — `Bash(cmd:*)`, `Read(glob)`, `WebFetch`, `mcp__<server>`                |
| `.cursor/cli.json`         | `permissions.allow` / `deny` — `Shell(cmd)`, `Read(glob)`, `WebFetch(domain)`, `Mcp(server:tool)`              |
| `.cursor/permissions.json` | `terminalAllowlist` (bare command), `mcpAllowlist`; no deny array — denials go in `autoRun.block_instructions` |
| `.lean-ctx.toml`           | `shell_allowlist_extra` (bare command); shell commands only, no deny mechanism                                 |

Change one, change all four in the same commit, at the same permission level. A command added to one allowlist is added to every allowlist; a command denied in one is denied — not merely dropped from allow — in every file that has a deny mechanism, and recorded as a `block_instructions` sentence in `.cursor/permissions.json`. A command that exists in only one agent's toolchain still gets an entry everywhere it is expressible. Translate syntax per the table rather than copying a rule verbatim between files, and keep each list in its existing sort order.

## Conventions

| Topic           | Rule             |
| --------------- | ---------------- |
| Temporary files | Write to `tmp/`. |
