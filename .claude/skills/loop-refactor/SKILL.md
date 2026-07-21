---
name: loop-refactor
description: >-
  Apply behavior-preserving O1/O2 refactors from loop-injected H1 hints. Use when
  loop automation detects duplication_block or oversized_unit — not for interactive
  architecture improvement (use refactor skill). Triggers via on-loop-refactor.yaml;
  never user-invoked.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

Injected JSON from loop-prompt-generate — see [category-input-schema.md](references/category-input-schema.md). Path allowlist and denylist arrive in the prompt `## Constraints` section (caller `LOOP_ALLOWLIST`, `LOOP_DENYLIST`).

## Operating levels

`level` arrives in injected JSON — see [category-input-schema.md](references/category-input-schema.md#operating-levels).

## Output Specification

Session report per [common-output-format.md](references/common-output-format.md).
At `L2`/`L3`, apply one structural refactor for the first actionable hint within [category-scope.md](references/category-scope.md).

## Execution Scope

### USE FOR:

- Map one H1 hint to one O1/O2 structural refactor (dedupe, clarify, shallow same-package move)
- Follow `refactor` skill structural path via caller `## Instructions` (A')
- Produce session report with PR Overview/Summary sections

### DO NOT USE FOR:

- Architecture-improvement intent or O3 proposal/apply
- Lint/style-only cleanup as the primary mission
- Cross-package redesign, GoF patterns, or public API changes
- Feature work, behavior-changing fixes, dependency upgrades
- Run detection or manage loop state

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-input-schema.md](references/category-input-schema.md) - Read when parsing context.
- Project `AGENTS.md` or steering files (always read)

## Workflow

1. Parse [category-input-schema.md](references/category-input-schema.md). Read prompt `## Constraints` for the active allowlist. If `skip` or no actionable `hints`, emit report with Session Metrics Outcome `no-op`; stop.
2. Select **one** hint — first actionable entry in `hints[]`. Map to `refactor` input (`hint.kind`, `hint.path`, `hint.detail`). Force `intent: structural`; `constraints.max_tier: O2`.
3. Follow structural `refactor` workflow: verify foundation → minimal O1/O2 edit → stack validation per caller `## Instructions`.
4. At `L2`/`L3`, edit only paths allowed by `## Constraints` and [category-scope.md](references/category-scope.md).
5. Output session report per [common-output-format.md](references/common-output-format.md); at synthesis time load `assets/pr-body-template.md` and emit `## Overview` + `## Summary` for PR composition.
