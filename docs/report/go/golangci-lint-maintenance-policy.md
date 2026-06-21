<!-- omit in toc -->
# Golangci-lint Maintenance Workflow

This document defines a future-facing workflow for maintaining `.golangci.yaml`.
It is a policy for how to update, review, and validate linter configuration, not a changelog of past edits.

<!-- omit in toc -->
## Table Of Contents
- [Scope](#scope)
- [Principles](#principles)
- [Workflow](#workflow)
  - [Stage 1: Discover](#stage-1-discover)
  - [Stage 2: Edit](#stage-2-edit)
  - [Stage 3: Clean Up](#stage-3-clean-up)
- [Decision Rules](#decision-rules)
- [Verification Gate](#verification-gate)
- [Operational Notes](#operational-notes)

## Scope
- Target file: `.golangci.yaml`
- Authoritative references:
  - https://golangci-lint.run/docs/configuration/file/
  - https://golangci-lint.run/docs/linters/configuration/

## Principles
- Keep changes minimal and reviewable.
- Apply explicit markers only to changed lines:
  - `(Deprecated)`
- Keep `linters.settings` entries in A-Z order under the root.
- Do not keep stale configuration:
  - If a linter is not present in current official docs, remove it from both `linters.enable` and `linters.settings`.

## Workflow
1. Discover current linter set.
2. Classify each target linter as one of: `enable`, `comment out`, `remove`, `deprecated`.
3. Apply `linters.enable` updates with markers on changed lines only.
4. Apply `linters.settings` updates in A-Z order.
5. Remove unsupported linters line-by-line from both sections.
6. Run verification gates before finalizing.

### Stage 1: Discover
- Pull the local authoritative list from the installed binary.
- Confirm deprecated status from the same source.

### Stage 2: Edit
- Update `linters.enable` first, then `linters.settings`.
- For linters with no configurable settings in official docs:
  - Do not add schema-breaking YAML keys.
  - Add a commented placeholder in `linters.settings` if traceability is needed.

### Stage 3: Clean Up
- Remove unknown or obsolete linters from:
  - `linters.enable`
  - `linters.settings`
- Mark deprecated linters in `linters.enable` with `(Deprecated)`.

## Decision Rules
- Enable a linter only when it provides clear net value and acceptable noise.
- Keep candidates commented out when impact is uncertain.
- Prefer maintained replacements for deprecated linters.
- Avoid introducing rule sets that require broad immediate refactors unless explicitly planned.

## Verification Gate
Run all commands below after each maintenance change.

```bash
golangci-lint help linters --json > tmp/golangci-linters.json
golangci-lint config verify --config .golangci.yaml
git diff --check -- .golangci.yaml
```

Optional inspection:

```bash
jq -r '.[].name' tmp/golangci-linters.json | sort
```

Completion criteria:
- `golangci-lint config verify` passes.
- No `git diff --check` errors.
- Markers are applied only to changed lines.
- `linters.settings` ordering is preserved.

## Operational Notes
- Re-run this workflow whenever golangci-lint version changes.
- Treat this file as policy; project-specific enable/disable decisions belong in PR descriptions or issue discussions.
- Reviewer/instructions boundary rule is defined in [linter-review-boundary.md](../governance/linter-review-boundary.md).
