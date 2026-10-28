# Harness Engineering: Terraform

Terraform-specific enforcement toolchain across the [harness engineering](harness-engineering.md) layers.

## Layer-by-Layer Configuration

### Layer 1: Agent Instructions

| Package   | Instruction | Scope                                |
| --------- | ----------- | ------------------------------------ |
| terraform | terraform   | `**/*.tf`, `**/*.tfvars`, `**/*.hcl` |

### Layer 2: Agent Hooks

| PostToolUse (auto-fix) | Stop (validation) |
| ---------------------- | ----------------- |
| terraform fmt          | tflint            |

### Layer 3: pre-commit

| Hook             | Behavior                                       |
| ---------------- | ---------------------------------------------- |
| terraform_fmt    | Format check on staged `.tf` files             |
| terraform_tflint | Lint with project `.tflint.hcl` config         |
| terraform_trivy  | Security scan with project `trivy.yaml` config |

Distributed via `.pre-commit-config-terraform.yaml` (installed by `install_terraform.sh`). All hooks are active — they require `terraform init` to have been run for full provider-aware checks.

### Layer 4: CI (`ci-aws-terraform.yaml`)

| Check                  | Purpose                                              |
| ---------------------- | ---------------------------------------------------- |
| terraform fmt          | Formatting enforcement                               |
| terraform validate     | Configuration syntax and internal consistency        |
| tflint                 | Terraform-specific linting                           |
| trivy                  | Security misconfiguration and vulnerability scanning |
| terraform plan + tfcmt | Plan output posted to PR for review                  |

**Key behaviors**:

- Terraform plan output is posted to PR via `tfcmt` for review
- trivy scans for misconfigurations, secrets, and vulnerabilities

### Layer 6: Setup Automation

| Step            | Effect                                               |
| --------------- | ---------------------------------------------------- |
| `tflint --init` | Initializes tflint plugins (provider-specific rules) |

## Coverage Matrix

Layers 1–2 apply only when development is AI-assisted. For manual development, Layer 3 (pre-commit) is the first enforcement point.

| Rule Category      | Agent Instructions |    Agent Hooks    | pre-commit |      CI      |
| ------------------ | :----------------: | :---------------: | :--------: | :----------: |
| Code formatting    |         ✓          | ✓ (terraform fmt) |     ✓      |      ✓       |
| Linting            |         ✓          |    ✓ (tflint)     |     ✓      |      ✓       |
| Security scanning  |         —          |         —         | ✓ (trivy)  |  ✓ (trivy)   |
| Dependency updates |         —          |         —         |     —      | ✓ (Renovate) |

## Design Decisions

| Decision                                            | Rationale                                                                                                                               |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Terraform pre-commit hooks require `terraform init` | Full provider-aware checks need initialized plugins. Projects run `terraform init` + `tflint --init` during setup.                      |
| tflint in Agent Hooks without `terraform init`      | Basic rules (naming, syntax, best practices) work without provider plugins. Provides immediate feedback during AI-assisted development. |
| Separate `.pre-commit-config-terraform.yaml`        | Distributed via `install_terraform.sh`. All hooks active — unlike the base config which comments them out.                              |

## Known Gaps

### Provider-dependent checks without init

If a developer has not run `terraform init`, pre-commit hooks will fail for provider-specific rules (e.g., `aws_instance` attribute validation). Basic syntax and naming rules still pass. The `init.sh` setup automation mitigates this by running `tflint --init` on devcontainer creation.

## Pending Items

| Item                                                          | Status   | Rationale for deferral                                                                        |
| ------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------- |
| Terraform pre-commit structural skip (guard on `.terraform/`) | Deferred | Separate config file resolves the distribution issue; guard script is a future DX improvement |
