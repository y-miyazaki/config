# Loop PR Body Skill Contract

Platform design for human-readable loop PR bodies. Skill-owned narrative; finalize-owned mechanical sections.

| Layer                       | Document                                                                                            |
| --------------------------- | --------------------------------------------------------------------------------------------------- |
| Readable PR body spec       | [Loop PR Body Readable Design](../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md)  |
| Automation PR rules         | Per-skill `references/category-automation-envelope.md` (load on automation path only)               |
| Report shapes               | Per-skill `references/common-output-format.md` (+ `common-output-format-automation.md` where split) |
| Hybrid composition (legacy) | [Loop PR Body Hybrid Design](../../superpowers/specs/2026-07-17-loop-pr-body-hybrid-design.md)      |
| Notify on human PR          | [loop-notify-pr Specification](../../reference/loop-notify-pr-specification.md)                     |

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

| Rule        | Requirement                                                                                   |
| ----------- | --------------------------------------------------------------------------------------------- |
| Length      | As long as needed for a useful summary — prefer completeness over brevity                     |
| Structure   | **Trigger** → **Substance** → **Action** in plain language                                    |
| Audience    | Reviewer who has not read detect JSON, logs, or session report                                |
| Substance   | Name dominant categories, files, or failure types — add scope when many items                 |
| Links       | Link commit ranges and SHAs to compare or commit URLs when detect JSON supplies `compare_url` |
| Specificity | Name workflows/files/failure types when ≤3 items; otherwise category + scope                  |
| Omit        | Level, Target, run URLs, boilerplate, "see Summary below"                                     |
| Tone        | Factual, past tense for completed work; no emoji; ASCII in code spans                         |

**Passes** when the reviewer can state _why this PR exists_ without opening the diff.

**Fails** when Overview is automation boilerplate, metadata only, or defers all substance to Summary.

Per-skill required elements and examples live in each skill's `references/common-output-format.md`, `references/category-automation-envelope.md` (automation path), `references/category-pr-body-links.md`, and `assets/pr-body-template.md`. **Same filename under each loop skill does not mean same content** — templates, envelopes, and link rules are per-skill.

### What the platform owns

| Section               | Source                                                                                                                                                            |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `## Failure context`  | `detect_result_json.failures[]` (ci-sweeper) — Workflow/Job/Run as Markdown links when URLs are present                                                           |
| `## Changes`          | git diff paths — **omitted** when agent Summary contains `### Changes` or `### Fixes Applied`; paths link to `blob/{branch}` when repository and branch are known |
| `## Run Metadata`     | Level, Target, Skip reason table                                                                                                                                  |
| Automation disclaimer | `render_automation_disclaimer()`                                                                                                                                  |
| Created By footer     | One-line `Created By {engine} {model} In/Out: {in}/{out}` from engine + `usage_json` (omit when unavailable)                                                       |

Finalize **passthrough** agent `## Overview`, `## Summary`, and `## Verification` with redact/truncate only — no table regeneration.

## Canonical result shape (interactive + loop PR)

Interactive runs and loop PR bodies share the same reader-facing sections (Run Metadata is loop PR only):

```markdown
## Overview

<trigger → problem → action; plain-language summary for a reviewer>

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

<loop PR only — finalize-owned Level / Target / Skip reason table>

---

*This PR was created by a loop automation. Review before merging.*

Created By <engine> <model> In/Out: <in>/<out>
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
8. Created By footer (finalize — engine/model/tokens when available)

## Skill checklist

Every loop automation skill MUST:

1. Define survey/apply report shapes in `references/common-output-format.md` (and `common-output-format-automation.md` when split).
2. Ship `references/category-automation-envelope.md` with `may_edit` Constraints, PR body rules, and Session Metrics (automation path only).
3. Ship `assets/pr-body-template.md` and `assets/pr-body-template-survey.md` with fixed top-level headings and per-skill Overview examples (good/bad).
4. Branch on `may_edit` from `## Constraints` only — do not branch agent behavior on caller `level`.
5. Instruct the agent to load the PR template at synthesis time when `may_edit` is set in Constraints.
6. Keep `## Session Metrics` separate from PR-facing `## Summary` (no duplicate headings).
7. Overview MUST satisfy the [Overview contract](#overview-contract) — trigger, problem, action in plain language.
8. Ship `references/category-pr-body-links.md` with per-skill link rules — see each skill's file; enforced for presence and placeholder patterns by `check_loop_pr_body_contract.sh`.

## Source of truth

`check_loop_pr_body_contract.sh` checks **structure** (required files, headings, forbidden patterns) for all loop skills.

| Artifact                                                                            | Source of truth                                                 | Cross-skill content sync?                                                      |
| ----------------------------------------------------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `assets/pr-body-template.md`, `assets/pr-body-template-survey.md`                   | per skill under `.apm/packages/<pkg>/.apm/skills/<loop-skill>/` | **No** — per-skill tables/examples                                             |
| `references/category-automation-envelope.md`, `references/common-output-format*.md` | per skill                                                       | **No**                                                                         |
| `references/category-pr-body-links.md`                                              | per skill                                                       | **No** — shared file-path rules may overlap; ci-sweeper adds workflow/job rows |
| `scripts/self/apm/check_loop_pr_body_contract.sh`                                   | `scripts/self/apm/`                                             | one script                                                                     |
| `.github/actions/loop-finalize/lib/render_pr_body.sh`                               | `.github/actions/`                                              | one composer                                                                   |

Edit link rules in the affected skill's `references/category-pr-body-links.md` directly. Templates use backtick placeholders only — not `https://github.com/org/repo/...` example links (markdown-link-check 404).

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

Loop automation skills listed in `validate_agent_report.sh` (`changelog`, `ci-sweeper`, `docs-updater`, `refactor`, `tech-debt`) run mechanical format checks before the LLM verifier. Failures produce structured REJECT (no APPROVE until fixed).

### Four-plane vs validation matrix

| Plane     | Caller input                  | Skill reads? | `validate_agent_report.sh`                                                                    |
| --------- | ----------------------------- | ------------ | --------------------------------------------------------------------------------------------- |
| Autonomy  | `level`                       | No           | No                                                                                            |
| Edit gate | `may_edit`                    | Yes          | Survey vs apply shape                                                                         |
| Artifact  | `write_target`, `report_file` | Yes          | All listed skills use `### Changes` in apply shape (tech-debt lists `report_file` path there) |
| Delivery  | `delivery`                    | No           | No                                                                                            |

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
