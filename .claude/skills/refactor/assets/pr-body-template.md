<!--
Canonical PR-facing template for loop-refactor.

Load ONLY at synthesis time, after refactor edits complete.
loop-finalize extracts ## Overview and ## Summary for the PR body.
-->

## Overview

<!--
  Trigger: H1 hint from detect (kind + path)
  Problem: duplication or oversized unit (plain language)
  Action: what was refactored; validation run

  GOOD: duplication_block in scripts/foo.sh shared 12 lines with scripts/bar.sh; extracted shared helper in scripts/lib/foo_lib.sh; shellcheck + bats passed.
  BAD:  Refactor loop completed at L2.
-->

<one or two sentences: trigger, problem, action — plain language for a reviewer>

## Summary

### Fixes Applied

| File   | Hint kind                             | Change                              |
| ------ | ------------------------------------- | ----------------------------------- |
| <path> | <duplication_block \| oversized_unit> | <minimal change summary, or "None"> |

### Deferred

| Path / hint        | Reason                |
| ------------------ | --------------------- |
| <path or "_None_"> | <why deferred or "—"> |

### Suggested next action

<one sentence for the human reviewer, e.g. "Merge if characterization tests cover the extracted helper.">

**Outcome:** <one-line result, e.g. "Applied local-structure dedupe for one hint; 2 hints deferred">

