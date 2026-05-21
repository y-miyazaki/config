## Go Template Variants

Language-specific template variants. Use when the Go profile is detected.

Use these variants when Go profile is detected and Terraform profile is not detected.

## Coverage Matrix (Go Profile)

Use the template source below for each `document_type`:

| `document_type`     | Template Source                                          |
| ------------------- | -------------------------------------------------------- |
| `specification`     | `specification_go` in this file                          |
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

## specification_go

```markdown
# Go Specification

This document defines behavior, package contracts, and runtime guarantees for Go components.

## Scope

<Describe covered packages, binaries, and environments.>

## Package Contracts

### `<package/path>`

**Responsibilities**:

- <responsibility 1>
- <responsibility 2>

**Public API**:

| Symbol   | Input    | Output     | Errors               |
| -------- | -------- | ---------- | -------------------- |
| `<Func>` | `<args>` | `<result>` | `<error conditions>` |

## Concurrency and State

<Describe goroutine model, synchronization rules, and state ownership boundaries. Omit if not applicable.>

## Configuration and Defaults

| Parameter | Default   | Source            | Notes   |
| --------- | --------- | ----------------- | ------- |
| `<name>`  | `<value>` | `<env/flag/file>` | <notes> |

## Validation and Safety Checks

- `go test ./...`
- `golangci-lint run`
- `go vet ./...` (optional when `govet` is enabled in `golangci-lint`)
- `<project specific checks>`

## Compatibility and Change Management

<Define compatibility policy, rollout approach, and rollback notes.>
```
