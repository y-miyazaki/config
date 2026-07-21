<!--
Canonical PR-facing template for loop-docs-triage.

Load ONLY at synthesis time, after triage and file edits complete.
loop-finalize extracts ## Overview and ## Summary for the PR body.

Rules:
- Keep top-level ## Overview and ## Summary headings exactly as written.
- Use Markdown tables in Summary (not bullet lists for fix rows).
- ASCII only in table cells.
- Overview: Trigger → Problem → Action in 1-2 sentences (see common-output-format.md).
- Do NOT put Level, Target, URLs, or "see below" filler in Overview.
-->

## Overview

<!--
  Trigger: docs drift scan scope
  Problem: what was stale/missing/broken
  Action: files fixed vs deferred (name paths when <=3)

  GOOD: Docs drift scan found 3 stale package references in mkdocs nav; this run updated README and mkdocs.yml and deferred 1 Watch item in a generated directory.
  BAD:  Documentation triage loop completed at L2.
-->

<one or two sentences: trigger, problem, action — plain language for a reviewer who has not read detect JSON>

## Summary

### Fixes Applied

| File   | Reason          | Change                              |
| ------ | --------------- | ----------------------------------- |
| <path> | <from findings> | <minimal change summary, or "None"> |

### Deferred

| File               | Reason                |
| ------------------ | --------------------- |
| <path or "_None_"> | <why deferred or "—"> |

### Suggested next action

<one sentence for the human reviewer, e.g. "Merge if the Context7 pin and nav entries match current packages.">

**Outcome:** <one-line result, e.g. "Fixed 3 High-Priority doc drift items; 0 Watch">
