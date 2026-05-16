---
name: shell-script-review
description: >-
  Review shell scripts for security, correctness, and maintainability with emphasis on operational safety.
  Use when reviewing shell script PRs requiring judgment beyond static checks.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- Shell script files in PR (required)
- PR context (required)

## Output Specification

Return structured review output with `## Checks Summary`, `## Checks (Failed/Deferred Only)`, and `## Issues` using fixed ItemIDs.

See [references/common-output-format.md](references/common-output-format.md) for detailed format specification.

## Execution Scope

- Systematically apply review checklist from [references/common-checklist.md](references/common-checklist.md)
- Focus on checks requiring human/AI judgment (design, security, error handling patterns)
- **Do not run shell-script-validation or execute bash -n/shellcheck**
- Do not modify script files or approve/merge PRs

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [global](references/category-global.md), [errors](references/category-error-handling.md), [security](references/category-security.md)
- [standards](references/category-code-standards.md), [deps](references/category-dependencies.md), [docs](references/category-documentation.md)
- [func](references/category-function-design.md), [logging](references/category-logging.md), [perf](references/category-performance.md), [testing](references/category-testing.md)

## Workflow

1. Read PR context and script intent.
2. Confirm `shell-script-validation` results exist; if missing/failing, request rerun.
3. Review relevant checklist categories and collect failed/deferred ItemIDs.
4. Output required report sections per [references/common-output-format.md](references/common-output-format.md).

## Best Practices

- Keep findings specific and actionable.
- Prioritize `SEC-*` findings first.
