# Loop PR Body Contract

Skill-owned narrative for loop PR bodies. Load survey or apply template from `assets/` at synthesis time.

## What the skill owns

- **Overview** — plain-language lead (trigger → substance → action). See [Overview contract](#overview-contract).
- **Summary** — `### Changes`, `### Deferred` (or domain equivalent: `### Skipped` for changelog), optional domain subsections only.
- **Verification** — checks the agent already ran (apply mode only).
- **Session report** — verifier/logs only (`## Session Metrics`). Not copied into PR body.

## Overview contract

| Rule      | Requirement                                                              |
| --------- | ------------------------------------------------------------------------ |
| Length    | 1–2 sentences (max ~280 characters)                                      |
| Structure | **Trigger** → **Substance** → **Action** in plain language               |
| Substance | Name dominant categories, files, or failure types — **not counts alone** |
| Omit      | Level, commit SHAs, run URLs, boilerplate, "see Summary below"           |

## Canonical PR shape

```markdown
## Overview

<trigger → substance → action; 1–2 sentences>

## Summary

### Changes

<what was fixed — table when 2+ rows>

### Deferred

<what was not fixed and why — omit when empty>

## Verification

<checks agent ran — apply mode only>
```

### List vs table

| Case                                 | Format                 |
| ------------------------------------ | ---------------------- |
| One item, one fact                   | Bullet list            |
| Two or more rows or multiple columns | Markdown table         |
| Empty subsection                     | Omit the `###` heading |

### Summary content to omit

- `**Outcome:**` one-liners
- `### Suggested next action`
- Top-level `## Changes` (use `### Changes` under Summary)
- `### Validation` inside Summary (use `## Verification`)

## Fixes / Deferred consistency

**Deferred** means no fix remains in the working tree for that path.

| Rule               | Requirement                                                 |
| ------------------ | ----------------------------------------------------------- |
| Mutual exclusion   | A path MUST NOT appear in both **Changes** and **Deferred** |
| Git alignment      | Every path in `git diff` MUST appear in **Changes**         |
| Deferred = no edit | Revert edits to deferred paths before synthesis             |

Before emitting PR `## Summary`, run `git diff --name-only` and reconcile **Changes** and **Deferred**.
