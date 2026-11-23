# Configurations for AI Agent Tooling, GitHub Actions, and Renovate

Shared configuration packages for AI agent tooling, GitHub Actions workflows, and Renovate policy reuse.

**[Documentation](https://y-miyazaki.github.io/config/)** · **[APM Tutorial](https://y-miyazaki.github.io/config/tutorials/apm-getting-started/)** · **[GitHub Actions Tutorial](https://y-miyazaki.github.io/config/tutorials/github-actions-getting-started/)** · **[Renovate Tutorial](https://y-miyazaki.github.io/config/tutorials/renovate-getting-started/)**

---

This repository is a shared configuration distribution source. No application code — only reusable packages, workflows, and presets.

## Key Features

- **APM Packages** — AI agent-related configuration files (MCP servers, hooks, instructions, skills) distributed as composable packages for Claude, Copilot, and Cursor.
- **Reusable GitHub Actions Workflows** — Shared CI/CD workflows callable via `workflow_call` from any repository.
- **Renovate Presets** — Shared dependency update policy for consistent Renovate configuration.
- **Multi-Agent Support** — Packages target Claude Code, GitHub Copilot CLI, and Cursor with agent-specific hook formats.

## Quick Start

### Prerequisites

- [mise](https://mise.jdx.dev/) (or install tools listed in `mise.toml` manually)
- [APM CLI](https://github.com/microsoft/apm)

### Install

```sh
apm install y-miyazaki/config --target copilot
```

Other targets:

```sh
apm install y-miyazaki/config --target claude
apm install y-miyazaki/config --target cursor
apm install y-miyazaki/config --target all
```

For existing projects with `apm.yml`:

```sh
apm install --frozen
```

## Documentation

Full documentation is hosted at **<https://y-miyazaki.github.io/config/>**.

| Category    | Link                                                                                                                                                                                                                                                              |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tutorials   | [APM](https://y-miyazaki.github.io/config/tutorials/apm-getting-started/) · [GitHub Actions](https://y-miyazaki.github.io/config/tutorials/github-actions-getting-started/) · [Renovate](https://y-miyazaki.github.io/config/tutorials/renovate-getting-started/) |
| How-To      | [Troubleshooting](https://y-miyazaki.github.io/config/how-to/troubleshooting/)                                                                                                                                                                                    |
| Reference   | [Specification](https://y-miyazaki.github.io/config/reference/specification/)                                                                                                                                                                                     |
| Explanation | [Architecture](https://y-miyazaki.github.io/config/explanation/architecture/)                                                                                                                                                                                     |

## APM

APM distributes AI agent-related configuration files as packages. Each package bundles MCP servers, hooks, instructions, and skills appropriate for its domain.

| Package          | Description                                              |
| ---------------- | -------------------------------------------------------- |
| common           | Forge-neutral review, markdown, docs-creator, shared MCP |
| repo-maintenance | Changelog, docs sync, CI repair, refactor, tech-debt     |
| github           | GitHub Issues/PRs (`gh`) and GitHub MCP                  |
| github-actions   | GitHub Actions workflow review and validation            |
| loop             | Generic loop checker (`loop-verifier`)                   |
| aws              | AWS development                                          |
| terraform        | Terraform development (cloud-agnostic)                   |
| terraform-aws    | Terraform AWS-specific rules + MCP (use with terraform)  |
| go               | Go development                                           |
| shell-script     | Shell script development                                 |

For detailed package contents (MCP servers, hooks, skills, instructions), see the [Specification](https://y-miyazaki.github.io/config/reference/specification/).

### Individual Packages

```sh
apm install y-miyazaki/config/.apm/packages/common
apm install y-miyazaki/config/.apm/packages/repo-maintenance
apm install y-miyazaki/config/.apm/packages/github
apm install y-miyazaki/config/.apm/packages/github-actions
apm install y-miyazaki/config/.apm/packages/loop
apm install y-miyazaki/config/.apm/packages/aws
apm install y-miyazaki/config/.apm/packages/terraform
apm install y-miyazaki/config/.apm/packages/terraform-aws
apm install y-miyazaki/config/.apm/packages/go
apm install y-miyazaki/config/.apm/packages/shell-script
```

## Lint Configs

Shared lint configuration files (`.golangci.yaml`, `.tflint.hcl`, `trivy.yaml`, etc.) for consumer projects. Install with one command:

```sh
# Go projects
bash <(curl -sL https://raw.githubusercontent.com/y-miyazaki/config/main/install_go.sh)

# Terraform projects
bash <(curl -sL https://raw.githubusercontent.com/y-miyazaki/config/main/install_terraform.sh)
```

Existing files are not overwritten. To force overwrite with the latest configs:

```sh
bash <(curl -sL https://raw.githubusercontent.com/y-miyazaki/config/main/install_go.sh) --force
```

## GitHub Actions

Reusable workflows in `.github/workflows/` that you call from your own repository with `workflow_call`. Each file starts with a description and usage comment that lists its inputs and secrets.

```yaml
jobs:
  markdown:
    uses: y-miyazaki/config/.github/workflows/ci-markdown.yaml@main
```

For production usage, pin a commit SHA instead of a branch.

Files named `on-*.yaml` are this repository's own triggers (push, schedule, and so on) and are not meant to be called from other repositories.

### CI workflows (`ci-*`)

| Workflow                     | Description                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------- |
| `ci-markdown`                | Markdown lint with markdownlint-cli2 and markdown-link-check                          |
| `ci-shell-script`            | shellcheck, shfmt, bash syntax and shebang checks, Bats/ShellSpec discovery           |
| `ci-go`                      | Go tests, golangci-lint, and govulncheck                                              |
| `ci-nodejs`                  | Node.js install, test, and audit for every `package.json` found in each workspace     |
| `ci-terraform`               | `terraform fmt`, `validate`, and tflint without AWS credentials                       |
| `ci-aws-terraform`           | Terraform fmt, validate, tflint, and plan with AWS credentials                        |
| `ci-aws-ecs`                 | ECS jsonnet format check and ecspresso verify per service                             |
| `ci-github-actions-workflow` | Workflow lint and security checks with actionlint, ghalint, and zizmor                |
| `ci-sast`                    | Static application security testing with CodeQL and Semgrep                           |
| `ci-security`                | Trivy filesystem scan, CycloneDX SBOM generation, and PR dependency review            |
| `ci-apm-audit`               | `apm install` with the pinned APM CLI, then `apm audit`                               |
| `ci-vsix-audit`              | Scan pinned VS Code extensions from `devcontainer.json` and `.vscode/extensions.json` |
| `ci-mise-update-lock`        | Update `mise.lock` and auto-commit through a GitHub App                               |
| `ci-aqua-update-checksum`    | Update `aqua-checksums.json` and auto-commit through a GitHub App                     |
| `ci-loop-agent`              | Run a loop agent (L1, L2, L3) and finalize its result                                 |
| `ci-loop-caller`             | Shared detect → execute → record-skip job graph for branch/PR loop callers            |
| `ci-loop-caller-entity`      | Same job graph for entity (Issue) loop callers                                        |

### CD workflows (`cd-*`)

| Workflow                                    | Description                                                              |
| ------------------------------------------- | ------------------------------------------------------------------------ |
| `cd-aws-terraform`                          | Terraform init, plan, and apply                                          |
| `cd-aws-ecs`                                | Validate jsonnet and run ecspresso verify/deploy for ECS services        |
| `cd-aws-go-registry`                        | Build Go application Docker images and push them to Amazon ECR           |
| `cd-aws-resources`                          | Generate AWS resource outputs and upload them as a zip artifact          |
| `cd-aws-batch-schedules`                    | Generate AWS Batch schedules with absc and upload them as an artifact    |
| `cd-aws-schemaspy`                          | Generate database documentation with SchemaSpy                           |
| `cd-aws-service-control`                    | Unified entry point that dispatches to the service-control workflows     |
| `cd-aws-service-control-ec2`                | Start or stop EC2 instances                                              |
| `cd-aws-service-control-ecs-service`        | Start or stop ECS services                                               |
| `cd-aws-service-control-ecs-scheduled-task` | Enable or disable EventBridge schedules for ECS tasks                    |
| `cd-aws-service-control-rds-cluster`        | Start or stop RDS clusters                                               |
| `cd-aws-service-control-redshift`           | Pause or resume Redshift clusters                                        |
| `cd-aws-service-control-batch`              | Enable or disable AWS Batch job queues                                   |
| `cd-go-releaser`                            | Build cross-platform binaries and create GitHub releases with GoReleaser |
| `cd-mkdocs`                                 | Build a MkDocs site and upload it as an artifact                         |
| `cd-github-pages`                           | Deploy an uploaded artifact to GitHub Pages                              |
| `cd-github-pages-multi`                     | Merge multiple artifacts into one site and deploy it to GitHub Pages     |

See the [GitHub Actions Tutorial](https://y-miyazaki.github.io/config/tutorials/github-actions-getting-started/) and the [workflow design notes](docs/explanation/github-workflows-design.md) for secrets, inputs, and versioning.

## Renovate

Shared dependency update policy presets in `renovate/`. Add to your `.github/renovate.json`:

```json
{
  "extends": ["github>y-miyazaki/config//renovate/default"]
}
```

### What `renovate/default.json` does

| Area                | Behavior                                                                                                                                                                                                                                      |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base presets        | `config:recommended`, Docker image digest pinning, GitHub Actions SHA pinning, config migration, weekly lock file maintenance, aqua-renovate-config                                                                                           |
| Commits and labels  | Semantic commits with `chore` type, `renovate(<category>):` prefix, `dependencies` label plus a per-category label (`aqua`, `docker`, `github-actions`, `go`, `mise`, `npm`, `python`, `terraform`, `tflint`)                                 |
| Safety              | `minimumReleaseAge` of 7 days with the `strict` internal checks filter, OSV vulnerability alerts, `security` label on vulnerability fix PRs                                                                                                   |
| Throughput          | Dependency Dashboard enabled, at most 10 concurrent PRs and branches, rebase when behind the base branch, timezone `Asia/Tokyo`                                                                                                               |
| Automerge           | Patch updates only for aqua, mise, npm, Python, Go modules (not the Go toolchain), and `actions/*`; `minor` and `patch` for aqua-registry; `digest`, `pin`, `lockFileMaintenance`, and `replacement` updates                                  |
| Manual review       | Docker, GitHub Actions (except `actions/*` patch), Terraform, tflint plugins, Go toolchain `major`/`minor`, and Dockerfile `digest`/`pin` updates are never automerged                                                                        |
| Terraform           | Provider updates refresh `.terraform.lock.hcl`; modules and providers are grouped; weekly lock file maintenance                                                                                                                               |
| Cross-file grouping | One PR per tool across workflow inputs, `mise.toml`, Dockerfile, and pre-commit: apm, ecschedule, ecspresso, gitleaks, golangci-lint, goreleaser, markdownlint-cli2, markdown-link-check, mise, semgrep, terraform, tflint, trivy, uv, zizmor |

Related presets in the same directory add custom regex managers. Extend them separately when you need them:

| Preset                                    | Description                                              |
| ----------------------------------------- | -------------------------------------------------------- |
| `renovate/github-actions-tool-version`    | Track tool-version inputs in GitHub Actions workflows    |
| `renovate/pre-commit-config-tool-version` | Track hook `rev` versions in `.pre-commit-config.yaml`   |
| `renovate/apm-mcp-version`                | Track MCP package versions in `.apm/packages/**/apm.yml` |

See [renovate/README.md](renovate/README.md) for the full policy and the [Renovate Tutorial](https://y-miyazaki.github.io/config/tutorials/renovate-getting-started/).

## License

[Apache-2.0](LICENSE)
