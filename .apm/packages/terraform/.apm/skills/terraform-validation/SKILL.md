---
name: terraform-validation
description: >-
  Validate Terraform syntax, linting, and security with terraform fmt/validate, tflint, and trivy.
  Use when committing Terraform changes, running CI validation, or checking IaC security issues.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.1"
---

## Input

- Terraform path or directory (required)
- Validation script (required): `scripts/validate.sh` (run from the terraform-validation skill directory)
- `--fix` (optional): rewrites formatting with `terraform fmt` (and argument order with `--check-order`)
- `--verbose` (optional)
- `--check-order` (optional): run the argument order check (ORD-01); requires `python3`

## Output Specification

Return structured Markdown in accordance with [references/common-output-format.md](references/common-output-format.md). That file is the source of truth for the output contract.

Structured results in the script's order: tflint, terraform validate, terraform fmt, argument order (with `--check-order`), trivy config.

## Execution Scope

- **Always use `scripts/validate.sh`** for comprehensive validation. Do not run individual commands.
- Script runs all checks in deterministic order and continues after a failing tool (no fail-fast).
- Individual commands are for debugging only (see [references/common-individual-commands.md](references/common-individual-commands.md)).

### USE FOR:

- run Terraform syntax/lint/security checks before commit
- reproduce CI validation failures locally
- validate a scoped Terraform directory during iterative changes

### DO NOT USE FOR:

- perform design and architecture review
- implement Terraform resource changes as a primary task
- validate non-Terraform files

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [common-troubleshooting.md](references/common-troubleshooting.md) (read on failure)
- [common-individual-commands.md](references/common-individual-commands.md) (read on failure)
- [category-security.md](references/category-security.md) (read on failure)

## Workflow

1. Run `bash scripts/validate.sh`.
2. For scoped runs, pass one or more target directories: `bash scripts/validate.sh <terraform-dir>`.
3. Use `--fix` for formatting corrections and `--verbose` for diagnostics.
4. Retry at most 2 times after fixes; if checks still fail, return blocking findings and stop.

### Error Handling

| Condition                                                                                | Severity    | Action                                                                               |
| ---------------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------ |
| `scripts/validate.sh` missing                                                            | Fatal       | Stop; report missing script                                                          |
| No `.tf` files under target path                                                         | Info        | Report no reviewable Terraform; stop                                                 |
| Required binary missing (`terraform`, `tflint`, `trivy`; `python3` with `--check-order`) | Fatal       | Stop; report the missing binary; set `Status: ❌ FAIL`                               |
| Single tool fails, others succeed                                                        | Recoverable | Report every tool; mark the failed tool ❌ Fail with exit status                     |
| All tools fail                                                                           | Fatal       | Set `Status: ❌ FAIL` with per-tool stderr summaries in `## Error Details`           |
| `common-checklist.md` unavailable                                                        | Fatal       | Stop; report missing dependency                                                      |
| `common-output-format.md` unavailable                                                    | Recoverable | Note missing file; emit `## Summary`, `## Tool Results`, and `## Error Details` only |

### Examples

- Prompt: `Validate Terraform fmt, validate, tflint, and trivy`
- Command: `bash scripts/validate.sh`
- Result: Structured report per [references/common-output-format.md](references/common-output-format.md). Additional invocations: [common-individual-commands.md](references/common-individual-commands.md) (read on debugging).
