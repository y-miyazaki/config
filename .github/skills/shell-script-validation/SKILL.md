---
name: shell-script-validation
description: >-
  Validate shell scripts with bash -n and shellcheck for syntax safety and maintainability checks.
  Use when committing script changes, running CI validation, or debugging shellcheck findings in PRs.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- Shell script path or directory (required)
- Validation script: `shell-script-validation/scripts/validate.sh` (required)
- Optional flags: `-v`, `-f`

## Output Specification

Structured results for bash -n, shellcheck, and project standards.

See [references/common-output-format.md](references/common-output-format.md) for detailed format specification.

## Execution Scope

- **Always use `scripts/validate.sh`** for comprehensive validation. Do not run individual commands.
- Script runs checks in fixed order.
- Individual commands are for debugging only (see [references/common-individual-commands.md](references/common-individual-commands.md)).
- **Do not review code design decisions** (use shell-script-review for that)

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [common-troubleshooting.md](references/common-troubleshooting.md) - Read when checks fail unexpectedly.
- [common-individual-commands.md](references/common-individual-commands.md) - Read when debugging bash -n or shellcheck.
- [category-standards.md](references/category-standards.md) - Read when standards/template violations are reported.

## Workflow

1. Run `bash shell-script-validation/scripts/validate.sh`.
2. If a failure appears, run with target path and/or `-v`.
3. If formatting fixes are suggested, rerun with `-f`.
4. Re-run until all checks pass.

### Examples

```bash
bash shell-script-validation/scripts/validate.sh
bash shell-script-validation/scripts/validate.sh ./scripts/deploy.sh -v
bash shell-script-validation/scripts/validate.sh -f
```

## Best Practices

- Run validation before every commit
- Use `-f` only after reviewing proposed changes.
- Run bats tests separately when needed.
- Require all checks to pass before merge.
