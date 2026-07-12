# Changelog Loop Report Format

Use this structure for every run, including no-action exits.

```markdown
# Changelog Loop Report

## Commits Processed

- **SHA:** <sha>
- **Type:** <type>
- **Subject:** <subject>

## Skipped Commits

- <already listed in CHANGELOG or non-conventional, or "None">

## Summary

- **Level:** <L1|L2|L3>
- **Commit range:** <commit_range>
- **Commits assessed:** <count>
- **File modified:** <changelog_file or "None">
- **Outcome:** <one-line result>
```

## Rules

- Always emit all three `##` sections; use `None` or `0` when empty.
- At `L1`, list intended entries under Commits Processed but do not edit files.
- At `L2`/`L3`, update only `CHANGELOG.md` under `## [Unreleased]`.
