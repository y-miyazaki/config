@AGENTS.md

# Project Instructions

## Repository Rules

### Project Overview

Shared configuration distribution source — no application code. Deliverables: APM packages, reusable GitHub Actions workflows, Renovate policy presets.

### APM Packages

- Edit instructions, skills, hooks, and MCP config under `.apm/packages/` only.
- Do not edit generated directories (`.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`, `.vscode/`, `apm_modules/`) — `apm install` overwrites them.
- After package changes: run `scripts/self/apm/sync_guidelines_from_categories.pl` when `category-*.md` or sync-mapped instructions change → `apm install --update` → `apm audit --ci`.
- Package authoring detail: [.apm/AGENTS.md](.apm/AGENTS.md).

### Scripts and Skill Mirrors

Cross-cutting rules when editing `scripts/` or paired skill copies. **Apply these even when not touching `.apm/`** — nested `.apm/AGENTS.md` is not loaded for `scripts/` work.

| You changed | Also do |
| ----------- | ------- |
| `scripts/lib/` (shared libraries) | Edit here — skill `scripts/lib/` copies are regenerated, not hand-edited → `bash scripts/self/ai/sync_skill_lib.sh` → `apm install --update` |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh`, or paired skill copies | Edit one side → `bash scripts/self/ai/sync_validate_mirror.sh` (default: repo → skill; `--from-skill` when editing the skill copy; `--domain <shell-script\|go\|terraform>` to limit scope). Do not hand-edit the paired file. |
| Repo-only script (for example `scripts/terraform/module_updater.sh`, `.github/actions/**/lib/`) | Update matching Bats under `test/bats/` in the same change |

- Drift check: `bash scripts/self/ai/sync_skill_lib.sh --check` and `bash scripts/self/ai/sync_validate_mirror.sh --check`.
- Shell style and Bats: stem `shell-script` and `bats` instructions (distributed under `.cursor/rules/` after `apm install`).
- `validate.sh` path-layout differences (skill vs repo): [.apm/AGENTS.md § Validation Scripts Mirror](.apm/AGENTS.md#validation-scripts-mirror-scripts--skill).

### Workflow Conventions

- Reusable workflows use `workflow_call` trigger.
- File names: `ci-*` (CI), `cd-*` (CD), `on-*` (event-triggered callers).
- Keys in `inputs`, `env`, `permissions`, `with` MUST be alphabetically ordered.

### Manual Validation

Run on demand when troubleshooting CI or when explicitly requested:

- Mirror drift: `sync_skill_lib.sh --check`, `sync_validate_mirror.sh --check`
- APM integrity: `apm install --update`, `apm audit --ci`
- Workflow lint: `actionlint`, `ghalint run`, `zizmor .github/workflows/` (see `github-actions-validation` skill)

### Temporary Artifacts

Write to `tmp/`.

### Documentation Editing

When structure, modules, or features change, update related `README.md` and `docs/` accordingly.

## Token Optimization

### MCP Policies

- lean-ctx, fetch should be used for all context fetching for optimization

### When to Read Reports

Only read `docs/report/` files when explicitly asked or when comparison/research context is needed.

## Security Guidelines

- Secrets MUST NOT appear in source code, logs, or test data.
- No destructive operations as defaults in command examples.
