# Changelog Loop Report Format

Follow survey/apply shapes in [common-loop-triage-format.md](common-loop-triage-format.md). Deferred subsection stays `### Skipped` for this skill.

## Survey-only result (loop `L1`)

No file edits.

```markdown
# Changelog Result

## Overview

<commit range → which conventional commits/releases would be recorded → no edits applied>

## Summary

### Candidates

| Target        | Type   | Evidence  | Suggested approach  | Priority              |
| ------------- | ------ | --------- | ------------------- | --------------------- |
| `<short sha>` | <type> | <subject> | <Unreleased bullet> | high \| medium \| low |

### Skipped

| Commit | Why skipped |
| ------ | ----------- |
```

## Apply result (loop `L2`/`L3`)

```markdown
# Changelog Result

## Overview

<which commits/releases were added to CHANGELOG — name types and sections>

## Summary

### Changes

| Commit      | Type   | Entry                                |
| ----------- | ------ | ------------------------------------ |
| <short sha> | <type> | <Unreleased bullet added or updated> |

### Skipped

| Commit | Why skipped |
| ------ | ----------- |

## Verification

| Check                    | Result         |
| ------------------------ | -------------- |
| `CHANGELOG.md` structure | <pass \| fail> |
```

## Loop session metrics (verifier / logs)

```markdown
## Session Metrics

| Field | Value |
| Level | <L1\|L2\|L3> |
| Mode | <survey\|apply> |
| Commit range | <commit_range> |
| Commits assessed | <count> |
| File modified | <changelog_file or "None"> |
| Outcome | <one-line result> |
```

## PR body templates

| Mode   | Level     | Template                            |
| ------ | --------- | ----------------------------------- |
| Survey | `L1`      | `assets/pr-body-template-survey.md` |
| Apply  | `L2`/`L3` | `assets/pr-body-template.md`        |

### Overview (skill-specific)

**Good:** `Processed 4 conventional commits since last changelog SHA; would add 3 Unreleased bullets under Changed; no file edits at L1.`

**Bad:** `Changelog loop run finished.`

## Rules

- At `L1`, survey shape — list intended entries under Candidates; do not edit `CHANGELOG.md`.
- At `L2`/`L3`, apply shape; update only `CHANGELOG.md` under `## [Unreleased]`.
