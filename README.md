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

| Category | Link |
| -------- | ---- |
| Tutorials | [APM](https://y-miyazaki.github.io/config/tutorials/apm-getting-started/) · [GitHub Actions](https://y-miyazaki.github.io/config/tutorials/github-actions-getting-started/) · [Renovate](https://y-miyazaki.github.io/config/tutorials/renovate-getting-started/) |
| How-To | [Troubleshooting](https://y-miyazaki.github.io/config/how-to/troubleshooting/) |
| Reference | [Specification](https://y-miyazaki.github.io/config/reference/specification/) |
| Explanation | [Architecture](https://y-miyazaki.github.io/config/explanation/architecture/) |

## APM

APM distributes AI agent-related configuration files as packages. Each package bundles MCP servers, hooks, instructions, and skills appropriate for its domain.

| Package | Description |
| ------- | ----------- |
| common | Shared workflows, documentation, and tools |
| aws | AWS development |
| terraform | Terraform development (cloud-agnostic) |
| terraform-aws | Terraform + AWS integration |
| go | Go development |
| shell-script | Shell script development |

For detailed package contents (MCP servers, hooks, skills, instructions), see the [Specification](https://y-miyazaki.github.io/config/reference/specification/).

### Individual Packages

```sh
apm install y-miyazaki/config/.apm/packages/common
apm install y-miyazaki/config/.apm/packages/aws
apm install y-miyazaki/config/.apm/packages/terraform
apm install y-miyazaki/config/.apm/packages/terraform-aws
apm install y-miyazaki/config/.apm/packages/go
apm install y-miyazaki/config/.apm/packages/shell-script
```

## GitHub Actions

Reusable workflow definitions shared via `workflow_call`. Use from your repository:

```yaml
jobs:
  markdown:
    uses: y-miyazaki/config/.github/workflows/ci-markdown.yaml@main
```

For production usage, pin a commit SHA instead of a branch.

## Renovate

Shared dependency update policy presets. Add to your `.github/renovate.json`:

```json
{
  "extends": ["github>y-miyazaki/config//renovate/default"]
}
```

## License

[Apache-2.0](LICENSE)
