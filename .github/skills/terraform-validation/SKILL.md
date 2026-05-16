---
name: terraform-validation
description: >-
  Validate Terraform syntax, linting, and security with terraform fmt/validate, tflint, and trivy.
  Use when committing Terraform changes, running CI validation, or checking IaC security issues.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- Terraform path or directory (required)
- Validation script: `terraform-validation/scripts/validate.sh` (required)
- Optional flags: `--fix`, `--verbose`

## Output Specification

Structured results in fixed order: terraform fmt, terraform validate, tflint, trivy config.

See [references/common-output-format.md](references/common-output-format.md) for detailed format specification.

## Execution Scope

- **Always use `scripts/validate.sh`** for comprehensive validation. Do not run individual commands.
- Script runs all checks in deterministic order.
- Individual commands are for debugging only (see [references/common-individual-commands.md](references/common-individual-commands.md)).
- **Do not review code design decisions** (use terraform-review for that)

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [common-troubleshooting.md](references/common-troubleshooting.md) - Read when checks fail unexpectedly.
- [common-individual-commands.md](references/common-individual-commands.md) - Read when debugging one tool directly.
- [category-security.md](references/category-security.md) - Read when trivy reports security findings.

## Workflow

1. Run `bash terraform-validation/scripts/validate.sh`.
2. If needed, scope target directories for faster feedback.
3. Use `--fix` for formatting corrections and `--verbose` for diagnostics.
4. Re-run until all checks pass.

### Examples

```bash
bash terraform-validation/scripts/validate.sh
bash terraform-validation/scripts/validate.sh ./terraform/base/
bash terraform-validation/scripts/validate.sh --fix --verbose
```

## Best Practices

- Run full validation before every commit
- Use `--fix` after reviewing diffs.
- Scope to target directories during development, then run full validation before merge.
- Require all checks to pass before merge.
