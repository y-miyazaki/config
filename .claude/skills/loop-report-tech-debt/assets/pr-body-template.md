<!--
Canonical PR-facing template for loop-report-tech-debt.

Load ONLY at synthesis time, after report classification completes.
Persisted report file may use fuller tables; this template is the PR summary.

Rules:
- Keep top-level ## Overview and ## Summary headings exactly as written.
- Cap Critical + High rows shown here at 10; note truncation in Outcome if needed.
- Overview: Trigger → Problem → Action in 1-2 sentences (see common-output-format.md).
- Do not list every signal in Overview — use counts and report path.
-->

## Overview

<!--
  Trigger: scan scope (commit range)
  Problem: Critical/High presence and dominant categories
  Action: report file path; this skill does not apply code fixes

  GOOD: Debt scan over abc..def found no Critical/High items; 21 Watch signals recorded in docs/report/report-tech-debt/2026-07-21.md for scheduled review.
  BAD:  Technical debt loop completed.
-->

<one or two sentences: scan scope, finding severity, and where the full report lives>

## Summary

### Findings (Critical + High)

| Path        | Category   | Reason             | Recommendation        |
| ----------- | ---------- | ------------------ | --------------------- |
| <path:line> | <category> | <why this is debt> | <next step or "None"> |

### Watch

| Path               | Category          | Reason                |
| ------------------ | ----------------- | --------------------- |
| <path or "_None_"> | <category or "—"> | <why deferred or "—"> |

### Suggested next action

<one sentence, e.g. "Review Watch gitleaks TODO; no merge-blocking debt this run.">

**Outcome:** <one-line result, e.g. "No Critical/High; 21 Watch items; report at docs/report/report-tech-debt/YYYY-MM-DD.md">
