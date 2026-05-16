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

## Output Specification

Structured validation results: yamllint → awsdac → file verification.

See [references/common-output-format.md](references/common-output-format.md) for detailed format specification.

## Execution Scope

- **Always use `scripts/validate.sh`** for comprehensive validation. Do not run individual commands.
- Script executes yamllint and awsdac in order.
- **Do not modify YAML files automatically**
- Generate PNG diagrams only.

## Reference Files Guide

**Standard Components** (always read):

- [common-checklist.md](references/common-checklist.md) - Validation checklist with ItemIDs
- [common-output-format.md](references/common-output-format.md) - Report format specification
- [common-troubleshooting.md](references/common-troubleshooting.md) - Read when validation fails unexpectedly
- [common-individual-commands.md](references/common-individual-commands.md) - Read when debugging yamllint or awsdac

## Workflow

**Always use the validation script. Do not run individual commands.**

```bash
# Full validation of all DAC files
bash diagram-as-code-validation/scripts/validate.sh

# Validate specific YAML file
bash diagram-as-code-validation/scripts/validate.sh ./aws_architecture_diagram.yaml

# Validate specific directory
bash diagram-as-code-validation/scripts/validate.sh ./diagrams/
```

### Examples

- Prompt: `Validate DAC YAML and generate PNG diagram. Report only failures.`

## Best Practices

- Run validation before every DAC commit
- Verify generated PNG visually after validation passes
- Ensure resource links and canvas hierarchy are valid
