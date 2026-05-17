# y-miyazaki/config

Shared agent skills and instructions for AI-assisted development.

## Contents

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

## Install with APM

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

## Usage in other repositories

After adding dependencies to your project's `apm.yml`, teammates only need:

```bash
apm install
```

This resolves all dependencies from `apm.lock.yaml` and deploys skills, instructions, and MCP servers to the appropriate target directories.

## License

Apache-2.0
