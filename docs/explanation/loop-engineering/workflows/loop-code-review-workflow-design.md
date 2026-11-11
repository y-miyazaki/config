# Loop Code Review Workflow Design

Workflow and operations design for the `code-review` loop.

| Layer        | Document                                                           |
| ------------ | ------------------------------------------------------------------ |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)       |
| Caller shell | [Loop Caller Workflows Design](../loop-caller-workflows-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)           |

**Artifacts:** `on-loop-code-review.yaml` · Claude Code built-in `code-review` skill · `scripts/self/loop/render_code_review_issues.sh`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md). Feature design (Japanese): [code-review loop(L2、Issue の起票)](../../../superpowers/specs/2026-11-09-loop-code-review-design.md).

## Purpose

Review the code merged to `main` since the last run and file the findings a checker approved as GitHub Issues. The loop runs at L2 with `delivery: issue_create`: it writes no fix and opens no PR.

### Supported use cases

- Weekly review of the changes between the stored `last_sha` and `HEAD` on `main`
- One Issue per verified finding, labeled `loop:code-review`
- No Issue for a finding that already has an Issue (open or closed)

### Out scope

- Code fixes (a human may add the `autofix` label to an Issue later; the existing autofix loop then runs on its own rules)
- L1 observation phase (skipped; **L2 start**, kept small by `finalize_issue_limit: 3`)
- Pull request heads (`delivery: issue_create` allows integration targets only)
- Webhook triggers (the loop runs on `schedule` and `workflow_dispatch` only)

## Flow

1. **Detect** runs the [built-in range detect](#built-in-range-detect) because the caller sets no `detect_script`.
2. **Maker** runs the built-in `code-review` skill with `Last SHA` as the base commit and writes the verified findings as a JSON array to `.loop-code-review/findings.json` (an empty array when there are none).
3. **Checker** reads the range diff and approves only when every finding has evidence in that diff and a real failure path. Any other result is REJECT (`agent_unchanged_verdict: REJECT`).
4. **Push Agent Branch** pushes the agent branch. On APPROVE, `finalize_script` runs [the re-verification](#finalize_script-re-verification) and writes `issues.json`.
5. **Deliver Message** opens the Issues (see [Issue creation](#issue-creation)).
6. **Delete Agent Branch** removes the agent branch; the state is written ([State](#state)).

## Caller inputs

Keys passed in `on-loop-code-review.yaml` via `with:` on `ci-loop-caller.yaml`. Shared semantics: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

Schedule: **`0 9 * * 3`** (Wednesday 09:00 UTC, weekly) and `workflow_dispatch`. Concurrency group `loop-state-main`, shared with the other loops that write state on `main`.

| Input                                                   | Dogfood value                                                                  |
| ------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `level` / `delivery`                                    | `L2` / `issue_create`                                                          |
| `loop_name`                                             | `code-review` (state file `.loop/state-code-review.json`)                      |
| `detect_script`                                         | omitted (built-in range detect)                                                |
| `detect_branch_match` / `state_branch`                  | `main` / `main`                                                                |
| `detect_max_targets`                                    | `1`                                                                            |
| `agent_engine` / `agent_cli_version`                    | `claude` / `2.1.318` (pinned; see [CLI version pinning](#cli-version-pinning)) |
| `agent_maker_skill_name`                                | `code-review` (Claude Code built-in skill)                                     |
| `agent_maker_model` / `agent_checker_model`             | `claude-sonnet-5` / `claude-opus-5`                                            |
| `agent_edit_target` / `agent_edit_allowlist`            | `report` / `.loop-code-review/findings.json` only                              |
| `agent_unchanged_verdict`                               | `REJECT` (mandatory for `issue_create`)                                        |
| `agent_tool_allowlist`                                  | `Bash(git cat-file:*)`, `Bash(git ls-files:*)`, `Bash(git rev-parse:*)`        |
| `agent_tool_denylist`                                   | `Agent` (no cap on sub-agent count exists, so the maker may not spawn any)     |
| `finalize_script`                                       | `scripts/self/loop/render_code_review_issues.sh`                               |
| `finalize_label_allowlist`                              | `loop:code-review`                                                             |
| `finalize_issue_limit`                                  | `3`                                                                            |
| `agent_loop_max_attempts`                               | `3`                                                                            |
| `budget_max_runs_per_day` / `budget_max_tokens_per_day` | `2` / `8000000`                                                                |

`agent_maker_instructions` and `agent_checker_instructions` are defined inline in the caller workflow. The checker rubric requires, for every finding, `title`, `body`, `fingerprint`, and `evidence` (`path`, `start_line`, `end_line`) with the cited lines present in the `<since>..<head>` diff.

## Built-in range detect

The caller omits `detect_script`, so `loop-detect` runs `range_detect.sh`. See [Built-in range detect](loop-caller-inputs-reference.md#built-in-range-detect) for the output contract.

- It lists files changed between `last_sha` and `HEAD`, excluding `.loop/`, the resolved state file, and the run-log file. No changed file skips the run.
- `verifier_context` holds `<since>..<head>` and up to 100 changed file paths. The checker uses it to confirm the evidence lies in the range.
- When the stored `last_sha` is unreachable, the range falls back to `HEAD~10`.
- `target_json.from.since` carries `last_sha` to `finalize_script`.

## `finalize_script` re-verification

`render_code_review_issues.sh` guards against a forged `APPROVE` (the verdict comes from the agent job).

- It acts only when `VERDICT` is `APPROVE`; any other verdict writes nothing and exits 0, so the state still records `rejected` and the circuit breaker works.
- It reads `.loop-code-review/findings.json` from the agent branch and keeps a finding only when its evidence lines overlap lines changed by `git diff <since> <ref>` in that file. The range comes from `TARGET_JSON`, never from the checkout or the state file.
- It drops findings whose title or body exceeds the length limit, and reports the dropped count in the step summary.
- It fails closed (exit 1, no `issues.json`) on a missing `from.since` or `from.ref`, an unreachable range, a `findings.json` that is not an array, or a malformed finding.

## Issue creation

Deliver Message validates `issues.json` (`[{title, body, fingerprint}]`) and then:

1. Computes the marker `<!-- code-review:fp:<hash16> -->`, where `hash16` is the first 16 hex characters of `sha256(loop_name + "\n" + fingerprint)`.
2. Drops findings whose marker appears in an open or closed Issue that carries every `finalize_label_allowlist` label.
3. Applies `finalize_issue_limit` to the remaining findings. The cut findings go to the step summary and are not carried over.
4. Sanitizes forged markers and mentions in each body, adds the marker and the Meta block, and creates the Issue with every `finalize_label_allowlist` label.

The write token for Issue creation is the GitHub App token that `loop-finalize` already uses; the agent job holds no write credential.

## State

State file: `.loop/state-code-review.json` on `state_branch`. Schema:

```json
{
  "targets": {
    "integration:main": {
      "last_run": "2026-11-11T09:00:00Z",
      "outcome": "issue_created",
      "consecutive_failures": 0,
      "last_sha": "abc123",
      "open_rejections": [],
      "last_reject_reason": ""
    }
  }
}
```

| Event                                                | Cursor (`last_sha`) | Outcome / failures                                       |
| ---------------------------------------------------- | ------------------- | -------------------------------------------------------- |
| Checker APPROVE with Issues opened                   | Advances            | `issue_created`                                          |
| Checker APPROVE with no finding (or only duplicates) | Advances            | `unchanged`                                              |
| Checker REJECT                                       | No change           | `rejected` (metadata); `consecutive_failures` increments |
| `finalize_script` or Deliver Message failure         | No state write      | No change; the next run re-reviews the same range        |
| Push Agent Branch failure                            | No change           | `error` (metadata); `consecutive_failures` unchanged     |

Issues created before a Deliver Message failure remain; the next run skips them through the fingerprint check. The fingerprint comes from the model, so that check lowers duplicates but does not guarantee none. `finalize_outcome_override` is ignored for `issue_create`. See [State delivery philosophy](../multi-branch-loops-design.md#state-delivery-philosophy) and [Retry Policy](../loop-engineering-design.md#retry-policy).

## Budget

`.loop/loop-budget.json` entry `code-review`: `max_runs_per_day: 2`, `max_tokens_per_day: 8000000`, `max_cost_usd_per_day: 15`, `max_attempts_per_run: 3`.

## Stop conditions

| Mechanism                           | Effect                                                                                                                                                                |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Checker REJECT and circuit breaker  | No Issue for an unsupported finding; repeated REJECT stops the loop                                                                                                   |
| `finalize_script` re-verification   | Drops findings unrelated to the range diff                                                                                                                            |
| `finalize_issue_limit` (3)          | Caps Issues per run                                                                                                                                                   |
| Fingerprint dedup (open and closed) | Prevents re-filing the same finding                                                                                                                                   |
| Budget                              | Caps runs, tokens, and cost per day                                                                                                                                   |
| **Pause**                           | A human disables the workflow during a large migration or incident: `gh workflow disable on-loop-code-review`                                                         |
| **Slow Down**                       | When more than 30% of the created Issues close as "not planned", lower `finalize_issue_limit` or widen the schedule interval                                          |
| **Kill**                            | Stop the loop when two consecutive weeks pass with created Issues left untouched (no fix, no close) while budget is spent, or when the "not planned" rate exceeds 50% |

## Operations

- **Create the label first.** The repository label `loop:code-review` must exist before the first run; Deliver Message labels every Issue with it.
- **Never remove the label from a created Issue.** The duplicate check lists Issues by this label, so an Issue without it no longer counts and the same finding can be filed again.
- **Do not add an intake label to `finalize_label_allowlist`.** `autofix`, `needs-triage`, and `triage:needs-info` raise Webhook events that start other loops (invariant 10 in [Design Invariants](../loop-engineering-design.md#design-invariants)). A bats test checks every caller. A human may add `autofix` to a single Issue later.
- **Check the "not planned" rate weekly.** Read it from the `loop:code-review` Issue list; no automatic count exists. Apply Slow Down or Kill from the table in [Stop conditions](#stop-conditions).
- **Review the cut findings.** Findings beyond `finalize_issue_limit` appear only in the step summary of the run, which lasts as long as the Actions log retention. Raise the limit when it is reached often.

### CLI version pinning

The built-in `code-review` skill ships inside the Claude Code CLI, so a CLI update can change the loop behavior silently. The caller pins `agent_cli_version: 2.1.318`. A repo-local Renovate regex manager in `.github/renovate.json` tracks that line; a package rule disables automerge for it, so a human reviews each version change.

## Implementation Checklist

Shared platform: [Multi-Branch — Shared platform checklist](../multi-branch-loops-design.md#shared-platform-checklist-all-loops).

- [x] `delivery: issue_create` (validation, `determine_outcome`, `resolve_state_write_mode`, Deliver Message)
- [x] Built-in range detect (`range_detect.sh`) and `target_json.from.since`
- [x] `agent_tool_denylist` input
- [x] `scripts/self/loop/render_code_review_issues.sh`
- [x] `on-loop-code-review.yaml` dogfood caller via `ci-loop-caller`
- [x] `.loop/loop-budget.json` entry `code-review`
- [x] Renovate regex manager for the pinned CLI version

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Loop Caller Inputs Reference](loop-caller-inputs-reference.md)
- [Loop Engineering Design](../loop-engineering-design.md)
- [Specification](../../../reference/specification.md)
