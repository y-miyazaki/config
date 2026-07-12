---
name: loop-changelog
description: >-
  Update CHANGELOG.md from unreleased commits detected by the loop (conventional,
  renovate, chore, and other explicit "prefix: description" subjects). Use when
  loop automation finds new commits since the last processed SHA — not for manual
  release tagging. Triggers via on-loop-changelog.yaml cron; never user-invoked.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.2.0"
---

## Input

Injected JSON from loop-prompt-generate — see [category-input-schema.md](references/category-input-schema.md). Path allowlist arrives in the prompt `## Constraints` section (caller `LOOP_ALLOWLIST`).

## Output Specification

Changelog report per [common-output-format.md](references/common-output-format.md).
At `L2`/`L3`, edit `CHANGELOG.md` within [category-scope.md](references/category-scope.md).

## Execution Scope

### USE FOR:

- Create `CHANGELOG.md` from the Keep a Changelog template when `changelog_exists` is false
- Group detect `commits[]` into Keep a Changelog sections under `## [Unreleased]`
- Preserve existing released version sections and formatting

### DO NOT USE FOR:

- Bump version numbers or create git tags
- Edit non-changelog files
- Run detection or manage loop state

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-input-schema.md](references/category-input-schema.md) - Read when parsing context.

## Workflow

1. Parse [category-input-schema.md](references/category-input-schema.md). If `skip` or `commits` is empty, emit report with Summary `No unreleased changelog commits`; stop.
2. When `changelog_exists` is false, create `changelog_file` with the Keep a Changelog header (`# Changelog`, format note, `## [Unreleased]`).
3. Map each commit `type` to changelog subsections per [common-checklist.md](references/common-checklist.md). Use the commit `subject` (and scope when helpful) as the bullet text. When `repository_url` is present, append a parenthesized markdown commit link per [common-checklist.md](references/common-checklist.md#bullet-links).
4. At `L2`/`L3`, edit only `changelog_file`. Do not duplicate entries already listed under `## [Unreleased]`. When `compare_url` is present and `## [Unreleased]` has no compare link yet, add a single line immediately under `## [Unreleased]`: `[Full diff]({compare_url})`.
5. Output per [common-output-format.md](references/common-output-format.md).
