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
  version: "1.3.1"
---

## Input

Injected JSON from loop-prompt-generate — see [category-input-schema.md](references/category-input-schema.md). Path allowlist arrives in the prompt `## Constraints` section (caller `LOOP_ALLOWLIST`).

## Operating levels

`level` arrives in injected JSON — see [category-input-schema.md](references/category-input-schema.md#operating-levels).

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
2. Map commits and promote releases per [common-checklist.md](references/common-checklist.md).
3. At `L2`/`L3`, edit only `changelog_file` per [category-scope.md](references/category-scope.md).
4. Output per [common-output-format.md](references/common-output-format.md).
