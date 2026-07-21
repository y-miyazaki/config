<!--
Canonical PR-facing template for loop-ci-sweeper.

Load ONLY at synthesis time, after triage and file edits complete.
loop-finalize adds ## Failure context from detect; this template covers Overview + Summary.

Rules:
- Keep top-level ## Overview and ## Summary headings exactly as written.
- Do not duplicate detect failure URLs here — Overview is plain language only.
- Use Markdown tables in Summary.
- Overview: Trigger → Problem → Action in 1-2 sentences (see common-output-format.md).
- Name workflow/job in Overview; URLs belong in platform ## Failure context only.
-->

## Overview

<!--
  Trigger: which workflow/job failed (name only)
  Problem: root cause from log_excerpt in plain language
  Action: fix applied and validation result

  GOOD: CI failed on markdownlint MD001 in docs/foo.md; fixed heading style in 1 file and re-ran markdownlint-cli2 clean.
  BAD:  CI sweeper addressed actionable failures.
-->

<one or two sentences: which CI failure was addressed, root cause, and fix strategy>

## Summary

### Fixes Applied

| Workflow / Job     | Root cause         | Fix                                 |
| ------------------ | ------------------ | ----------------------------------- |
| <workflow> / <job> | <from log_excerpt> | <minimal change summary, or "None"> |

### Deferred

| Workflow / Job                 | Type                                    | Reason                |
| ------------------------------ | --------------------------------------- | --------------------- |
| <workflow> / <job or "_None_"> | <flake\|infra\|env\|needs-human or "—"> | <why deferred or "—"> |

### Validation

| Command       | Result                  |
| ------------- | ----------------------- |
| <command run> | <pass / fail / not run> |

### Suggested next action

<one sentence, e.g. "Merge bot fix PR and re-run CI on the human PR.">

**Outcome:** <one-line result, e.g. "Fixed MD001 in docs/foo.md; markdownlint clean">
