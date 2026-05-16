---
name: go-validation
description: >-
  Validate Go formatting, linting, tests, and vulnerabilities for maintainable and secure code delivery.
  Use when committing Go changes, running CI validation, or debugging failing checks in repositories.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- Go path or directory (required)
- Validation script: `go-validation/scripts/validate.sh` (required)
- Optional flags: `--fix`, `--verbose`

## Output Specification

Structured validation results in fixed tool order.

See [references/common-output-format.md](references/common-output-format.md) for detailed format specification.

## Execution Scope

- **Always use `scripts/validate.sh`** for comprehensive validation. Do not run individual commands.
- Individual commands are for debugging only (see [references/common-individual-commands.md](references/common-individual-commands.md)).
- **Do not review code design decisions** (use go-review).
- **Do not modify source files** except `--fix` formatting.
- **Do not create or delete files**.
- Test coverage threshold: 80%

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [common-troubleshooting.md](references/common-troubleshooting.md) - Read when checks fail unexpectedly.
- [common-individual-commands.md](references/common-individual-commands.md) - Read when debugging one tool directly.
- [category-security.md](references/category-security.md) - Read when govulncheck reports vulnerabilities.
- [category-testing.md](references/category-testing.md) - Read when tests fail or coverage drops.

## Workflow

1. Run `bash go-validation/scripts/validate.sh`.
2. Use target path for fast iteration.
3. Use `--fix` for formatting and `--verbose` for diagnostics.
4. Re-run until all checks pass.

### Examples

- Prompt: `Validate Go checks and report summary, tool results, and error details.`

## Best Practices

- Use `--fix` after reviewing diffs.
- Run full validation before merge.
- Require all checks to pass before merge.
