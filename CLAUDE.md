@AGENTS.md

# Project Instructions

## Edit routing (MUST)

| Edit here (source of truth)                                                                                                                                                                           | Sync targets (commit; do not hand-edit)                                                                                                                                  |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `.apm/packages/<pkg>/` (instructions, skills, hooks, MCP config)                                                                                                                                      | `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/` — materialized by `apm install`; commit after sync, edit only under `.apm/packages/` |
| `scripts/lib/`                                                                                                                                                                                        | `.apm/packages/*/.apm/skills/*/scripts/lib/`                                                                                                                             |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh`                                                                                                   | Paired skill `scripts/` copy                                                                                                                                             |
| `.apm/packages/<pkg>/.apm/skills/<skill>-review/references/category-*.md`                                                                                                                             | Generated `## Guidelines` in instructions (unless accepting overwrite on next sync)                                                                                      |
| Repo-only paths (for example `cmd/terraform/` (source of the committed `scripts/terraform/module_updater` binary — rebuild with `make build` there), `.github/actions/**/lib/`, `.github/workflows/`) | —                                                                                                                                                                        |

**Distributable vs maintainer-only:** `.apm/packages/**` ships to other repositories — portable wording only. This-repo rules → [.apm/CLAUDE.md](.apm/CLAUDE.md) or this file, never package sources.

**Docs sync (MUST):** code and docs move together (see Document sync in `AGENTS.md`). Search for the docs first; for `.github/workflows/**` and `.github/actions/**` the code-to-docs map is in [.github/workflows/CLAUDE.md](.github/workflows/CLAUDE.md#docs-sync-must).

## Permission parity (MUST)

These three files express one permission policy for different agents. They are repo-owned and hand-edited: `apm install` does not materialize them, so the `.cursor/` sync-target row above does not apply to `cli.json` or `permissions.json`.

Restrictions and hooks that apply only to this repository (for example denying edits to the sync targets, or the `scripts/self/hooks/bats_changed.sh` Stop hook) belong in the git-ignored `.claude/settings.local.json`, not in these shared files: this project is meant to be reusable, so shared settings stay generic. Their absence from the shared files is intentional.

| File                       | Permission surface                                                                                             |
| -------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `.claude/settings.json`    | `permissions.allow` / `deny` / `ask` — `Bash(cmd:*)`, `Read(glob)`, `WebFetch`, `mcp__<server>`                |
| `.cursor/cli.json`         | `permissions.allow` / `deny` — `Shell(cmd)`, `Read(glob)`, `WebFetch(domain)`, `Mcp(server:tool)`              |
| `.cursor/permissions.json` | `terminalAllowlist` (bare command), `mcpAllowlist`; no deny array — denials go in `autoRun.block_instructions` |

Change one, change all three in the same commit, at the same permission level. A command added to one allowlist is added to every allowlist; a command denied in one is denied — not merely dropped from allow — in every file that has a deny mechanism, and recorded as a `block_instructions` sentence in `.cursor/permissions.json`. A command that exists in only one agent's toolchain still gets an entry everywhere it is expressible. Translate syntax per the table rather than copying a rule verbatim between files, and keep each list in its existing sort order.

## Hook-covered tools (MUST)

Do not run a tool directly when a hook in `.claude/settings.json` already runs it (`Stop` / `PostToolUse`); the hook result is the source of truth. Check `hooks` in `.claude/settings.json` first. If the hooks cannot be read, treat the tools below as hook-covered.

| Hook-covered tool     | Trigger                     |
| --------------------- | --------------------------- |
| `actionlint`          | `Stop`                      |
| `ghalint`             | `Stop`                      |
| `gitleaks`            | `Stop`                      |
| `go test`             | `Stop`                      |
| `golangci-lint`       | `Stop`                      |
| `markdown-link-check` | `Stop`                      |
| `markdownlint-cli2`   | `Stop`                      |
| `prettier`            | `PostToolUse` (Edit, Write) |
| `shellcheck`          | `Stop`                      |
| `shfmt`               | `PostToolUse` (Edit, Write) |
| `zizmor`              | `Stop`                      |

`shfmt` and `prettier` run after both the Edit and Write tools. The `Stop` hook also runs `scripts/self/apm/sync_apm_artifacts.sh` (sync, not a lint tool). The sync is hook-covered too: do not run `apm install`/sync by hand, and omit the sync targets (`.claude/`, `.cursor/`, `.github/hooks`, `apm_modules/`) from Completion — no "not yet synced", "pending sync", or "uncommitted" notes.

## AGENTS.md portability (MUST)

`AGENTS.md` is a generic agent constitution meant to be reused across repositories. Do not write repo-specific names in it (paths, skill names, tool names, hook lists, sync targets); put those in this file or the nearest `CLAUDE.md`.

## Conventions

| Topic           | Rule             |
| --------------- | ---------------- |
| Temporary files | Write to `tmp/`. |
