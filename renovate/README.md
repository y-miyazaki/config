# Renovate Configuration Guide

This directory contains Renovate configuration files for dependency update automation and review policy.

- `default.json`: main Renovate policy for this repository
- `github-actions-tool-version.json`: custom regex managers for tool-version inputs in GitHub Actions workflows

## Policy (Source of Truth)

This section defines the intended update policy first, independent from implementation details.

### Core Principles

- Prefer safety over speed for infrastructure/runtime-impacting updates.
- Allow automerge only for low-risk updates.
- Keep labeling rules and automerge rules separate for readability and easier policy changes.
- Use explicit exception rules when broad safe-update policies are overridden.

### Automerge Policy by Dependency Category

- Aqua packages (`aqua.yaml`): automerge up to `patch` only.
- Aqua registry (`aquaproj/aqua-registry`): automerge `minor` and `patch`.
- Docker (`dockerfile`, `docker-compose`): do not automerge by default.
- Docker `digest`/`pin`: manual review required (never automerge).
- GitHub Actions (`github-actions`): do not automerge by default.
- GitHub official actions (`actions/*`): automerge `patch` only.
- Go modules (`gomod`): automerge library `patch` only (exclude Go toolchain package `go`).
- Go toolchain (`go` package in `gomod`): do not automerge `major`/`minor`.
- npm: automerge `patch` only.
- Python packages (`poetry`, `pip_requirements`, `pipenv`): automerge library `patch` only (poetry, pip_requirements); pipenv has no automerge.
- Terraform (`terraform`, `terraform-version`): do not automerge.
- Shared safe update types (`lockFileMaintenance`, `digest`, `pin`): automerge allowed unless explicitly overridden by a stricter rule.

### Labeling Policy by Dependency Category

- Aqua: `aqua`
- Docker: `docker`
- GitHub Actions: `github-actions`
- Go modules: `go`
- npm: `npm`
- Python: `python`
- Terraform: `terraform`
- Automerged updates: `automerge`
- Baseline for dependency PRs: `dependencies`

## Global Behavior (`default.json`)

- Base labels: `dependencies`
- Dependency dashboard: enabled
- Concurrency limits: `prConcurrentLimit=5`, `branchConcurrentLimit=5`
- Rebase policy: `behind-base-branch`
- Version range strategy: `replace`
- Lock file maintenance: enabled with schedule `before 4am on monday`

## Dependency Rules by Category

### Aqua (`aqua.yaml`)

- Label all updates with `aqua`
- Automerge patch updates only
- Commit prefix: `renovate(aqua):`

### Aqua Registry (`aquaproj/aqua-registry`)

- Label all updates with `aqua`
- Automerge minor and patch updates
- Commit prefix: `renovate(aqua):`

### Docker (`dockerfile`, `docker-compose`)

- Label updates with `docker`
- Default: no automerge
- `digest` and `pin` updates: manual review required (explicitly no automerge)

### GitHub Actions (`github-actions` manager)

- Label updates with `github-actions`
- Default: no automerge
- Official actions (`actions/*`) patch updates are automerged
- Commit prefixes:
  - `renovate(github-actions):` (general)
  - `renovate(github-actions-official):` (official actions patch)

### Go Modules (`gomod`)

- Label all updates with `go`
- Go toolchain (`go`) major/minor updates require review (no automerge)
- Non-toolchain patch updates are automerged
- Commit prefix: `renovate(go):`

### npm (`npm`)

- Label all updates with `npm`
- Automerge patch updates only

### Python (`poetry`, `pip_requirements`, `pipenv`)

- Label all updates with `python`
- Poetry and pip_requirements: automerge patch updates only
- Pipenv: no automerge (requires manual review for all versions)
- Commit prefix: `renovate(python):`

### Terraform (`terraform`, `terraform-version`)

- Label updates with `terraform`
- No automerge
- Group Terraform module/provider updates into one PR with group name `terraform dependencies`

### Safe Update Types (cross-cutting)

- `lockFileMaintenance`, `digest`, and `pin` are marked as safe for automerge
- Label with `automerge`
- Note: Docker `digest`/`pin` is explicitly overridden to no automerge by a later rule

## GitHub Actions Tool Version Rules (`github-actions-tool-version.json`)

### Scope

- Uses `custom.regex` managers
- Targets workflow files under `.github/workflows/*.yml` and `.github/workflows/*.yaml`
- Detects tool version inputs such as `terraform_version`, `go_version`, `golangci_lint_version`, etc.

### Labels and Automerge

- Label all matched tool-version updates with `github-actions-tool-version`
- Automerge patch updates for `custom.regex` workflow tool dependencies
- Add `automerge` label to automerged updates

### Managed Tools

Enabled managers include:

- `kayac/ecspresso`
- `Songmu/ecschedule`
- `hashicorp/terraform`
- `terraform-linters/tflint`
- `woodruffw/zizmor`
- `golangci/golangci-lint`
- `golang/vuln`
- `golang/go`
- `goreleaser/goreleaser`
- `koalaman/shellcheck`
- `schemaspy/schemaspy`

Disabled managers (checksum-coupled updates) include:

- `y-miyazaki/absc`
- `y-miyazaki/arc`
- `google/go-jsonnet`
- `suzuki-shunsuke/tfcmt`
- `rhysd/actionlint`
- `suzuki-shunsuke/ghalint`

## Maintenance Notes

When updating rule behavior:

1. Keep base labeling rules and automerge rules separate where possible.
2. Document any exception rules that intentionally override broad safe-update policies.
3. Re-validate JSON syntax after edits.
