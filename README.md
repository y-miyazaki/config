<!-- omit in toc -->
# Configurations for AI Agent Tooling, GitHub Actions, and Renovate

Shared configuration packages for AI agent tooling, GitHub Actions workflows, and Renovate policy reuse.

This repository is a shared configuration repository. It is focused on practical usage and reuse of settings across projects.

- Specifications for this repository are documented under [`docs/`](docs/), including repository structure in [`docs/reference/specification.md`](docs/reference/specification.md).
- Usage and installation steps are documented in this `README.md`.
- AI agent-related configuration files are shared as APM packages.
- Shared automation is provided through GitHub Actions workflows.
- Shared dependency update policy is provided through Renovate configuration.

<!-- omit in toc -->
## Table of Contents

- [Documentation](#documentation)
- [APM](#apm)
  - [Packages](#packages)
  - [MCP Servers](#mcp-servers)
  - [Hooks](#hooks)
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
- Specification and structure: [`docs/reference/specification.md`](docs/reference/specification.md)
- Documentation index: [`docs/index.md`](docs/index.md)

## APM

APM is used to share AI agent-related configuration files as packages. Each package bundles MCP servers, hooks, instructions, and skills appropriate for its domain.

### Packages

| Package       | Description                                | MCP Servers | Hooks | Instructions | Skills |
| ------------- | ------------------------------------------ | ----------- | ----- | ------------ | ------ |
| common        | Shared workflows, documentation, and tools | 6           | 6     | 4            | 7      |
| aws           | AWS development                            | 5           | 0     | 0            | 0      |
| terraform     | Terraform development (cloud-agnostic)     | 1           | 2     | 1            | 2      |
| terraform-aws | Terraform + AWS integration                | 1           | 0     | 0            | 0      |
| go            | Go development                             | 0           | 1     | 1            | 2      |
| shell-script  | Shell script development                   | 0           | 2     | 1            | 2      |

### MCP Servers

| Package       | Server                         | Description                    |
| ------------- | ------------------------------ | ------------------------------ |
| common        | context7                       | Context management             |
| common        | fetch                          | HTTP fetch                     |
| common        | github                         | GitHub Copilot MCP             |
| common        | codebase-memory-mcp            | Codebase memory                |
| common        | lean-ctx                       | Lean context management        |
| common        | playwright                     | Browser automation             |
| aws           | aws-mcp                        | AWS MCP proxy                  |
| aws           | aws-knowledge-mcp-server       | AWS knowledge base             |
| aws           | aws-documentation-mcp-server   | AWS documentation              |
| aws           | aws-pricing-mcp-server         | AWS pricing                    |
| aws           | awslabs-aws-api-mcp-server     | AWS API operations             |
| terraform     | hashicorp-terraform-mcp-server | Terraform operations           |
| terraform-aws | awslabs-terraform-mcp-server   | Terraform AWS provider support |

### Hooks

| Package      | Hook                      | Trigger          | Description                                  |
| ------------ | ------------------------- | ---------------- | -------------------------------------------- |
| common       | lean-ctx                  | preToolUse/postToolUse | Context observation and rewrite/redirect     |
| common       | markdownlint-cli2         | agentStop        | Auto-fix Markdown files with markdownlint    |
| common       | markdown-link-check       | agentStop        | Check Markdown links                         |
| common       | github-actions-actionlint | agentStop        | Lint GitHub Actions workflows with actionlint |
| common       | github-actions-ghalint    | agentStop        | Lint GitHub Actions workflows with ghalint   |
| common       | github-actions-zizmor     | agentStop        | Security scan GitHub Actions with zizmor     |
| go           | golangci-lint             | agentStop        | Auto-fix Go files with golangci-lint         |
| terraform    | terraform-fmt             | postToolUse      | Run terraform fmt on changed files           |
| terraform    | tflint                    | agentStop        | Run tflint on changed files                  |
| shell-script | shellcheck                | agentStop        | Run shellcheck on changed shell scripts      |
| shell-script | shfmt                     | agentStop        | Auto-format shell scripts with shfmt         |

### Skills

| Package      | Skill                     | Description                       |
| ------------ | ------------------------- | --------------------------------- |
| common       | agent-skills-review       | Review agent skill definitions    |
| common       | docs-creation             | Create documentation              |
| common       | github-actions-review     | Review GitHub Actions workflows   |
| common       | github-actions-validation | Validate GitHub Actions workflows |
| common       | github-pr-body            | Generate PR body                  |
| common       | instructions-review       | Review instruction files          |
| common       | markdown-validation       | Validate Markdown files           |
| go           | go-review                 | Review Go code                    |
| go           | go-validation             | Validate Go code                  |
| terraform    | terraform-review          | Review Terraform code             |
| terraform    | terraform-validation      | Validate Terraform code           |
| shell-script | shell-script-review       | Review shell scripts              |
| shell-script | shell-script-validation   | Validate shell scripts            |

### Instructions

| Package      | Instruction             | Scope                                |
| ------------ | ----------------------- | ------------------------------------ |
| common       | agent-skills            | Agent skill files                    |
| common       | github-actions-workflow | GitHub Actions workflows             |
| common       | instructions            | Instruction files                    |
| common       | markdown                | Markdown files                       |
| go           | go                      | `**/*.go`                            |
| terraform    | terraform               | `**/*.tf`, `**/*.tfvars`, `**/*.hcl` |
| shell-script | shell-script            | `**/*.sh`                            |

### Install

Install the full package (all sub-packages):

```bash
apm install y-miyazaki/config --target copilot
```

> **Note:** `--target` is not required if your project already has an `apm.yml` (auto-detected from the `target:` setting).

### Individual packages

```bash
# Common (MCP servers + hooks + instructions + skills)
apm install y-miyazaki/config/.apm/packages/common

# AWS (MCP servers only)
apm install y-miyazaki/config/.apm/packages/aws

# Terraform (MCP server + hook + instruction + skills)
apm install y-miyazaki/config/.apm/packages/terraform

# Terraform + AWS (MCP server only)
apm install y-miyazaki/config/.apm/packages/terraform-aws

# Go (hook + instruction + skills)
apm install y-miyazaki/config/.apm/packages/go

# Shell Script (hook + instruction + skills)
apm install y-miyazaki/config/.apm/packages/shell-script
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
apm install --frozen
```

This resolves all dependencies from `apm.lock.yaml` and deploys skills, instructions, hooks, and MCP servers to the appropriate target directories.

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
