# Harness Engineering for Go and Terraform Projects

This document defines the enforcement architecture that ensures developers automatically comply with coding standards, security policies, and operational conventions — without requiring prior knowledge of the rules.

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

| Package | Instruction | Scope |
|---------|-------------|-------|
| common | github-actions-workflow | `.github/workflows/**/*.yaml` |
| common | markdown | `README.md`, `docs/**/*.md` |
| go | go | `**/*.go` |
| terraform | terraform | `**/*.tf`, `**/*.tfvars`, `**/*.hcl` |
| shell-script | shell-script | `**/*.sh` |

**Role**: Reduce violations at the point of generation. Complemented by review skills that provide structured assessment.

## Layer 2: Agent Hooks

Hooks execute automatically during AI agent operation. Two trigger points:

- **PostToolUse** — runs after the agent writes/edits a file (auto-formatting)
- **Stop** — runs when the agent completes a task (validation gate)

| Language | PostToolUse (auto-fix) | Stop (validation) |
|----------|------------------------|-------------------|
| Go | — | golangci-lint |
| Terraform | terraform fmt | tflint |
| Shell | shfmt | shellcheck |
| Markdown | markdownlint-cli2 | markdown-link-check |
| GitHub Actions | — | actionlint, ghalint, zizmor |
| Security | — | gitleaks |

**Multi-agent support**: Each hook script detects the active agent (Claude Code, Copilot CLI, Cursor, Kiro CLI, VS Code, Antigravity) from stdin JSON and responds in the expected format. Hook JSON definitions are packaged per-target (`common-hooks-claude`, `common-hooks-copilot`, `common-hooks-cursor`).

**Design principle**: golangci-lint covers Go formatting via its integrated formatters, so a separate `gofumpt` PostToolUse hook is unnecessary.

## Layer 3: pre-commit

pre-commit hooks run at commit time. Two hook types are installed:

- **pre-commit** — runs on staged files before commit
- **commit-msg** — validates commit message format

### pre-commit hooks

| Category | Hooks |
|----------|-------|
| General | check-added-large-files, check-merge-conflict, end-of-file-fixer, trailing-whitespace |
| Secrets | detect-secrets, detect-aws-credentials, detect-private-key, gitleaks |
| Go | golangci-lint (with --fix) |
| Terraform | terraform_fmt, terraform_tflint, terraform_trivy (all commented out; uncomment per project after `terraform init`) |
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

Reusable workflows enforce standards on push/PR regardless of local setup.

| Workflow | Checks |
|----------|--------|
| `ci-go.yaml` | go mod tidy, go test -race, golangci-lint (reviewdog PR comments), govulncheck, trivy |
| `ci-aws-terraform.yaml` | terraform fmt, validate, tflint, trivy, terraform plan + tfcmt |
| `ci-github-actions-workflow.yaml` | actionlint, ghalint, zizmor |
| `ci-markdown.yaml` | markdownlint-cli2, markdown-link-check |
| `ci-shell-script.yaml` | shellcheck, shfmt |

**Key behaviors**:
- Go lint uses `reviewdog` for inline PR comments on pull requests
- Terraform plan output is posted to PR via `tfcmt` for review
- Security scanning (trivy, govulncheck) generates artifacts but does not block merge for informational findings
- SBOM (CycloneDX) is generated and uploaded as artifact

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
| `tflint --init` | Initializes tflint plugins |

**Result**: A developer who opens the devcontainer has all enforcement layers active without any manual setup.

## Coverage Matrix

Layers 1–2 apply only when development is AI-assisted. For manual development, Layer 3 (pre-commit) is the first enforcement point.

| Rule Category | Agent Instructions | Agent Hooks | pre-commit | CI |
|---------------|:-:|:-:|:-:|:-:|
| Code formatting (Go) | ✓ | ✓ (golangci-lint) | ✓ | ✓ |
| Code formatting (Terraform) | ✓ | ✓ (terraform fmt) | ✓ | ✓ |
| Code formatting (Shell) | ✓ | ✓ (shfmt) | ✓ | ✓ |
| Linting (Go) | ✓ | ✓ | ✓ | ✓ |
| Linting (Terraform) | ✓ | ✓ (tflint) | ✓ | ✓ |
| Linting (GitHub Actions) | ✓ | ✓ | ✓ | ✓ |
| Secrets detection | ✓ | ✓ (gitleaks) | ✓ | ✓ (trivy) |
| Vulnerability scanning | — | — | — | ✓ (govulncheck, trivy) |
| Commit message format | — | — | ✓ (commitlint) | — |
| Dependency updates | — | — | — | ✓ (Renovate) |
| Architecture/design | ✓ (review skills) | — | — | — |

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| No coverage threshold gate | Coverage percentage becomes the goal rather than test quality. Instructions guide toward 80% but CI does not enforce it. |
| No `depguard` in shared config | Project package structures vary too much. Layer violation rules are project-specific. |
| No `go-arch-lint` in shared config | Overkill for Lambda/CLI; only useful for large layered services. Projects add it individually. |
| gitleaks in Agent hooks despite pre-commit coverage | Provides immediate feedback during AI-assisted development before commit time. |
| commitlint via pre-commit only (no Agent hook) | Commit timing is identical; adding an Agent hook provides no additional coverage. |
| All Terraform hooks commented out in pre-commit | Requires `terraform init` (project-specific provider/plugin initialization). Projects uncomment after local init is configured. |
| Shared lint configs in repository (not APM) | APM distributes agent-related files only. `.golangci.yaml`, `.tflint.hcl`, `trivy.yaml` belong in the project repository. |

## Pending Items

| Item | Status | Rationale for deferral |
|------|--------|------------------------|
| License compliance (`go-licenses`) | Pending | Not yet prioritized |
| Dependency review action | Pending | Not yet prioritized |
| `apm audit --ci` in consumer CI | Deferred | MCP distribution causes persistent drift; tool not stable enough |
| `go-arch-lint` | Per-project | Not suitable as shared harness; projects opt in individually |
