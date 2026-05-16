---
name: agent-skills-review
description: >-
  Review SKILL.md quality for Waza readiness and project compliance in final release checks.
  Use when creating skills, reviewing skill PRs, or fixing waza check findings.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- Target: `.github/skills/*/SKILL.md`
- Evidence: `scripts/validate_waza.sh` and `scripts/validate.sh` outputs

## Output Specification

- Return structured Markdown per [references/common-output-format.md](references/common-output-format.md).

## Execution Scope

- Review structure and quality.
- Run `scripts/validate_waza.sh` and `scripts/validate.sh`.
- Enforce `waza check` Token Budget <= 500.
- Do not merge PRs or edit unrelated files.

### USE FOR:

- review new SKILL drafts
- fix token-limit failures
- fix compliance issues

### DO NOT USE FOR:

- implement product features
- debug runtime issues

### ROUTING:

**UTILITY SKILL**

INVOKES: `scripts/validate_waza.sh` and `scripts/validate.sh`.
FOR SINGLE OPERATIONS: for one wording fix, edit `SKILL.md`.

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-structure.md](references/category-structure.md) - Read for structure.
- [category-quality.md](references/category-quality.md) - Read for quality.
- [category-patterns.md](references/category-patterns.md) - Read for workflow.

## Workflow

1. Run `bash scripts/validate_waza.sh <skill-name>` and `bash scripts/validate.sh <SKILL.md>`.
2. Check hard gate first: Token Budget <= 500.
3. Apply checks in order: `S-*`, `Q-*`, `P-*`, `BP-*`.
4. Report failed/deferred items with ItemIDs.

### Examples

- Prompt: `Review SKILL.md and report only failed/deferred items`.

## Error Handling and Troubleshooting

- If script output is missing/failed, rerun both scripts and defer affected checks.

## Best Practices

- Fix CRITICAL items first and prioritize Waza errors.
