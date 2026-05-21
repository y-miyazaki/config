## Terraform Template Variants

Language-specific template variants. Use when the Terraform profile is detected.

Use these variants when Terraform profile is detected.

## Coverage Matrix (Terraform Profile)

Use the template source below for each `document_type`:

| `document_type`     | Template Source                                          |
| ------------------- | -------------------------------------------------------- |
| `specification`     | `specification_terraform` in this file                   |
| `architecture`      | `references/category-templates.md` (`architecture`)      |
| `design`            | `references/category-templates.md` (`design`)            |
| `design-decisions`  | `references/category-templates.md` (`design-decisions`)  |
| `troubleshooting`   | `references/category-templates.md` (`troubleshooting`)   |
| `general`           | `references/category-templates.md` (`general`)           |
| `module-catalog`    | `references/category-templates.md` (`module-catalog`)    |
| `monitoring`        | `references/category-templates.md` (`monitoring`)        |
| `performance`       | `references/category-templates.md` (`performance`)       |
| `security-coverage` | `references/category-templates.md` (`security-coverage`) |
| `maintenance-notes` | `references/category-templates.md` (`maintenance-notes`) |
| `improvements`      | `references/category-templates.md` (`improvements`)      |

## specification_terraform

```markdown
# Terraform Specification

This document defines the repository behavior and environment-specific configuration
for Terraform-managed resources. Module input/output documentation is maintained
separately by terraform-docs.

## Scope

| Item           | Detail                                |
| -------------- | ------------------------------------- |
| Stacks         | <comma-separated list of stack paths> |
| Environments   | <e.g., dev, staging, production>      |
| Cloud Provider | <e.g., AWS, GCP>                      |
| Exclusions     | <what is explicitly out of scope>     |

Out-of-scope items:

- Module input/output variable documentation (maintained by terraform-docs)
- <other exclusions>

## Resource Specifications

| Resource Type | Name Pattern | Required Tags | Notes   |
| ------------- | ------------ | ------------- | ------- |
| `<aws_*>`     | `<pattern>`  | `<tags>`      | <notes> |

## Validation and Safety Checks

- `terraform fmt -check`
- `terraform validate`
- `tflint --init`
- `tflint --recursive`
- `<project specific checks>`

## Change Management

<Define plan/apply workflow, approval requirements, and rollback notes.>
```
