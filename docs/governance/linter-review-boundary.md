<!-- omit in toc -->
# Linter and Review Boundary Policy

<!-- omit in toc -->
## Table Of Contents
- [Purpose](#purpose)
- [Scope](#scope)
- [Core Rule](#core-rule)
- [Decision Criteria](#decision-criteria)
- [Workflow for Instructions and Skills Updates](#workflow-for-instructions-and-skills-updates)
- [Examples](#examples)
- [Verification](#verification)

## Purpose
This document defines the boundary policy for instructions and skills maintenance.
It prevents duplicated review guidance when lint configuration already covers machine-detectable issues.

## Scope
- Applies to:
  - instructions
  - skills
  - review checklists and references used by instructions/skills
- Does not define generic review/output standards.

## Core Rule
Do not add review guidance that only repeats what enabled linters already detect and enforce.

Keep review guidance for concerns that require human judgment, such as:
- architecture and design intent
- trade-off evaluation and risk
- ownership boundaries and responsibilities
- domain correctness and operational impact

## Decision Criteria
When adding or editing a review item, classify it before documenting it.

1. Linter-covered (machine-detectable)
- If fully detectable by configured linters with acceptable signal quality, do not add it as a review rule.

2. Judgment-required (human evaluation)
- If context, intent, or trade-off assessment is needed, keep it as a review rule.

3. Mixed
- If a linter detects only part of the issue, keep only the judgment-required portion in review guidance.

## Workflow for Instructions and Skills Updates
1. Identify candidate guidance to add or modify.
2. Check whether current lint configuration already covers it.
3. If covered by linter, remove the direct mechanical rule from review guidance.
4. Keep and document only the judgment-required aspect.
5. Verify wording does not prescribe purely mechanical replacements.

## Examples
- Prefer: "Are synchronization boundaries and ownership rules explicit?"
- Avoid: "Replace X with Y" when configured linters already provide that mechanical suggestion.

- Prefer: "Is context ownership explicit across boundaries?"
- Avoid: checklist items that only mirror linter-detected token-level patterns.

## Verification
For policy updates:

```bash
markdownlint-cli2 "docs/**/*.md"
```

For Go lint boundary checks:

```bash
golangci-lint help linters --json > tmp/golangci-linters.json
golangci-lint config verify --config .golangci.yaml
```
