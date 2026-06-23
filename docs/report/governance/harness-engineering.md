# Harness Engineering

This document defines the enforcement architecture that ensures developers automatically comply with coding standards, security policies, and operational conventions — without requiring prior knowledge of the rules.

For language-specific toolchain details, see:

- [Harness Engineering: Go](harness-engineering-go.md)
- [Harness Engineering: Terraform](harness-engineering-terraform.md)

## Overview

Harness engineering is the practice of embedding rule enforcement into the development workflow infrastructure so that compliance is structural rather than behavioral. The goal: **a developer — whether using an AI agent or writing code manually — still produces compliant code without reading the coding standards**.

This is achieved through a 6-layer enforcement architecture where each layer catches violations that the previous layer missed or that the developer bypassed. Layers 1–2 apply only to AI-assisted development; for manual development, Layer 3 (pre-commit) is the first enforcement point.

## Enforcement Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Local Development Loop                                         │
│                                                                 │
│  Developer writes code                                          │
│          │                                                      │
│          ▼                                                      │
│  Layer 1: Agent Instructions  ← Guides AI code generation       │
│  (instructions.md / steering)   (AI-assisted only)              │
│          ▼                                                      │
│  Layer 2: Agent Hooks         ← Auto-format + validate          │
│  (PostToolUse / Stop)           (AI-assisted only)              │
│          ▼                                                      │
│  Layer 3: pre-commit          ← Block non-compliant commits     │
│  (commit-msg + pre-commit)      (all developers)                │
│                                                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │ push
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Remote Verification                                            │
│                                                                 │
│  Layer 4: CI                  ← Block non-compliant merges      │
│  (GitHub Actions reusable)                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Async / Infrastructure (independent lifecycle)                  │
│                                                                 │
│  Layer 5: Renovate            ← Automated dependency governance │
│  (Shared policy presets)        Triggers CI on update PRs       │
│                                                                 │
│  Layer 6: Setup Automation    ← Ensures layers 1-3 are active   │
│  (devcontainer init.sh)         Runs on environment creation    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Layer 1: Agent Instructions

Instructions (`.apm/instructions/*.instructions.md`) define coding rules that AI agents follow during code generation. APM (Agent Package Manager) distributes these instruction files and hooks to each project. These are soft controls — they guide but cannot enforce.

**Role**: Reduce violations at the point of generation. Complemented by review skills that provide structured assessment.

## Layer 2: Agent Hooks

Hooks execute automatically during AI agent operation. Two trigger points:

- **PostToolUse** — runs after the agent writes/edits a file (auto-formatting)
- **Stop** — runs when the agent completes a task (validation gate)

**Multi-agent support**: Each hook script detects the active agent (Claude Code, Copilot CLI, Cursor, Kiro CLI, VS Code, Antigravity) from stdin JSON and responds in the expected format. Hook JSON definitions are packaged per-target (`common-hooks-claude`, `common-hooks-copilot`, `common-hooks-cursor`).

## Layer 3: pre-commit

pre-commit hooks run at commit time. Two hook types are installed:

- **pre-commit** — runs on staged files before commit
- **commit-msg** — validates commit message format

### Common pre-commit hooks

| Category | Hooks |
|----------|-------|
| General | check-added-large-files, check-merge-conflict, end-of-file-fixer, trailing-whitespace |
| Secrets | detect-secrets, detect-aws-credentials, detect-private-key, gitleaks |
| Shell | shellcheck, shfmt |
| GitHub Actions | actionlint, zizmor |
| Markdown | markdownlint-cli2 (--fix), markdown-link-check |
| JSON/YAML/TOML | check-json, check-yaml, check-toml, pretty-format-json |

### commit-msg hooks

| Hook | Purpose |
|------|---------|
| commitlint | Enforces Conventional Commits format (`type(scope): subject`) |

**commitlint configuration** (`.commitlintrc.yaml`):

- Extends `@commitlint/config-conventional`
- Allowed types: `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`
- Header max length: 100 characters
- Subject must start lowercase

## Layer 4: CI (GitHub Actions)

Reusable workflows enforce standards on push/PR regardless of local setup. See language-specific documents for workflow details.

| Workflow | Language |
|----------|----------|
| `ci-go.yaml` | [Go](harness-engineering-go.md) |
| `ci-aws-terraform.yaml` | [Terraform](harness-engineering-terraform.md) |
| `ci-github-actions-workflow.yaml` | Common |
| `ci-markdown.yaml` | Common |
| `ci-shell-script.yaml` | Common |

## Layer 5: Renovate

Shared Renovate presets automate dependency governance.

| Policy | Effect |
|--------|--------|
| Patch automerge | Go modules, npm, aqua, mise patches merge automatically |
| Minimum release age | 7 days before adoption (supply-chain risk reduction) |
| Tool version grouping | golangci-lint, terraform, tflint, trivy updates are grouped across mise + CI inputs |
| Vulnerability alerts | OSV alerts with `security` label |

## Layer 6: Setup Automation

`env/common/scripts/init.sh` runs in devcontainer `postCreateCommand` and ensures all enforcement layers are active:

| Step | Effect |
|------|--------|
| `mise trust + install` | Installs pinned tool versions (Go, Terraform, linters, etc.) |
| `apm install --frozen` | Deploys instructions, hooks, skills, MCP servers |
| `pre-commit install` | Activates pre-commit hooks |
| `pre-commit install --hook-type commit-msg` | Activates commitlint |

**Result**: A developer who opens the devcontainer has all enforcement layers active without any manual setup.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| gitleaks in Agent hooks despite pre-commit coverage | Provides immediate feedback during AI-assisted development before commit time. |
| commitlint via pre-commit only (no Agent hook) | Commit timing is identical; adding an Agent hook provides no additional coverage. |
| Shared lint configs in repository (not APM) | APM distributes agent-related files only. `.golangci.yaml`, `.tflint.hcl`, `trivy.yaml` belong in the project repository. Drift management for these files is addressed below. |

## Known Gaps and Future Direction

### Lint config drift across repositories

APM distributes agent instructions and hooks but cannot distribute lint config files (`.golangci.yaml`, `.tflint.hcl`, `trivy.yaml`) because they are not agent-specific. These files currently live in each project repository with no automated sync mechanism.

**Current mitigation**: Renovate presets group tool version updates (golangci-lint, tflint, trivy) so all projects receive version bumps together. However, rule configuration changes (e.g., enabling a new linter) require manual propagation.

**Planned approach**: Adopt a repository-files-sync GitHub Action or template repository pattern to push config changes from this distribution source to consumer repositories via automated PRs. This preserves project autonomy (PRs can be reviewed) while preventing silent drift.

### Tool version single source of truth

All layers (Agent Hooks, pre-commit, CI) resolve tool binaries from the same source: `mise.toml` pins versions, `mise install` provisions them in the devcontainer, and all hooks execute within that environment. AI agents running inside the devcontainer use the same `PATH`-resolved binaries. CI workflows pin versions via `mise.toml` or explicit action inputs that Renovate keeps in sync. No separate tool registry exists for agent environments.

### Escape hatch governance

This document defines enforcement architecture, not operational policy. Bypass mechanisms (`--no-verify`, `nolint` directives, `[skip ci]`) are governed by the team's code review process: PRs that bypass enforcement layers require explicit reviewer approval, and CI logs record which checks were skipped. Detailed audit trail requirements are out of scope for this architecture document.

## Pending Items

| Item | Status | Rationale for deferral |
|------|--------|------------------------|
| Lint config sync (repository-files-sync) | Pending | Evaluating GitHub Action vs template repo pattern |
| `apm audit --ci` in consumer CI | Deferred | MCP distribution causes persistent drift; tool not stable enough |
