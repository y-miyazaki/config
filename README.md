<!-- omit in toc -->
# y-miyazaki/config

Shared configuration packages for AI agent tooling, GitHub Actions workflows, and Renovate policy reuse.

This repository is a shared configuration repository. It is focused on practical usage and reuse of settings across projects.

- Specifications for this repository are documented under [`docs/`](docs/), including repository structure in [`docs/specification.md`](docs/specification.md).
- Usage and installation steps are documented in this `README.md`.
- AI agent-related configuration files are shared as APM packages.
- Shared automation is provided through GitHub Actions workflows.
- Shared dependency update policy is provided through Renovate configuration.

<!-- omit in toc -->
## Table of Contents

- [Documentation](#documentation)
- [APM](#apm)
  - [Contents](#contents)
  - [Skills](#skills)
  - [Instructions](#instructions)
  - [Install](#install)
  - [Individual packages](#individual-packages)
  - [Other targets](#other-targets)
  - [Use in other repositories](#use-in-other-repositories)
- [GitHub Actions](#github-actions)
  - [Reuse shared workflows](#reuse-shared-workflows)
- [Renovate](#renovate)
  - [Reuse shared policy](#reuse-shared-policy)
- [License](#license)

## Documentation

- Usage: this `README.md`
- Specification and structure: [`docs/specification.md`](docs/specification.md)

## APM

APM is used to share AI agent-related configuration files (skills, instructions, and MCP package sets).

### Contents

### Skills

| Skill                     | Description                       |
| ------------------------- | --------------------------------- |
| agent-skills-review       | Review agent skill definitions    |
| docs-creation             | Create documentation              |
| github-actions-review     | Review GitHub Actions workflows   |
| github-actions-validation | Validate GitHub Actions workflows |
| github-pr-body            | Generate PR body                  |
| go-review                 | Review Go code                    |
| go-validation             | Validate Go code                  |
| instructions-review       | Review instruction files          |
| markdown-validation       | Validate Markdown files           |
| shell-script-review       | Review shell scripts              |
| shell-script-validation   | Validate shell scripts            |
| terraform-review          | Review Terraform code             |
| terraform-validation      | Validate Terraform code           |

### Instructions

| Instruction             | Scope                                |
| ----------------------- | ------------------------------------ |
| agent-skills            | Agent skill files                    |
| dac                     | Diagram-as-code files                |
| github-actions-workflow | GitHub Actions workflows             |
| go                      | `**/*.go`                            |
| markdown                | Markdown files                       |
| shell-script            | `**/*.sh`                            |
| terraform               | `**/*.tf`, `**/*.tfvars`, `**/*.hcl` |

### Install

Install the full package (skills + instructions + common/performance MCP servers):

```bash
apm install y-miyazaki/config --target copilot
```

> **Note:** `--target` is not required if your project already has an `apm.yml` (auto-detected from the `target:` setting).

### Individual packages

Skills and instructions only:

```bash
apm install y-miyazaki/config/.apm/skills/go-review
apm install y-miyazaki/config/.apm/skills/terraform-review
apm install y-miyazaki/config/.apm/instructions/go.instructions.md
```

MCP server packages:

```bash
# Common (GitHub, Context7, Playwright, Fetch)
apm install y-miyazaki/config/.apm/packages/common-mcp

# AWS
apm install y-miyazaki/config/.apm/packages/aws-mcp

# Terraform (cloud-agnostic)
apm install y-miyazaki/config/.apm/packages/terraform-mcp

# Terraform + AWS
apm install y-miyazaki/config/.apm/packages/terraform-aws-mcp

# Performance (lean-ctx, codebase-memory-mcp)
apm install y-miyazaki/config/.apm/packages/performance-mcp
```

### Other targets

```bash
# Claude
apm install y-miyazaki/config --target claude

# Cursor
apm install y-miyazaki/config --target cursor

# All targets
apm install y-miyazaki/config --target all
```

### Use in other repositories

After adding dependencies to your project's `apm.yml`, teammates only need:

```bash
apm install
```

This resolves all dependencies from `apm.lock.yaml` and deploys skills, instructions, and MCP servers to the appropriate target directories.

## GitHub Actions

GitHub Actions workflows are shared as reusable workflow definitions in this repository.

### Reuse shared workflows

Use this repository's reusable workflows from your repository workflows:

```yaml
jobs:
	markdown:
		uses: y-miyazaki/config/.github/workflows/ci-markdown.yaml@main
```

For production usage, pin a commit SHA instead of a branch.

## Renovate

Renovate configuration is shared as reusable policy presets.

### Reuse shared policy

Create or update your `.github/renovate.json`:

```json
{
	"extends": ["github>y-miyazaki/config//renovate/default"]
}
```

This enables the shared Renovate baseline and policy defaults maintained in this repository.

## License

Apache-2.0
