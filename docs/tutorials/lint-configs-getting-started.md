# Getting Started with Lint Configs

Install shared lint configuration files and pre-commit hooks for your project. This tutorial takes approximately 2 minutes.

## Prerequisites

- `curl` installed
- A project repository with `git init` completed
- [pre-commit](https://pre-commit.com/) installed

## Goal

After completing this tutorial you will have:

1. Shared lint configs (`.golangci.yaml` or `.tflint.hcl`, `trivy.yaml`, etc.) in your repository
2. A pre-commit configuration with all hooks active
3. Commit message validation via commitlint

## Step 1: Run the Install Script

For Go projects:

```bash
bash <(curl -sL https://raw.githubusercontent.com/y-miyazaki/config/main/install_go.sh)
```

For Terraform projects:

```bash
bash <(curl -sL https://raw.githubusercontent.com/y-miyazaki/config/main/install_terraform.sh)
```

Existing files are skipped. To overwrite with the latest configs:

```bash
bash <(curl -sL https://raw.githubusercontent.com/y-miyazaki/config/main/install_go.sh) --force
```

## Step 2: Activate pre-commit Hooks

```bash
pre-commit install
pre-commit install --hook-type commit-msg
```

For Terraform projects, also initialize providers and tflint:

```bash
terraform init
tflint --init
```

## Verification

```bash
# Verify hooks are installed
pre-commit run --all-files
```

All checks should pass (or show only pre-existing issues in your code).

## Installed Files

| File | Purpose |
| ---- | ------- |
| `.pre-commit-config.yaml` | Pre-commit hook definitions |
| `.golangci.yaml` (Go) | golangci-lint configuration |
| `.tflint.hcl` (Terraform) | tflint configuration |
| `trivy.yaml` | Trivy security scanner configuration |
| `.markdownlint-cli2.yaml` | Markdown linting rules |
| `.gitleaks.toml` | Secret detection rules |
| `.commitlintrc.yaml` | Commit message format rules |

## Next Steps

- Customize `.golangci.yaml` or `.tflint.hcl` for project-specific rules
- [Specification](../reference/specification.md) — For the full list of distributed configs
- [GitHub Actions](github-actions-getting-started.md) — To add CI workflows that enforce the same rules remotely
