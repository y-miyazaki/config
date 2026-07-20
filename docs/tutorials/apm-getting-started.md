# Getting Started with APM Packages

Install shared AI agent configuration packages (MCP servers, hooks, instructions, and skills) in your repository using APM. This tutorial takes approximately 5 minutes.

## Prerequisites

- [APM CLI](https://github.com/microsoft/apm) installed
- A target repository with `git init` completed
- One of the supported AI agents: Claude Code, GitHub Copilot CLI, Cursor, or OpenAI Codex CLI
- Node.js (`npx`) and/or Python with [uv](https://docs.astral.sh/uv/) (`uvx`) for MCP runtime resolution

**Note:** [Loop Engineering](../explanation/loop-engineering/loop-engineering-design.md) callers also support `codex` as a runtime engine (`claude` \| `copilot` \| `codex` \| `cursor`). APM `targets` in this repository currently deploy to `claude` and `cursor` only; Codex skills/hooks packages are not distributed yet.

**Minimal setup** — `apm install` plus runtime runners above. MCP servers fetch on demand; per-linter global installs are not required.

**Recommended dev setup** — install linters on `PATH` (for example via [mise](https://mise.jdx.dev/)) so hooks and skills run checks instead of skipping. Hooks are optional enforcement, not a quality guarantee.

See [Config Repository Architecture](../explanation/architecture.md#configuration-philosophy) for layer-by-layer rules (MCP / hooks / skills).

## Goal

After completing this tutorial you will have:

1. An `apm.yml` configured with shared packages
2. MCP servers, hooks, instructions, and skills deployed for your AI agent

## Step 1: Create apm.yml

Create `apm.yml` at your repository root:

```yaml
name: my-project
version: 1.0.0
description: My project
license: MIT
targets:
  - copilot
includes: auto
dependencies:
  apm:
    - github.com/y-miyazaki/config/.apm/packages/common
    - github.com/y-miyazaki/config/.apm/packages/common-hooks-copilot
```

Replace `copilot` with your agent target (`claude`, `copilot`, or `cursor`). Match the hooks package suffix to your target.

## Step 2: Add Domain-Specific Packages

For Go, Terraform, or shell script projects, add the relevant packages:

```yaml
dependencies:
  apm:
    - github.com/y-miyazaki/config/.apm/packages/common
    - github.com/y-miyazaki/config/.apm/packages/common-hooks-copilot
    - github.com/y-miyazaki/config/.apm/packages/go
    - github.com/y-miyazaki/config/.apm/packages/go-hooks-copilot
```

Available domain packages: `go`, `terraform`, `terraform-aws`, `shell-script`, `aws`.

## Step 3: Install Packages

```bash
apm install --frozen
```

**Expected Output:**

```text
Installing dependencies...
  ✓ github.com/y-miyazaki/config/.apm/packages/common
  ✓ github.com/y-miyazaki/config/.apm/packages/common-hooks-copilot
Deployed: 5 MCP servers, 6 hooks, 4 instructions, 8 skills
```

This creates `apm_modules/` (gitignored) and deploys configuration to agent-specific directories (e.g., `.copilot/`, `.claude/`, `.cursor/`).

## Verification

```bash
# Check packages are installed
ls apm_modules/

# Check agent config files exist
ls .copilot/ 2>/dev/null || ls .claude/ 2>/dev/null || ls .codex/ 2>/dev/null || ls .cursor/ 2>/dev/null

# Validate integrity
apm audit
```

All commands should succeed without errors.

## Next Steps

- [Troubleshooting](../how-to/troubleshooting.md) — For resolving common install and sync issues.
- [Specification](../reference/specification.md) — To look up package structure and behavioral contracts.
- [Architecture](../explanation/architecture.md) — To understand the system design and package boundaries.
