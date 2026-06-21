<!-- omit in toc -->
# Configurations for AI Agent Tooling, GitHub Actions, and Renovate

Shared configuration packages for AI agent tooling, GitHub Actions workflows, and Renovate policy reuse.

**[Documentation](https://y-miyazaki.github.io/config/)** · **[APM Tutorial](https://y-miyazaki.github.io/config/tutorials/apm-getting-started/)** · **[GitHub Actions Tutorial](https://y-miyazaki.github.io/config/tutorials/github-actions-getting-started/)** · **[Renovate Tutorial](https://y-miyazaki.github.io/config/tutorials/renovate-getting-started/)**

---

This repository is a shared configuration distribution source. No application code — only reusable packages, workflows, and presets.

- AI agent-related configuration files are shared as APM packages.
- Shared automation is provided through GitHub Actions reusable workflows.
- Shared dependency update policy is provided through Renovate configuration presets.

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
  - [Hooks Limitations](#hooks-limitations)
- [GitHub Actions](#github-actions)
  - [Reuse shared workflows](#reuse-shared-workflows)
- [Renovate](#renovate)
  - [Reuse shared policy](#reuse-shared-policy)
- [License](#license)

## Documentation

Full documentation is hosted at **<https://y-miyazaki.github.io/config/>**.

| Category | Link |
| -------- | ---- |
| Tutorials | [APM](https://y-miyazaki.github.io/config/tutorials/apm-getting-started/) · [GitHub Actions](https://y-miyazaki.github.io/config/tutorials/github-actions-getting-started/) · [Renovate](https://y-miyazaki.github.io/config/tutorials/renovate-getting-started/) |
| How-To | [Troubleshooting](https://y-miyazaki.github.io/config/how-to/troubleshooting/) |
| Reference | [Specification](https://y-miyazaki.github.io/config/reference/specification/) |
| Explanation | [Architecture](https://y-miyazaki.github.io/config/explanation/architecture/) |

## APM

APM is used to share AI agent-related configuration files as packages. Each package bundles MCP servers, hooks, instructions, and skills appropriate for its domain.

### Packages

| Package       | Description                                | MCP Servers | Hooks | Instructions | Skills |
| ------------- | ------------------------------------------ | ----------- | ----- | ------------ | ------ |
| common        | Shared workflows, documentation, and tools | 5           | 0     | 4            | 7      |
| aws           | AWS development                            | 5           | 0     | 0            | 0      |
| terraform     | Terraform development (cloud-agnostic)     | 1           | 0     | 1            | 2      |
| terraform-aws | Terraform + AWS integration                | 1           | 0     | 0            | 0      |
| go            | Go development                             | 0           | 0     | 1            | 2      |
| shell-script  | Shell script development                   | 0           | 0     | 1            | 2      |

Hooks are distributed as separate target-specific packages because each AI agent has a different hooks JSON format:

| Hooks Package              | Target  | Hooks | Description                               |
| -------------------------- | ------- | ----- | ----------------------------------------- |
| common-hooks-claude        | Claude  | 6     | Common hooks for Claude Code              |
| common-hooks-copilot       | Copilot | 6     | Common hooks for GitHub Copilot CLI       |
| common-hooks-cursor        | Cursor  | 6     | Common hooks for Cursor                   |
| go-hooks-claude            | Claude  | 1     | Go hooks for Claude Code                  |
| go-hooks-copilot           | Copilot | 1     | Go hooks for GitHub Copilot CLI           |
| go-hooks-cursor            | Cursor  | 1     | Go hooks for Cursor                       |
| shell-script-hooks-claude  | Claude  | 2     | Shell script hooks for Claude Code        |
| shell-script-hooks-copilot | Copilot | 2     | Shell script hooks for GitHub Copilot CLI |
| shell-script-hooks-cursor  | Cursor  | 2     | Shell script hooks for Cursor             |
| terraform-hooks-claude     | Claude  | 2     | Terraform hooks for Claude Code           |
| terraform-hooks-copilot    | Copilot | 2     | Terraform hooks for GitHub Copilot CLI    |
| terraform-hooks-cursor     | Cursor  | 2     | Terraform hooks for Cursor                |

### MCP Servers

| Package       | Server                         | Description                    |
| ------------- | ------------------------------ | ------------------------------ |
| common        | context7                       | Context management             |
| common        | fetch                          | HTTP fetch                     |
| common        | github                         | GitHub Copilot MCP             |
| common        | codebase-memory-mcp            | Codebase memory                |
| common        | lean-ctx                       | Lean context management        |
| aws           | aws-mcp                        | AWS MCP proxy                  |
| aws           | aws-knowledge-mcp-server       | AWS knowledge base             |
| aws           | aws-documentation-mcp-server   | AWS documentation              |
| aws           | aws-pricing-mcp-server         | AWS pricing                    |
| aws           | awslabs-aws-api-mcp-server     | AWS API operations             |
| terraform     | hashicorp-terraform-mcp-server | Terraform operations           |
| terraform-aws | awslabs-terraform-mcp-server   | Terraform AWS provider support |

### Hooks

| Hooks Package         | Hook                      | Trigger                | Description                                   |
| --------------------- | ------------------------- | ---------------------- | --------------------------------------------- |
| common-hooks-*        | lean-ctx                  | PreToolUse/PostToolUse | Context observation and rewrite/redirect      |
| common-hooks-*        | markdownlint-cli2         | Stop                   | Auto-fix Markdown files with markdownlint     |
| common-hooks-*        | markdown-link-check       | Stop                   | Check Markdown links                          |
| common-hooks-*        | github-actions-actionlint | Stop                   | Lint GitHub Actions workflows with actionlint |
| common-hooks-*        | github-actions-ghalint    | Stop                   | Lint GitHub Actions workflows with ghalint    |
| common-hooks-*        | github-actions-zizmor     | Stop                   | Security scan GitHub Actions with zizmor      |
| go-hooks-*            | golangci-lint             | Stop                   | Auto-fix Go files with golangci-lint          |
| terraform-hooks-*     | terraform-fmt             | PostToolUse            | Run terraform fmt on changed files            |
| terraform-hooks-*     | tflint                    | Stop                   | Run tflint on changed files                   |
| shell-script-hooks-*  | shellcheck                | Stop                   | Run shellcheck on changed shell scripts       |
| shell-script-hooks-*  | shfmt                     | PostToolUse            | Auto-format shell scripts with shfmt          |

> **Note:** `*` represents target suffix (`claude`, `copilot`, or `cursor`). Each target has identical hook scripts with different JSON formats.

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

### Hooks Limitations

Hooks JSON format differs across AI agents and cannot be auto-converted between targets. Key constraints:

| Constraint | Detail |
| ---------- | ------ |
| Format incompatibility | Each agent uses a different JSON structure (event names, command keys, timeout keys, nesting). A single hooks.json cannot serve multiple agents. |
| Target-specific packages required | Hooks must be distributed as separate packages per target (`*-hooks-copilot`, `*-hooks-cursor`, `*-hooks-claude`). |
| Cursor requires `version: 1` | Cursor errors if `version` is missing. APM does not inject `version` automatically — use a `postinstall` script (e.g. `jq '. + {"version": 1}'`). |
| Claude Code uses 2-level nesting | Claude Code hooks use `{ matcher, hooks: [...] }` structure unlike other agents' flat arrays. |
| Event name casing varies | Copilot CLI uses camelCase (`agentStop`), Claude Code/VS Code use PascalCase (`Stop`), Cursor uses lowercase (`stop`). |
| `matcher` is Claude Code only | Tool name regex filtering (`matcher`) is available only in Claude Code. Other agents execute hooks for all tool invocations. |
| Script portability | The hook scripts themselves are multi-agent aware (detect agent via stdin JSON and respond appropriately). Only the hook JSON definitions need per-target packaging. |

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
