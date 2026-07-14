# Config Repository Architecture

This document describes the repository architecture, major component boundaries, and how shared assets are organized for distribution and reuse.

## Overview

The repository is organized as a distribution source for reusable AI agent settings, workflows, and validation utilities.

The architecture separates:

- metadata and entrypoints at repository root
- reusable package bundles under `.apm/packages/`
- execution and validation scripts under `scripts/`
- documentation and references under `docs/`

## Component Layout

### Root Layer

- `apm.yml`: top-level package metadata and dependency entrypoint
- `apm.lock.yaml`: deterministic lock state
- `.github/`: workflow and policy assets
- `renovate/`: shared Renovate presets

### Package Layer

- `.apm/packages/common/`: shared instructions, skills, and MCP integrations (5 MCP servers, 4 instructions, 8 skills)
- `.apm/packages/common-hooks-*`: target-specific common hooks (6 hooks per target: Claude, Copilot, Cursor)
- `.apm/packages/aws/`: AWS-focused MCP integrations (5 MCP servers)
- `.apm/packages/terraform/`: Terraform-focused integrations (1 MCP server, 1 instruction, 2 skills)
- `.apm/packages/terraform-hooks-*`: target-specific Terraform hooks (2 hooks per target: Claude, Copilot, Cursor)
- `.apm/packages/terraform-aws/`: Terraform + AWS provider MCP integration (1 MCP server)
- `.apm/packages/go/`: Go-focused instructions and skills (1 instruction, 2 skills)
- `.apm/packages/go-hooks-*`: target-specific Go hooks (1 hook per target: Claude, Copilot, Cursor)
- `.apm/packages/shell-script/`: shell-focused instructions and skills (2 instructions, 2 skills)
- `.apm/packages/shell-script-hooks-*`: target-specific shell script hooks (2 hooks per target: Claude, Copilot, Cursor)

Each package can be consumed independently through APM path-based dependencies.

> **Note:** Hooks packages are split per target because each AI agent uses a different hooks JSON format (event names, command keys, nesting structure). The hook scripts themselves are multi-agent aware and shared across targets.

### Execution Layer

- `scripts/`: validation, build, deploy, and helper commands
- `test/`: script and language-specific test assets
- `env/`: container and environment tooling

## Data and Control Flow

1. Consumers reference this repository (or a package path) from their APM config.
2. `apm install` resolves dependencies using `apm.yml` and `apm.lock.yaml`.
3. Package assets are materialized to target locations.
4. Hooks and instructions influence agent/runtime behavior in consumer repositories.

## Configuration Philosophy

APM packages distribute **configuration**. Tool execution rules differ by layer.

| Layer  | Purpose                           | Tool resolution                    | When tool absent            |
| ------ | --------------------------------- | ---------------------------------- | --------------------------- |
| MCP    | Agent capabilities at runtime     | `npx` / `uvx` with pinned versions | Server fails to start       |
| Hooks  | Optional in-session lint/format   | Native binary on `PATH`            | Exit 0 — session continues  |
| Skills | On-demand validation when invoked | Native binary via `validate.sh`    | `SKIP` in structured output |

### Consumer Setup Tiers

**Minimal** (required for MCP):

- APM CLI
- Node.js (`npx`) and/or Python with [uv](https://docs.astral.sh/uv/) (`uvx`)
- Network access for MCP runtime fetch

`apm install` deploys configuration. MCP servers resolve packages on first connection — no per-tool global install step.

**Recommended dev** (optional, for full hook/skill enforcement):

- Install linters on `PATH` (for example via [mise](https://mise.jdx.dev/) as in this repository's `mise.toml`)
- Hooks and skills then run checks instead of skipping

This repository dogfoods the recommended tier for CI and local validation. Consumers on the minimal tier still receive working MCP and agent instructions; hooks become best-effort no-ops when tools are absent.

### MCP — Runtime Resolution

- MCP servers use `npx` (Node.js) or `uvx` (Python via uv) with pinned package versions in `apm.yml` `args`.
- Pin versions in `apm.lock.yaml` for deterministic APM package resolution.
- **Optional binary MCP servers** (no npm/PyPI distribution, for example `codebase-memory-mcp`) require a separate consumer install or can be omitted.

### Hooks — Optional Enforcement

- Hooks are **not** a quality guarantee. They lint or format changed files when a native binary is on `PATH`.
- Most hook tools (`actionlint`, `golangci-lint`, `shellcheck`, `terraform`, `tflint`) are native binaries — not `npx`/`uvx` packages.
- When a tool is missing, hooks exit 0 so agent sessions are not blocked. Users may not notice enforcement was skipped unless the hook emits a stderr notice.

### Skills — Explicit Validation

- Skills run only when an agent invokes them through `scripts/validate.sh`.
- Missing tools produce `SKIP` entries in structured output — visible to the agent, not silent success.
- Skills complement hooks; neither replaces CI or pre-commit in consumer repositories.

Package authoring rules: [.apm/AGENTS.md](../../.apm/AGENTS.md). Behavioral contracts: [Config Repository Functional Specification](../reference/specification.md#configuration-philosophy).

## Validation Model

Validation is layered to reduce drift:

- CI workflows for APM audit (`ci-apm-audit`), markdown lint, GitHub Actions validation, and shell script checks
- package-level validation scripts under `scripts/`
- language/tool specific validation via instructions and skills
- CI-based checks for workflows and repository consistency

## Operational Constraints

- package paths and file names must remain stable for downstream consumers
- generated artifacts should remain in ignored temporary locations
- instruction and skill changes should be validated before release
