## Terraform Template Variants

Language-specific template variants. Use when the Terraform profile is detected.

Use these variants when Terraform profile is detected.

## Coverage Matrix (Terraform Profile)

Use the template source below for each `document_type`:

| Document Type | Template Source |
| --- | --- |
| `specification` | `specification_terraform` in this file |
| `architecture` | `references/category-templates.md` (`architecture`) |
| `design` | `references/category-templates.md` (`design`) |
| `design_decisions` | `references/category-templates.md` (`design_decisions`) |
| `troubleshooting` | `references/category-templates.md` (`troubleshooting`) |
| `general` | `references/category-templates.md` (`general`) |
| `module_catalog` | `references/category-templates.md` (`module_catalog`) |
| `monitoring` | `references/category-templates.md` (`monitoring`) |
| `performance` | `references/category-templates.md` (`performance`) |
| `security_coverage` | `references/category-templates.md` (`security_coverage`) |
| `maintenance_notes` | `references/category-templates.md` (`maintenance_notes`) |
| `improvements` | `references/category-templates.md` (`improvements`) |

## specification_terraform

```markdown
# Terraform Specification

This document defines the repository behavior, module contracts, and environment-specific
configuration for Terraform-managed resources.

## Scope

<Describe covered stacks, environments, and exclusions.>

## Module Contracts

### `modules/<path>`

**Inputs**:

| Variable | Type     | Required | Default   | Description   |
| -------- | -------- | -------- | --------- | ------------- |
| `<var>`  | `<type>` | Yes/No   | `<value>` | <description> |

**Outputs**:

| Output     | Description   |
| ---------- | ------------- |
| `<output>` | <description> |

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
