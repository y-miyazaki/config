---
name: loop-verifier
description: >-
  Independent checker for maker diffs in a maker/checker split. Default
  stance is REJECT until evidence is strong. Use when verifying loop-produced
  changes, after a minimal-fix or maker agent, or when asked to APPROVE
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

1. Load [common-checklist.md](references/common-checklist.md). If a caller-supplied domain rubric is in the prompt, apply it **in addition to** the generic checklist — domain REJECT rules win on conflict for that loop.
2. Check scope: only relevant files; honor denylist and allowlist.
3. Check intent: the change addresses the stated target.
4. Check honesty: no disabled tests, skipped assertions, or commented-out checks as the “fix.”
5. Check secrets: no credentials or sensitive values added.
6. On attempt 2+, REGRESSION mode: REJECT only if a prior open rejection is still unfixed, factually wrong, or this attempt introduced a new factual error in changed files. Do not hunt for new nits.
7. Emit [common-output-format.md](references/common-output-format.md). Default `REJECT` until every required check passes.

### Error Handling

| Condition                               | Severity    | Action                                                    |
| --------------------------------------- | ----------- | --------------------------------------------------------- |
| Cannot read the branch diff             | Fatal       | `REJECT` with reason; do not APPROVE                      |
| Domain rubric missing                   | Info        | Apply generic checklist only                              |
| Tests required by rubric but cannot run | Recoverable | `REJECT` or escalate in `reason`; do not APPROVE on faith |

### Examples

- Prompt: `Verify the maker branch against the CI failure in context`
- Result: JSON `verdict` plus Evidence; REJECT if the diff does not address the logged failure
