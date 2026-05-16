---
name: go-review
description: >-
  Review Go code for security, correctness, performance, and maintainability.
  Use when reviewing Go PRs requiring judgment beyond automated checks.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- Go files in PR (required)
- PR context (required)

## Output Specification

Return structured review output with `## Checks Summary`, `## Checks (Failed/Deferred Only)`, and `## Issues` using fixed ItemIDs.

See [references/common-output-format.md](references/common-output-format.md) for detailed format specification.

## Execution Scope

- Systematically apply review checklist from [references/common-checklist.md](references/common-checklist.md)
- Focus on checks requiring human/AI judgment (design, concurrency, security patterns)
- **Do not run go-validation or execute gofumpt/go vet/golangci-lint/go test/govulncheck**
- Do not modify code files or approve/merge PRs

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [global](references/category-global.md), [concurrency](references/category-concurrency.md), [errors](references/category-error-handling.md), [security](references/category-security.md)
- [arch](references/category-architecture.md), [standards](references/category-code-standards.md), [context](references/category-context.md), [deps](references/category-dependencies.md)
- [docs](references/category-documentation.md), [func](references/category-function-design.md), [perf](references/category-performance.md), [testing](references/category-testing.md)

## Workflow

1. Read PR context and change intent.
2. Confirm `go-validation` results exist; if missing/failing, request rerun.
3. Review relevant checklist categories and collect failed/deferred ItemIDs.
4. Output required report sections per [references/common-output-format.md](references/common-output-format.md).

## Best Practices

- Keep findings specific and actionable.
- Prioritize `SEC-*` findings first.
