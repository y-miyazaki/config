---
name: loop-changelog
description: >-
  Update CHANGELOG.md from unreleased commits and undocumented releases detected
  by the loop (conventional, renovate, chore, pin/finalize subjects, and git tags).
  Use when loop automation finds new commits or releases since the last processed
  SHA — not for manual release tagging. Triggers via on-loop-changelog.yaml cron;
  never user-invoked.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.3.0"
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
- Promote detect `releases[]` into `## [x.y.z] - date` sections and move matching bullets out of `## [Unreleased]`
- Preserve existing released version sections and formatting

### DO NOT USE FOR:

- Create git tags or cut releases in CI outside the changelog file
- Edit loop state files (bundled by finalize after verification)
- Run detection or manage loop state

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-input-schema.md](references/category-input-schema.md) - Read when parsing context.

## Workflow

1. Parse [category-input-schema.md](references/category-input-schema.md). If `skip` or both `commits` and `releases` are empty, emit report with Summary `No unreleased changelog commits`; stop.
2. When `changelog_exists` is false, create `changelog_file` with the Keep a Changelog header (`# Changelog`, format note, `## [Unreleased]`).
3. Map each commit `type` to changelog subsections per [common-checklist.md](references/common-checklist.md). Use the commit `subject` (and scope when helpful) as the bullet text. When `repository_url` is present, append a parenthesized markdown commit link per [common-checklist.md](references/common-checklist.md#bullet-links).
4. For each `releases[]` entry without an existing `## [version]` section, add `## [version] - date` below `## [Unreleased]` and move bullets whose commit `sha` is listed in `commit_shas` from `## [Unreleased]` into the release section using the same subsection names. Add footer compare links per [common-checklist.md](references/common-checklist.md#release-sections).
5. At `L2`/`L3`, edit only `changelog_file`. Do not duplicate entries already listed under `## [Unreleased]` or released sections. When `compare_url` is present and `## [Unreleased]` has no compare link yet, add a single line immediately under `## [Unreleased]`: `[Full diff]({compare_url})`.
6. Output per [common-output-format.md](references/common-output-format.md).
