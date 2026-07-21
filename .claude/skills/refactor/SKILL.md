---
name: refactor
description: >-
  Behavior-preserving structural refactors with stack gates. Use when removing
  duplication, consolidating copy-paste, extracting helpers, clarifying
  verbose-equivalent code, or making shallow same-package moves. Do not use for
  lint/shellcheck/gofmt-only style, features, behavior-changing bugfixes,
  upgrades, or architecture/GoF redesign.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.4"
---

## Input

Paths/symbols — [category-input-schema.md](references/category-input-schema.md).
Stack: `## Instructions` (A') + `*-validation` skills.

## Output Specification

Session report per [common-output-format.md](references/common-output-format.md).

## Execution Scope

- One target ([category-scope.md](references/category-scope.md)). Allowed depth: [category-operations.md](references/category-operations.md). Gates: [category-verification.md](references/category-verification.md).

### USE FOR:

- Deduplicate, extract/inline, clarify, shallow same-package moves
- Characterization tests when supported; validation skills in Instructions

### DO NOT USE FOR:

- Lint/style-only; features/API/behavior fixes/upgrades; deep redesign/GoF; detect/loop; tech-debt report input

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-operations.md](references/category-operations.md) (always read before edits — plain-language depth tiers)
- [category-verification.md](references/category-verification.md) - Read before apply and after edits.
- [category-input-schema.md](references/category-input-schema.md) - Read when parsing input.

## Workflow

1. Parse input schema. Nothing actionable → Outcome `no-op`; stop.
2. Load checklist, operations, verification, scope.
3. One target. Lint/style-primary or feature/API → Watch.
4. Verify (add characterization when required).
5. Minimal allowed-depth edit; if same-package move lacks a gate → local-only or Watch.
6. Stack validation; one repair or revert Watch.
7. Emit session report (Tier fields use plain-language depth labels).
