# Getting Started with APM Packages

Install shared AI agent configuration packages (MCP servers, hooks, instructions, and skills) in your repository using APM. This tutorial takes approximately 5 minutes.

## Prerequisites

- [APM CLI](https://github.com/microsoft/apm) installed
- A target repository with `git init` completed
- One of the supported AI agents: Claude Code, GitHub Copilot CLI, or Cursor

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
Deployed: 5 MCP servers, 6 hooks, 4 instructions, 7 skills
```

This creates `apm_modules/` (gitignored) and deploys configuration to agent-specific directories (e.g., `.copilot/`, `.claude/`, `.cursor/`).

## Verification

```bash
# Check packages are installed
ls apm_modules/

# Check agent config files exist
ls .copilot/ 2>/dev/null || ls .claude/ 2>/dev/null || ls .cursor/ 2>/dev/null

# Validate integrity
apm audit
```

All commands should succeed without errors.

## Next Steps

- How-To: Troubleshooting (`docs/how-to/troubleshooting.md`) — For resolving common install and sync issues.
- Reference: Specification (`docs/reference/specification.md`) — To look up package structure and behavioral contracts.
- Explanation: Architecture (`docs/explanation/architecture.md`) — To understand the system design and package boundaries.
