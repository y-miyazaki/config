<!--
Canonical PR-facing template for loop-changelog.

Load ONLY at synthesis time, after CHANGELOG.md edits complete.

Rules:
- Keep top-level ## Overview and ## Summary headings exactly as written.
- Overview: Trigger → Problem → Action in 1-2 sentences (see common-output-format.md).
- Do not list every commit SHA in Overview — use counts and section names.
-->

## Overview

<!--
  Trigger: commits/releases since last processed SHA
  Problem: what was missing from CHANGELOG.md
  Action: entries added or releases promoted

  GOOD: Processed 4 conventional commits since last changelog SHA; added 3 Unreleased bullets under Changed and promoted v1.2.0 release section.
  BAD:  Changelog loop run finished.
-->

<one or two sentences: which commits were processed and what CHANGELOG section was updated>

## Summary

### Changes Applied

| Commit      | Type   | Entry                                |
| ----------- | ------ | ------------------------------------ |
| <short sha> | <type> | <Unreleased bullet added or updated> |

### Skipped

| Commit            | Reason                                     |
| ----------------- | ------------------------------------------ |
| <sha or "_None_"> | <already listed / non-conventional or "—"> |

### Suggested next action

<one sentence, e.g. "Merge to advance Unreleased entries before next release tag.">

**Outcome:** <one-line result>
