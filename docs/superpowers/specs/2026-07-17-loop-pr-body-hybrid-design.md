# Loop PR Body Hybrid Design

**Status:** Approved for planning  
**Date:** 2026-07-17  
**Trigger:** [PR #417](https://github.com/y-miyazaki/config/pull/417) summary lacked failure reason and fix details; static caller `pr_body` was used as-is.

## Problem

`loop-finalize` passes caller `pr_body` unchanged to `gh pr create`. Detect already has `failures[]` (workflow, run URL, job, reason) and the implementer already emits a structured `## Summary`, but neither appears on the PR. Reviewers cannot tell which CI failure the PR addresses without opening the Actions run.

## Goals

- Human-readable PR body: which failure(s), what changed, agent narrative when present.
- Generic across all loops (changelog, docs-triage, ci-sweeper, future loops).
- Deterministic ground truth for failure context and file list; optional LLM `## Summary` for narrative only.
- Unit-testable pure function under `loop-finalize/lib/`.

## Non-Goals

- Dynamic `pr_title` (remains caller static string).
- Inferring “which failures were actually fixed” vs deferred Watch (list detect `failures[]`; Changes + Summary show the edit).
- Rewriting per-caller static `pr_body` marketing text.
- Changing `loop-notify-pr` contracts (reuse redact/truncate patterns only).

## Decisions

| Topic | Choice |
| --- | --- |
| Content model | Hybrid: mechanical sections required when data exists; Agent `## Summary` block appended when parseable |
| Scope | All loops; domain sections appear only when detect schema provides data (e.g. `failures[]`) |
| Agent text | Whole `## Summary` … next H2 (not key/value parse) |
| Failure listing | Enumerate all `failures[]` (cap 5 + “and N more”); never hide multiples behind “Other failures: N” only |
| PR title | Unchanged (static caller input) |
| Implementation | `loop-finalize/lib/render_pr_body.sh` pure function; Create PR step calls it |
| Testing | bats on the lib; no new top-level `scripts/` entry |

## Architecture

```text
caller pr_body (static prefix)
        │
ci-loop-agent finalize
        │  passes: prefix, detect_result_json, changed files, agent-output path, footer fields
        v
loop-finalize Create PR step
        │
        ├─ render_pr_body.sh  →  composed markdown
        └─ gh pr create --body <composed>
```

### Placement

| Path | Role |
| --- | --- |
| `.github/actions/loop-finalize/lib/render_pr_body.sh` | Compose body; no `gh` / no git push |
| `.github/actions/loop-finalize/action.yml` | Wire env; call lib before `gh pr create` |
| `test/bats/.github/actions/loop-finalize/lib/render_pr_body.bats` | Unit tests |

### Wiring inputs (new or reused)

| Source | Into finalize / render |
| --- | --- |
| `inputs.pr_body` (caller prefix + existing Level/Target footer from caller YAML, or footer fields passed separately) | `PR_BODY_PREFIX` and/or footer env |
| `detect_result_json` (already on `ci-loop-agent` / execute; **add passthrough to finalize**) | `DETECT_RESULT_JSON` |
| Domain changed files (merge-base diff excluding `.loop/`, same idea as `notify_context.sh`) | `CHANGED_FILES` (newline list or JSON array) |
| Last `agent-output.txt` path from execute status dir | `AGENT_OUTPUT_PATH` |
| `level`, target key, `skip_reason` | Footer (keep current semantics) |

Footer may stay assembled in `ci-loop-caller*.yaml` today; prefer moving Level/Target/Skip into `render_pr_body` once inputs are available so composition is single-sourced. Either is acceptable if PR body order matches the format below.

## Body format

Composition order (top → bottom):

1. Caller `pr_body` prefix (omit if empty)
2. `## Failure context` — only if `failures[]` non-empty
3. `## Changes` — only if at least one non-`.loop/` changed file
4. Agent `## Summary` block — only if found in agent output
5. Footer: Level / Target / Skip reason (existing)

### Failure context rules

- Fields per failure (when present): workflow name, run URL, job name, failure_type, reason.
- One failure → one bullet group.
- Multiple failures → list **all** entries (human must see every workflow/job in scope).
- More than 5 → first 5 + line `… and N more`.
- Missing `failures[]` (changelog / docs-triage) → omit entire section.

### Changes rules

- List paths from domain diff (exclude `.loop/`).
- Cap display at 20 paths + `… (+N more)` if needed (align with notify_context).

### Agent Summary rules

- Extract from first `## Summary` heading through the line before the next `## ` heading (or EOF).
- If absent → omit (do not fail).
- Apply redact + truncate (`SUMMARY_MAX_CHARS`, default 4000).
- Redact patterns aligned with `loop-execute/lib/notify_context.sh` / ci-sweeper sanitize.

### Example (ci-sweeper, single failure)

```markdown
## Summary
Automated minimal CI fix by `loop-ci-sweeper`.

---
*This PR was created by a loop automation. Review before merging.*

## Failure context
- Workflow: `on-ci-push-markdown`
- Run: https://github.com/y-miyazaki/config/actions/runs/29558828923
- Job: `markdown-ci / lint`
- Type: `regression`
- Reason: CI failure in job markdown-ci / lint (regression)

## Changes
- `docs/ci-sweeper-test.md`

## Summary
- **Root cause:** docs/ci-sweeper-test.md:7 MD001 — heading jumped from h1 to h3
- **Fix applied:** Changed `###` to `##` for the MD001 heading
- **Outcome:** markdownlint clean

- Level: L2
- Target: `integration:main`
- Skip reason: none
```

Note: two `## Summary` headings can appear (caller prefix title vs agent report). That matches current caller templates and agent output contracts; do not rename caller prefix in this change.

## Error handling

- Invalid `DETECT_RESULT_JSON` → treat as `{}`; omit Failure context.
- Missing agent output file → omit Agent Summary.
- Empty composed body (no prefix, no sections) → still allow `gh pr create` without `--body`, same as today when `PR_BODY` empty.
- Never fail the finalize job solely because optional sections are missing.

## Testing

`render_pr_body.bats` must cover:

| Case | Expectation |
| --- | --- |
| No failures | No Failure context |
| One failure | One failure block |
| Three failures | All three listed |
| Seven failures | Five listed + `… and 2 more` |
| Agent Summary present | Block appended |
| Agent Summary absent | Omitted |
| Secret-like strings in reason/Summary | Redacted |
| Empty changed files | No Changes section |
| Empty prefix | Starts at first mechanical section |

## Documentation updates (implementation phase)

- `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md` — `pr_body` is static prefix; finalize composes final body.
- Per-loop workflow design docs (`loop-ci-sweeper`, `loop-changelog`, `loop-docs-triage`) — one-line note on hybrid PR body.
- Clarify vs notify: `loop-notify-pr` keeps its own context JSON; PR body composition is finalize-owned.

## Risks

| Risk | Mitigation |
| --- | --- |
| Duplicate `## Summary` headings confuse some renderers | Accepted; document; caller rename is out of scope |
| Agent Summary long/noisy | Truncate + redact |
| Detect lists failures agent deferred as Watch | Intentional: show detect scope; Changes/Summary show edits |
| Passthrough wiring misses agent-output path | Fail soft (omit Summary); add bats + one wiring check in action |

## Related observations (out of scope)

- Run [29559096677](https://github.com/y-miyazaki/config/actions/runs/29559096677) did not create PR #417; it budget-skipped. Creator was [29558840978](https://github.com/y-miyazaki/config/actions/runs/29558840978).
- Verifier logged `APPROVE — No meaningful changes outside .loop/` while domain file changed; investigate separately.
