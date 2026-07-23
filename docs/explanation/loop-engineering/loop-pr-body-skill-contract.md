# Loop PR Body Skill Contract

Platform design for human-readable loop PR bodies. Skill-owned narrative; finalize-owned mechanical sections.

| Layer                       | Document                                                                                           |
| --------------------------- | -------------------------------------------------------------------------------------------------- |
| Readable PR body spec       | [Loop PR Body Readable Design](../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md) |
| Automation PR rules         | Per-skill `references/category-automation-envelope.md` (load on automation path only)              |
| Report shapes               | Per-skill `references/common-output-format.md` (+ `common-output-format-loop.md` where split)      |
| Hybrid composition (legacy) | [Loop PR Body Hybrid Design](../../superpowers/specs/2026-07-17-loop-pr-body-hybrid-design.md)     |
| Notify on human PR          | [loop-notify-pr Specification](../../reference/loop-notify-pr-specification.md)                    |

## Reference: APM Triage Panel

Loop PR bodies follow the same separation as [microsoft/apm `triage-panel`](https://github.com/microsoft/apm/blob/main/.github/workflows/triage-panel.md) and [`apm-triage-panel`](https://github.com/microsoft/apm/tree/main/.agents/skills/apm-triage-panel):

| Triage Panel                                   | Loop engineering                                                          |
| ---------------------------------------------- | ------------------------------------------------------------------------- |
| Workflow (`triage-panel.md`)                   | Caller workflow + `loop-finalize` (`render_pr_body.sh`)                   |
| Skill (`apm-triage-panel/SKILL.md`)            | `loop-*` skill (`SKILL.md` + references)                                  |
| Verdict template (`assets/triage-template.md`) | `assets/pr-body-template.md` per loop skill                               |
| Workflow posts comment                         | `loop-finalize` composes PR body; `loop-notify-pr` posts human PR comment |
| Mechanical footer (ratification)               | `render_automation_disclaimer()`                                          |

### What the skill owns

- **Overview** — synthesized plain-language lead (trigger → problem → action). See [Overview contract](#overview-contract) below.
- **Summary** — `### Changes`, `### Deferred` (or domain equivalent), and optional domain subsections only. No Outcome line, no Suggested next action, no duplicate file lists.
- **Verification** — checks the agent already ran (pass/fail/skip/blocked). Interactive: agent obligation; loop PR: extracted as top-level `## Verification`.
- **Session report** — verifier/logs only (`## Session Metrics`, domain bullets). Not copied into PR body.

Load `assets/pr-body-template.md` **at synthesis time only** (after triage/fix work), mirroring triage-panel step 7.

### Overview contract

`## Overview` is the first thing a human reads. Finalize passthrough only — the skill MUST emit review-ready prose.

| Rule        | Requirement                                                                  |
| ----------- | ---------------------------------------------------------------------------- |
| Length      | 1–2 sentences (max ~280 characters)                                          |
| Structure   | **Trigger** → **Substance** → **Action** in plain language                   |
| Audience    | Reviewer who has not read detect JSON, logs, or session report               |
| Substance   | Name dominant categories, files, or failure types — **not counts alone**     |
| Specificity | Name workflows/files/failure types when ≤3 items; otherwise category + scope |
| Omit        | Level, Target, commit SHAs, run URLs, boilerplate, "see Summary below"       |
| Tone        | Factual, past tense for completed work; no emoji; ASCII in code spans        |

**Passes** when the reviewer can state _why this PR exists_ without opening the diff.

**Fails** when Overview is automation boilerplate, metadata only, or defers all substance to Summary.

Per-skill required elements and examples live in each skill's `references/common-output-format.md`, `references/category-automation-envelope.md` (automation path), and `assets/pr-body-template.md`.

### What the platform owns

| Section               | Source                                                                                        |
| --------------------- | --------------------------------------------------------------------------------------------- |
| `## Failure context`  | `detect_result_json.failures[]` (ci-sweeper)                                                  |
| `## Changes`          | git diff paths — **omitted** when agent Summary contains `### Changes` or `### Fixes Applied` |
| `## Run Metadata`     | Level, Target, Skip reason table                                                              |
| Automation disclaimer | `render_automation_disclaimer()`                                                              |

Finalize **passthrough** agent `## Overview`, `## Summary`, and `## Verification` with redact/truncate only — no table regeneration.

## Canonical result shape (interactive + loop PR)

Interactive runs and loop PR bodies share the same reader-facing sections (Run Metadata is loop PR only):

```markdown
## Overview

<trigger → problem → action; 1–2 sentences>

## Summary

### Changes

<what was fixed — see list vs table rule>

### Deferred

<what was not fixed and why — omit subsection when empty>

### <Optional domain>

Architecture Proposal / Skipped / Watch / …

## Verification

<checks agent ran — see list vs table rule>

## Run Metadata

<loop PR only — finalize-owned>
```

### List vs table

| Case                                                           | Format                                                      |
| -------------------------------------------------------------- | ----------------------------------------------------------- |
| One item, one fact (e.g. single file path, one check)          | Bullet list                                                 |
| Two or more rows, or multiple columns (path + reason + change) | Markdown table                                              |
| Empty subsection                                               | Omit the `###` heading entirely (do not emit `_None_` rows) |

### Summary content to omit

Do **not** put these in **Summary** — they duplicate **Changes** / **Deferred** or belong elsewhere:

- `**Outcome:**` one-liners
- `### Suggested next action` (merge into Overview when a reviewer hint is needed)
- Top-level `## Changes` file bullets (agent uses `### Changes` table under Summary; finalize adds path list only as fallback)
- `### Validation` inside Summary (use top-level `## Verification` instead)

## PR body composition order

1. `## Overview` (agent)
2. `## Failure context` (detect, when present)
3. `## Summary` (agent — `### Changes`, `### Deferred`, optional domain)
4. `## Verification` (agent)
5. `## Changes` (finalize — only when Summary lacks `### Changes` / `### Fixes Applied`)
6. `## Run Metadata` (finalize)
7. Automation disclaimer (finalize)

## Skill checklist

Every loop automation skill MUST:

1. Define survey/apply report shapes in `references/common-output-format.md` (and `common-output-format-loop.md` when split).
2. Ship `references/category-automation-envelope.md` with `may_edit` Constraints, PR body rules, and Session Metrics (automation path only).
3. Ship `assets/pr-body-template.md` and `assets/pr-body-template-survey.md` with fixed top-level headings and per-skill Overview examples (good/bad).
4. Branch on `may_edit` from `## Constraints` only — do not branch agent behavior on caller `level`.
5. Instruct the agent to load the PR template at synthesis time when `may_edit` is set in Constraints.
6. Keep `## Session Metrics` separate from PR-facing `## Summary` (no duplicate headings).
7. Overview MUST satisfy the [Overview contract](#overview-contract) — trigger, problem, action in plain language.

## Fixes / Deferred consistency

**Deferred** means the agent did **not** leave a fix in the final working tree for that path. Platform `## Changes` is mechanical (`git diff` paths from `loop-finalize`) — agent narrative MUST match git truth.

| Rule                  | Requirement                                                                                           |
| --------------------- | ----------------------------------------------------------------------------------------------------- |
| Mutual exclusion      | A path MUST NOT appear in both **Changes** and **Deferred**                                           |
| Git alignment         | Every path in `git diff` MUST appear in **Changes** (or **Report** for tech-debt)                     |
| Deferred = no edit    | Do not leave modifications for deferred paths — revert stray edits before the final report            |
| Multi-attempt cleanup | If an earlier attempt edited a file later classified as deferred, revert those edits before synthesis |
| Platform **Changes**  | Omitted when Summary has `### Changes`; otherwise finalize adds git-diff path list                    |

**Passes** when Deferred paths are absent from platform `## Changes` and every changed file has a Fixes Applied row with reason and change summary.

**Fails** when Deferred lists paths that still appear in `## Changes` (see [PR #454](https://github.com/y-miyazaki/config/pull/454): deferred docs still in git diff).

Before emitting PR `## Summary`, run `git diff --name-only` (or `git diff --cached --name-only` when staged) and reconcile **Changes** and **Deferred**.

## Mechanical validation (loop-execute)

For fix skills (`docs-updater`, `refactor`, `ci-sweeper`, `changelog`, `tech-debt`), `loop-execute` runs `validate_agent_report.sh` before the LLM verifier. Failures produce structured REJECT (no APPROVE until fixed).

Checks include: required `## Overview` / `## Summary` / `## Verification`; `### Changes` when diff is non-empty; forbidden legacy sections (`Fixes Applied`, `Outcome`, top-level `## Changes`); **Deferred vs git diff** consistency (catches [PR #454](https://github.com/y-miyazaki/config/pull/454)-class bugs).

LLM rubric: `.github/actions/loop-execute/lib/agent_output_format_criteria.md` (auto-appended for these skills). Interactive/chat runs skip this gate.

## Quality bar

A PR body passes when a reviewer can answer without opening the diff:

- What triggered this run?
- What was wrong (root cause / drift)?
- What changed (per file or per failure)?
- What was deferred and why?
- What should the human do next?

This matches the information density of [APM #2321 Triage Panel verdict](https://github.com/microsoft/apm/issues/2321#issuecomment-5022508143).
