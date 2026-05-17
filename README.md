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

Install the full package:

```bash
apm install y-miyazaki/config
```

Install a specific skill:

```bash
apm install y-miyazaki/config/.apm/skills/go-review
apm install y-miyazaki/config/.apm/skills/terraform-review
```

Install a specific instruction:

```bash
apm install y-miyazaki/config/.apm/instructions/go.instructions.md
```

## License

Apache-2.0
