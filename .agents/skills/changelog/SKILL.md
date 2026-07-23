---
name: changelog
description: >-
  Update CHANGELOG.md from unreleased commits and undocumented releases (conventional,
  renovate, chore, pin/finalize subjects, and git tags). Use when loop automation
  or an explicit request supplies commit/release detect JSON. Preferred via
  on-loop-changelog.yaml.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.4.0"
---

## Input

Injected JSON from loop-prompt-generate — see [category-input-schema.md](references/category-input-schema.md). Path allowlist arrives in the prompt `## Constraints` section (caller `LOOP_ALLOWLIST`).

## Operating levels

`level` arrives in injected JSON — see [category-input-schema.md](references/category-input-schema.md#operating-levels).

## Output Specification

Changelog report per [common-output-format.md](references/common-output-format.md). Survey at `L1`; apply at `L2`/`L3` within [category-scope.md](references/category-scope.md).

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
- [category-input-schema.md](references/category-input-schema.md) (always read)
- [common-loop-triage-format.md](references/common-loop-triage-format.md) (always read)
- [common-loop-pr-body-contract.md](references/common-loop-pr-body-contract.md) (always read)
- `assets/pr-body-template-survey.md` (always read — loop L1 survey path)
- `assets/pr-body-template.md` (always read — loop L2/L3 apply path)

## Workflow

1. Parse [category-input-schema.md](references/category-input-schema.md). If `skip` or both `commits` and `releases` are empty, emit survey no-op; stop.
2. Map commits and promote releases per [common-checklist.md](references/common-checklist.md).
3. At `L1`, emit survey shape with Candidates; load `assets/pr-body-template-survey.md` at synthesis; stop — do not edit `changelog_file`.
4. At `L2`/`L3`, edit only `changelog_file` per [category-scope.md](references/category-scope.md); emit apply shape; load `assets/pr-body-template.md` at synthesis.

### Error Handling

| Condition                        | Severity    | Action                                  |
| -------------------------------- | ----------- | --------------------------------------- |
| `skip` or empty commits/releases | Info        | Report skip outcome; stop               |
| `changelog_file` outside scope   | Recoverable | Defer; note in report                   |
| Edit requested at `L1`           | Info        | Report only; do not edit `CHANGELOG.md` |
