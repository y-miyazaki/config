<!-- omit in toc -->
# Config Repository Architecture

This document describes the repository architecture, major component boundaries, and how shared assets are organized for distribution and reuse.

<!-- omit in toc -->
## Table of Contents

- [Overview](#overview)
- [Component Layout](#component-layout)
  - [Root Layer](#root-layer)
  - [Package Layer](#package-layer)
  - [Execution Layer](#execution-layer)
- [Data and Control Flow](#data-and-control-flow)
- [Validation Model](#validation-model)
- [Operational Constraints](#operational-constraints)

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

- `.apm/packages/common/`: shared instructions, skills, and MCP integrations (5 MCP servers, 4 instructions, 7 skills)
- `.apm/packages/common-hooks-*`: target-specific common hooks (6 hooks per target: Claude, Copilot, Cursor)
- `.apm/packages/aws/`: AWS-focused MCP integrations (5 MCP servers)
- `.apm/packages/terraform/`: Terraform-focused integrations (1 MCP server, 1 instruction, 2 skills)
- `.apm/packages/terraform-hooks-*`: target-specific Terraform hooks (2 hooks per target: Claude, Copilot, Cursor)
- `.apm/packages/terraform-aws/`: Terraform + AWS provider MCP integration (1 MCP server)
- `.apm/packages/go/`: Go-focused instructions and skills (1 instruction, 2 skills)
- `.apm/packages/go-hooks-*`: target-specific Go hooks (1 hook per target: Claude, Copilot, Cursor)
- `.apm/packages/shell-script/`: shell-focused instructions and skills (1 instruction, 2 skills)
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
