# Harness Engineering: Terraform

Terraform-specific enforcement toolchain across the [harness engineering](harness-engineering.md) layers.

## Layer-by-Layer Configuration

### Layer 1: Agent Instructions

| Package | Instruction | Scope |
|---------|-------------|-------|
| terraform | terraform | `**/*.tf`, `**/*.tfvars`, `**/*.hcl` |

### Layer 2: Agent Hooks

| PostToolUse (auto-fix) | Stop (validation) |
|------------------------|-------------------|
| terraform fmt | tflint |

### Layer 3: pre-commit

| Hook | Status |
|------|--------|
| terraform_fmt | Commented out |
| terraform_tflint | Commented out |
| terraform_trivy | Commented out |

All Terraform hooks are commented out because they require `terraform init` (project-specific provider/plugin initialization). CI (Layer 4) enforces regardless. See Known Gaps below for planned structural fix.

### Layer 4: CI (`ci-aws-terraform.yaml`)

| Check | Purpose |
|-------|---------|
| terraform fmt | Formatting enforcement |
| terraform validate | Configuration syntax and internal consistency |
| tflint | Terraform-specific linting |
| trivy | Security misconfiguration and vulnerability scanning |
| terraform plan + tfcmt | Plan output posted to PR for review |

**Key behaviors**:

- Terraform plan output is posted to PR via `tfcmt` for review
- trivy scans for misconfigurations, secrets, and vulnerabilities

### Layer 6: Setup Automation

| Step | Effect |
|------|--------|
| `tflint --init` | Initializes tflint plugins (provider-specific rules) |

## Coverage Matrix

Layers 1–2 apply only when development is AI-assisted. For manual development, Layer 3 is currently inactive — CI (Layer 4) serves as the first enforcement point for Terraform.

| Rule Category | Agent Instructions | Agent Hooks | pre-commit | CI |
|---------------|:-:|:-:|:-:|:-:|
| Code formatting | ✓ | ✓ (terraform fmt) | — (commented out) | ✓ |
| Linting | ✓ | ✓ (tflint) | — (commented out) | ✓ |
| Security scanning | — | — | — | ✓ (trivy) |
| Dependency updates | — | — | — | ✓ (Renovate) |

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| All Terraform hooks commented out in pre-commit | Requires `terraform init` (project-specific provider/plugin initialization). CI (Layer 4) enforces regardless. Structural skip planned — see Known Gaps. |

## Known Gaps

### Terraform pre-commit hooks: structural skip

The current design comments out Terraform hooks and relies on developers to uncomment them — a behavioral dependency that contradicts the structural enforcement principle. The planned improvement: keep hooks uncommented and add a guard condition in each hook entry that exits 0 (skip) when `.terraform/` or the provider lock file does not exist. This makes enforcement automatic after `terraform init` without requiring manual opt-in.

## Pending Items

| Item | Status | Rationale for deferral |
|------|--------|------------------------|
| Terraform pre-commit structural skip | Pending | Requires hook wrapper script; current workaround is CI enforcement (Layer 4) |
