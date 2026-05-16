---
name: instructions-review
description: >-
  Review `.instructions.md` files for structure, consistency, and usability.
  Use when reviewing instruction PRs or audits.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- Target `.github/instructions/*.instructions.md` files (required)
- PR context (optional)

## Output Specification

Return structured review output with `## Checks Summary`, `## Checks (Failed/Deferred Only)`, and `## Issues` using fixed ItemIDs.

See [references/common-output-format.md](references/common-output-format.md) for detailed format specification.

## Execution Scope

- Systematically apply review checklist from [references/common-checklist.md](references/common-checklist.md)
- Focus on quality, structure, consistency, and practical usability requiring human/AI judgment
- **Do not execute validation commands from this review skill**
- Do not modify instructions files or approve/merge PRs
- Required chapter order: Standards → Guidelines → Testing and Validation → Security Guidelines

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [troubleshooting](references/common-troubleshooting.md)
- [global](references/category-global.md), [testing](references/category-testing.md), [security](references/category-security.md)
- [quality](references/category-quality.md), [guidelines](references/category-guidelines.md), [standards](references/category-standards.md)

## Workflow

1. Read PR context and identify target instruction files.
2. Confirm deterministic checks are available; if missing/failing, request rerun.
3. Verify required chapter order, then review checklist priorities and collect failed/deferred ItemIDs.
4. Output required report sections per [references/common-output-format.md](references/common-output-format.md).

## Best Practices

- Prioritize consistency with existing instruction conventions.
- Keep recommendations practical and executable.
