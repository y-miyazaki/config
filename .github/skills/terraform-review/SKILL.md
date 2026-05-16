---
name: terraform-review
description: >-
  Review Terraform quality, security, and architecture decisions.
  Use when reviewing Terraform PRs requiring judgment beyond automated checks across modules and environments.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- Terraform files and PR context (required)

## Output Specification

Return review output with `## Checks Summary`, `## Checks (Failed/Deferred Only)`, and `## Issues`.

## Execution Scope

- Apply review checklist from [references/common-checklist.md](references/common-checklist.md)
- **Do not run terraform-validation or execute terraform fmt/validate/tflint/trivy**
- Do not modify Terraform files or approve/merge PRs

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [global](references/category-global.md), [security](references/category-security.md), [modules](references/category-modules.md), [state](references/category-state.md)
- [ci](references/category-ci-lint.md), [compliance](references/category-compliance.md), [cost](references/category-cost.md), [data](references/category-data-sources.md)
- [dependency](references/category-dependency.md), [events](references/category-events.md), [migration](references/category-migration.md), [naming](references/category-naming.md)
- [outputs](references/category-outputs.md), [patterns](references/category-patterns.md), [perf](references/category-performance.md), [tagging](references/category-tagging.md)
- [tfvars](references/category-tfvars.md), [variables](references/category-variables.md), [versioning](references/category-versioning.md)

## Workflow

1. Read PR context and module scope.
2. Confirm `terraform-validation` results; if missing/failing, request rerun.
3. Review relevant checklist categories and collect failed/deferred items.
4. Output required sections per [references/common-output-format.md](references/common-output-format.md).

## Examples

- Prompt: `Review Terraform PR and report only failed/deferred checks.`

## Error Handling and Troubleshooting

- If validation evidence is missing/partial, request rerun and mark affected checks as deferred.

## Best Practices

- Prioritize `SEC-*` findings first.
