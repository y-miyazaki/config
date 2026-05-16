---
name: github-actions-review
description: >-
  Review GitHub Actions workflows for correctness, security, and maintainability.
  Use when assessing trigger design, permissions, secret usage, and action integrations requiring judgment.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- Workflow YAML + PR context (required)

## Output Specification

Return review output with `## Checks Summary`, `## Checks (Failed/Deferred Only)`, and `## Issues`.

See [references/common-output-format.md](references/common-output-format.md) for detailed format specification.

## Execution Scope

- Systematically apply review checklist from [references/common-checklist.md](references/common-checklist.md)
- **Do not run github-actions-validation or execute actionlint/ghalint/zizmor**
- Do not modify workflow files or approve/merge PRs

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-global.md](references/category-global.md) - Read when reviewing triggers and permissions.
- [category-security.md](references/category-security.md) - Read when reviewing secrets and permission scoping.
- [category-best-practices.md](references/category-best-practices.md) - Read when reviewing maintainability.
- [category-error-handling.md](references/category-error-handling.md) - Read when reviewing failure handling behavior.
- [category-performance.md](references/category-performance.md) - Read when reviewing execution efficiency.
- [category-tool-integration.md](references/category-tool-integration.md) - Read when reviewing third-party action usage.

## Workflow

1. Read PR context and workflow intent.
2. Confirm `github-actions-validation` results; if missing/failing, request rerun.
3. Review relevant checklist categories and collect failed/deferred items.
4. Output report with the required sections per [references/common-output-format.md](references/common-output-format.md).

## Error Handling and Troubleshooting

- If prerequisite validation results are missing, request `github-actions-validation` output before review.
- If evidence is partial, mark affected checks as deferred with explicit reason.

## Examples

- Prompt: `Review workflow PR and report failed/deferred checks.`

## Best Practices

- Keep findings actionable and prioritize `SEC-*` first.
