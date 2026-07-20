# Loop PR Body Skill Contract

Platform design for human-readable loop PR bodies. Skill-owned narrative; finalize-owned mechanical sections.

| Layer                       | Document                                                                                           |
| --------------------------- | -------------------------------------------------------------------------------------------------- |
| Readable PR body spec       | [Loop PR Body Readable Design](../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md) |
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

- **Overview** — synthesized plain-language lead (like triage "Suggested next action" density, but covering trigger + problem + action). See [Overview contract](#overview-contract) below.
- **Summary** — fix tables, deferred items, suggested next action, outcome (like triage panel findings + decision prose).
- **Session report** — domain sections (`High-Priority Items`, `Actionable Fixes`, …) plus `## Session Metrics` (Field \| Value table) for verifier/logs.

Load `assets/pr-body-template.md` **at synthesis time only** (after triage/fix work), mirroring triage-panel step 7.

### Overview contract

`## Overview` is the first thing a human reads. Finalize passthrough only — the skill MUST emit review-ready prose.

| Rule        | Requirement                                                                  |
| ----------- | ---------------------------------------------------------------------------- |
| Length      | 1–2 sentences (max ~280 characters)                                          |
| Structure   | **Trigger** → **Problem** → **Action** in plain language                     |
| Audience    | Reviewer who has not read detect JSON, logs, or session report               |
| Specificity | Name workflows/files/failure types when ≤3 items; otherwise count + category |
| Omit        | Level, Target, commit SHAs, run URLs, boilerplate, "see Summary below"       |
| Tone        | Factual, past tense for completed work; no emoji; ASCII in code spans        |

**Passes** when the reviewer can state _why this PR exists_ without opening the diff.

**Fails** when Overview is automation boilerplate, metadata only, or defers all substance to Summary.

Per-skill required elements and examples live in each skill's `references/common-output-format.md` and `assets/pr-body-template.md`.

### What the platform owns

| Section               | Source                                       |
| --------------------- | -------------------------------------------- |
| `## Failure context`  | `detect_result_json.failures[]` (ci-sweeper) |
| `## Changes`          | git diff paths                               |
| `## Run Metadata`     | Level, Target, Skip reason table             |
| Automation disclaimer | `render_automation_disclaimer()`             |

Finalize **passthrough** agent `## Overview` and `## Summary` with redact/truncate only — no table regeneration.

## PR body composition order

1. `## Overview` (agent)
2. `## Failure context` (detect, when present)
3. `## Summary` (agent)
4. `## Changes` (finalize)
5. `## Run Metadata` (finalize)
6. Automation disclaimer (finalize)

## Skill checklist

Every `loop-*` skill MUST:

1. Define session report + PR body sections in `references/common-output-format.md`.
2. Ship `assets/pr-body-template.md` with fixed top-level `## Overview` and `## Summary` headings and per-skill Overview examples (good/bad).
3. Instruct the agent to load the template at synthesis time and emit exactly those sections for PR composition.
4. Keep `## Session Metrics` separate from PR-facing `## Summary` (no duplicate headings).
5. Overview MUST satisfy the [Overview contract](#overview-contract) — trigger, problem, action in plain language.

## Quality bar

A PR body passes when a reviewer can answer without opening the diff:

- What triggered this run?
- What was wrong (root cause / drift)?
- What changed (per file or per failure)?
- What was deferred and why?
- What should the human do next?

This matches the information density of [APM #2321 Triage Panel verdict](https://github.com/microsoft/apm/issues/2321#issuecomment-5022508143).
