---
name: diagram-as-code-validation
description: >-
  Validate AWS Diagram as Code (DAC) YAML with yamllint and awsdac, and generate PNG diagrams.
  Use when editing DAC YAML, generating architecture diagrams, or validating structure before commit.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- DAC YAML file(s) (required)
- Optional: output PNG filename, `.yamllint`, environment identifier
- Prerequisites: `yamllint` and `awsdac` available on PATH

## Output Specification

Structured validation results with `## Checks Summary`, `## Checks (Failed/Deferred Only)`, and `## Issues`.
Validation sequence is fixed: yamllint → awsdac → PNG/file verification.

## Execution Scope

- **Always use `scripts/validate.sh`** for comprehensive validation. Do not run individual commands.
- Script executes yamllint and awsdac in order.
- **Do not modify YAML files automatically**
- Generate PNG diagrams only.

### USE FOR:

- validate `aws_architecture_diagram*.yaml` or `aws_architecture_diagram*.yml`
- debug DAC validation failures before commit
- regenerate PNG after successful DAC validation

### DO NOT USE FOR:

- validate non-DAC generic YAML files
- redesign architecture content or rewrite YAML semantics
- review Terraform or CloudFormation code quality

## Reference Files Guide

**Standard Components** (always read):

- [common-checklist.md](references/common-checklist.md) - Validation checklist with ItemIDs
- [common-output-format.md](references/common-output-format.md) - Report format specification
- [common-troubleshooting.md](references/common-troubleshooting.md) - Read when validation fails unexpectedly
- [common-individual-commands.md](references/common-individual-commands.md) - Read when debugging yamllint or awsdac

## Workflow

```bash
# Full validation of all DAC files
bash diagram-as-code-validation/scripts/validate.sh

# Validate specific YAML file
bash diagram-as-code-validation/scripts/validate.sh ./aws_architecture_diagram.yaml

# Validate specific directory
bash diagram-as-code-validation/scripts/validate.sh ./diagrams/
```

1. If `yamllint` or `awsdac` is missing on PATH, return `status: failed` with missing binary name.
2. If input file name does not match `aws_architecture_diagram*.yaml` or `aws_architecture_diagram*.yml`, return `status: skipped`.
3. If `yamllint` fails, stop and report lint findings.
4. If `yamllint` passes and `awsdac` fails, report `awsdac` findings.
5. If PNG verification fails, set status to deferred for PNG checks with reason `output PNG missing or empty`.
6. If all checks pass, return `## Checks Summary` with `Passed` only and include generated PNG path(s).
7. If script execution fails unexpectedly, follow [common-troubleshooting.md](references/common-troubleshooting.md) and report command, exit status, and summary.

### Examples

- Prompt: `Validate DAC YAML and generate PNG diagram. Report only failures.`
- Input: `bash diagram-as-code-validation/scripts/validate.sh ./aws_architecture_diagram.yaml`
- Output: Report passed/failed/deferred checks with ItemIDs and generated PNG path.

## Best Practices

- Run validation before every DAC commit
- Confirm all generated PNG files exist and are non-empty.
