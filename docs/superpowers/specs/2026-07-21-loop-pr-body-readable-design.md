# Loop PR Body Readable Design

**Status:** Approved  
**Date:** 2026-07-21  
**Trigger:** [PR #444](https://github.com/y-miyazaki/config/pull/444), [PR #443](https://github.com/y-miyazaki/config/pull/443) — boilerplate-only Summary; duplicate `## Summary` blocks; no per-file fix detail.

## Problem

Loop PR bodies show caller boilerplate and metadata bullets but not what was fixed. Reviewers must open the diff to judge merge readiness. `loop-finalize` extracts only the first `## Summary` (session metrics), not fix narratives.

## Goals

- PR body alone supports ~80% merge judgment ([APM #2321](https://github.com/microsoft/apm/issues/2321) triage-panel quality bar).
- Agent owns narrative (`## Overview`, `## Summary` with tables); finalize passthrough with redact/truncate only.
- Single clear section structure — no duplicate `## Summary`.
- `loop-notify-pr` human PR comments match bot fix PR information density.

## Non-Goals

- Dynamic `pr_title`.
- Finalize-side table generation from JSON (agent emits Markdown tables).
- Changing detect or verifier contracts.

## Decisions

| Topic           | Choice                                                                                      |
| --------------- | ------------------------------------------------------------------------------------------- |
| Reader goal     | PR body alone ~80% judgment                                                                 |
| Section names   | `## Overview` + `## Summary` (agent); `## Run Metadata` (finalize table)                    |
| Session metrics | Rename skill `## Summary` → `## Session Metrics`; Field \| Value table (verifier/logs only) |
| Agent content   | Skill output format defines Overview + Summary tables; finalize passthrough                 |
| Failure context | Independent `## Failure context` from detect (ci-sweeper); documented in skill              |
| Run metadata    | Table: Level, Target, Skip reason (finalize-owned)                                          |
| Notify density  | Include agent Overview + Summary in human PR comment                                        |
| Scope           | Platform + skill output formats + caller `pr_body` in one change                            |

## PR Body Format (normative)

Composition order (top → bottom):

1. `## Overview` — agent (omit if empty); MUST follow [Overview contract](../../explanation/loop-engineering/loop-pr-body-skill-contract.md#overview-contract): Trigger → Problem → Action
2. `## Failure context` — detect `failures[]` when non-empty (ci-sweeper)
3. `## Summary` — agent fix tables + Outcome (omit if empty)
4. `## Changes` — changed file paths (finalize mechanical)
5. `## Run Metadata` — Level / Target / Skip reason table (finalize)
6. Automation disclaimer (finalize constant)

## Skill PR Body Contract

Every loop skill agent output ends with:

```markdown
## Overview

<trigger → problem → action in 1-2 plain-language sentences; per-skill examples in assets/pr-body-template.md>

## Summary

### Fixes Applied

| …   | …   | …   |
| --- | --- | --- |

### Deferred

| …   | …   |
| --- | --- |

**Outcome:** <one-line result>
```

Domain-specific column headers defined per skill `common-output-format.md`. Session report sections (`High-Priority Items`, `Actionable Fixes`, etc.) precede `## Session Metrics` (Field \| Value table).

## Architecture

```text
agent-output.txt
  ├─ session sections (verifier)
  ├─ ## Session Metrics
  ├─ ## Overview  ──┐
  └─ ## Summary   ──┼─ notify_context.sh → notify_context_json
                    └─ render_pr_body.sh → gh pr create body
detect failures[] ──→ ## Failure context (mechanical)
git diff paths    ──→ ## Changes (mechanical)
LEVEL/TARGET/...  ──→ ## Run Metadata (mechanical)
```

## Related

- [Loop PR Body Skill Contract](../../explanation/loop-engineering/loop-pr-body-skill-contract.md) — triage-panel reference mapping
- Supersedes duplicate-Summary acceptance in [2026-07-17-loop-pr-body-hybrid-design.md](2026-07-17-loop-pr-body-hybrid-design.md)
- [loop-notify-pr Specification](../../reference/loop-notify-pr-specification.md)
- Reference quality bar: [APM triage-panel workflow](https://github.com/microsoft/apm/blob/main/.github/workflows/triage-panel.md), [`apm-triage-panel` skill](https://github.com/microsoft/apm/tree/main/.agents/skills/apm-triage-panel)
