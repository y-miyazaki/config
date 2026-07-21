---
name: refactor
description: >-
  Behavior-preserving structural refactors with stack gates. Use when removing
  duplication, extracting helpers, clarifying verbose-equivalent code, or shallow
  same-package moves — interactively or from loop hints (duplication_block,
  oversized_unit). Architecture: proposal first, one approved slice per run. Not
  for lint-only style, features, behavior-changing bugfixes, or upgrades.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "2.2.1"
---

## Input

- **Interactive:** paths/symbols — constraints in `## Constraints` or [category-scope.md](references/category-scope.md)
- **Loop:** JSON with `hints[]` — [category-input-schema.md](references/category-input-schema.md)

## Operating levels

`level` arrives in loop JSON — see [category-input-schema.md#operating-levels](references/category-input-schema.md#operating-levels).

## Output Specification

Interactive: [common-output-format.md](references/common-output-format.md). Loop: [common-output-format-loop.md](references/common-output-format-loop.md).

## Execution Scope

### USE FOR:

- Dedupe, extract/inline, clarify, shallow moves; loop hints; architecture Phase A/B; characterization tests

### DO NOT USE FOR:

- Lint/style-only; features/API/behavior fixes; cross-boundary apply; loop architecture; tech-debt input

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-operations.md](references/category-operations.md) (always read)
- [category-techniques.md](references/category-techniques.md) (always read)
- [category-verification.md](references/category-verification.md) (always read)
- [category-input-schema.md](references/category-input-schema.md) (always read — loop path)
- [common-output-format-loop.md](references/common-output-format-loop.md) (always read — loop path)

## Workflow

### Loop path (`hints[]` in loop JSON)

1. Parse [category-input-schema.md](references/category-input-schema.md); read constraints.
2. If empty/`skip` → no-op report; stop.
3. Take first hint; structural only; at L1 report-only.
4. One target; gate per [category-verification.md](references/category-verification.md); one technique per [category-techniques.md](references/category-techniques.md); minimal edit or Watch.
5. Emit loop report per [common-output-format-loop.md](references/common-output-format-loop.md).

### Interactive path

1. Parse input; read constraints.
2. Classify intent per [category-operations.md](references/category-operations.md); architecture without slice → Phase A proposal; stop.
3. One target; lint-primary or feature/API → Watch.
4. Gate; one technique per [category-techniques.md](references/category-techniques.md).
5. Minimal local or same-package edit; downgrade if weak gate; validate once or revert Watch.
6. Emit report per [common-output-format.md](references/common-output-format.md).

### Error Handling

| Condition                              | Severity    | Action                                      |
| -------------------------------------- | ----------- | ------------------------------------------- |
| Loop: empty/`skip`                     | Info        | No-op report; stop                          |
| Architecture request without slice     | Recoverable | Phase A proposal only; stop                 |
| Lint-primary or feature/API change       | Recoverable | Classify Watch; no edit                     |
| Weak or failed verification gate       | Recoverable | Downgrade to Watch or revert; report        |
| Cross-boundary or out-of-scope target  | Recoverable | Watch; recommend approved slice             |
