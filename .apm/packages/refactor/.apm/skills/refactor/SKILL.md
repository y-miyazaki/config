---
name: refactor
description: >-
  Behavior-preserving structural refactors with stack gates. Use when removing
  duplication, consolidating copy-paste, extracting helpers, clarifying
  verbose-equivalent code, or making shallow same-package moves. For architecture
  improvement, module boundaries, or deep-module redesign: proposal and phased
  O2 slices only — not one-shot apply. Do not use for lint/shellcheck/gofmt-only
  style, features, behavior-changing bugfixes, or upgrades.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.5"
---

## Input

Paths/symbols — [category-input-schema.md](references/category-input-schema.md).
Stack: `## Instructions` (A') + `*-validation` skills.

## Output Specification

Session report per [common-output-format.md](references/common-output-format.md).

## Execution Scope

- One target ([category-scope.md](references/category-scope.md)). Allowed depth: [category-operations.md](references/category-operations.md). Gates: [category-verification.md](references/category-verification.md).

### USE FOR:

- Deduplicate, extract/inline, clarify, shallow same-package moves (structural intent)
- Architecture-improvement intent: Phase A proposal; Phase B one approved O2 slice per run
- Characterization tests when supported; validation skills in Instructions

### DO NOT USE FOR:

- Lint/style-only; features/API/behavior fixes/upgrades
- One-shot cross-boundary apply or GoF introduction
- O3 apply under loop L2; detect/loop envelope; tech-debt report input

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-operations.md](references/category-operations.md) (always read before edits — intent + depth tiers)
- [category-verification.md](references/category-verification.md) - Read before apply and after edits.
- [category-input-schema.md](references/category-input-schema.md) - Read when parsing input.

## Workflow

1. Parse input schema. Nothing actionable → Outcome `no-op`; stop.
2. Load checklist, operations, verification, scope.
3. Classify intent per [category-operations.md](references/category-operations.md): **structural** (default) or **architecture-improvement**. Record in session report.
4. One target. Lint/style-primary or feature/API → Watch.
5. **Architecture intent, no user-approved slice:** Phase A — emit deepening proposal (problem, candidates, phased plan, risks). Outcome `proposal`; stop.
6. **Structural intent, or architecture Phase B with one approved slice:** verify (add characterization when required).
7. Minimal O1/O2 edit; if same-package move lacks a gate → local-only or Watch.
8. Stack validation; one repair or revert Watch.
9. Emit session report (Tier fields use plain-language depth labels).
