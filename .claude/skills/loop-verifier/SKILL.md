---
name: loop-verifier
description: >-
  Independent checker for maker diffs in a maker/checker split. Default
  stance is REJECT until evidence is strong. Use when verifying loop-produced
  changes, after a maker agent produces a diff, or when asked to APPROVE
  or REJECT a branch diff against stated criteria. Do not implement fixes in
  this role. Caller-supplied domain rubric (when present in the prompt) is an
  additional input, not part of this skill.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "0.1.3"
---

**UTILITY SKILL** — generic loop checker. Not a domain entry skill.

## Input

- Maker diff (branch vs base) and optional maker summary
- Stated target (required): the issue, CI failure, or review comment the maker was asked to address
- Prior REJECT JSON(s) and attempt number (optional): enables REGRESSION mode on attempt 2+
- Optional domain rubric (caller-supplied markdown in the prompt)
- Optional extra context (CI log excerpt, detect facts)
- Project path allowlist / denylist when provided

## Output Specification

Report per [common-output-format.md](references/common-output-format.md). End with a single fenced JSON object (`verdict` `APPROVE` or `REJECT`).

## Execution Scope

### USE FOR:

- INITIAL scrutiny of a maker branch for factual blockers and scope violations
- REGRESSION checks that prior open rejections were actually fixed
- Confirming the diff matches the stated target (not a different problem)

### DO NOT USE FOR:

- Implementing or editing product files (checker does not write fixes)
- Replacing caller-supplied domain rubric on a loop caller
- Acting as the loop entry or maker skill
- Re-running CI or linters unless the domain rubric explicitly requires it

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)

## Workflow

1. Load [common-checklist.md](references/common-checklist.md). If a caller-supplied domain rubric is in the prompt, apply its REJECT conditions **in addition to** the generic gates: a domain rule may add REJECT conditions or stricter thresholds, but never removes or relaxes a generic gate.
2. SCOPE-01: only relevant files; honor denylist and allowlist.
3. INTENT-01: the change addresses the stated target.
4. HONEST-01: no disabled tests, skipped assertions, or commented-out checks as the “fix.”
5. SECRET-01: no credentials or sensitive values added.
6. RISK-01: classify risk per [common-checklist.md](references/common-checklist.md); for medium or high, note human review in `reason`.
7. On attempt 2+ (prior REJECT JSON supplied), REGRESSION mode: REJECT only if a prior open rejection is still unfixed, factually wrong, or this attempt introduced a new factual error in changed files. Do not hunt for new nits.
8. Emit [common-output-format.md](references/common-output-format.md). Default `REJECT` until SCOPE-01, INTENT-01, HONEST-01, SECRET-01, and every domain REJECT rule pass.

### Error Handling

| Condition                               | Severity    | Action                                                                                  |
| --------------------------------------- | ----------- | --------------------------------------------------------------------------------------- |
| Cannot read the branch diff             | Fatal       | `REJECT` with reason; do not APPROVE                                                    |
| Asked to implement or edit a fix        | Fatal       | Do not edit; `REJECT` with `files: []`; `reason`: out of scope (checker role)           |
| Stated target missing from the prompt   | Fatal       | `REJECT` with `files: []`; `reason`: stated target required to check INTENT-01          |
| Domain rubric missing                   | Info        | Apply generic checklist only                                                            |
| Tests required by rubric but cannot run | Recoverable | `REJECT`; name the test that could not run and why in `reason`; do not APPROVE on faith |

### Examples

- Prompt: `Verify the maker branch against the CI failure in context`
- Result: Markdown Evidence plus JSON `verdict`; REJECT if the diff does not address the logged failure
