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

Behaviors to know:

- The loop has no pending state: on APPROVE the cursor `last_sha` advances in the same run, and the next run reviews the next range whatever happens to the filed Issues.
- The filed Issues are the input of two other loops. The triage loop and the autofix loop pick up open `loop:code-review` Issues on their own schedules; the Issue states are in [Loop Issue Handoff](../loop-issue-handoff.md) (`T0`–`T4`, `A0`–`A6`).
- The agent branch exists only during the run: `loop-finalize` deletes it after delivery.

### Flow

1. **Detect** runs the [built-in range detect](#built-in-range-detect) because the caller sets no `detect_script`.
2. **Maker** runs the built-in `code-review` skill with `Last SHA` as the base commit and writes the verified findings as a JSON array to `.loop-code-review/findings.json` (an empty array when there are none).
3. **Checker** reads the range diff and approves only when every finding has evidence in that diff and a real failure path. Any other result is REJECT (`agent_unchanged_verdict: REJECT`).
4. **Push Agent Branch** pushes the agent branch. On APPROVE, `finalize_script` runs [the re-verification](#finalize_script-re-verification) and writes `issues.json`.
5. **Deliver Message** opens the Issues (see [Issue creation](#issue-creation)).
6. **Delete Agent Branch** removes the agent branch; the state is written ([State](#state)).

## Use cases

| Use case                                | Trigger                                                                                                                          | Outcome                                                                                          | Transition |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ---------- |
| Weekly review of merged changes         | Weekly `schedule` (Wednesday 09:00 UTC) or `workflow_dispatch`; files changed between the stored `last_sha` and `HEAD` on `main` | One Issue per verified finding, labeled `loop:code-review`, up to `finalize_issue_limit` (3)     | S0 -> S1a  |
| No duplicate Issue                      | A finding whose marker is already in an open or closed `loop:code-review` Issue                                                  | No Issue for a finding that already has an Issue (open or closed); the cursor still advances     | S0 -> S2a  |
| Hand the findings to triage and autofix | An open `loop:code-review` Issue that the loop filed                                                                             | The triage and autofix schedules pick it up (see [Loop Issue Handoff](../loop-issue-handoff.md)) | A0 -> A1   |

## Out of scope

- Code fixes in this loop. The autofix loop's daily schedule picks up open `loop:code-review` Issues on its own rules, and a human may add the `autofix` label to an Issue to start the Webhook path (see [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md#intake-paths))
- L1 observation phase (skipped; **L2 start**, kept small by `finalize_issue_limit: 3`)
- Pull request heads (`delivery: issue_create` allows integration targets only)
- Webhook triggers (the loop runs on `schedule` and `workflow_dispatch` only)

## State model

The loop uses the shared states from [Loop Workflow Design Template](loop-workflow-design-template.md#scheduled-loop-states) for its one target key, `integration:main` in `.loop/state-code-review.json` on `state_branch`. Delivery `issue_create` writes no pending state, so `S1`–`S4` do not apply; two rows replace them:

| ID  | State                         | Trigger                                                                                                     | Next state                                                                                                                     |
| --- | ----------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| S1a | Issues filed, range done      | Checker APPROVE, re-verification keeps at least one finding, and Deliver Message creates at least one Issue | S0 on the next tick (the next range). Each new Issue starts at `A0` and `T0` in [Loop Issue Handoff](../loop-issue-handoff.md) |
| S2a | Range reviewed, nothing filed | Checker APPROVE with no finding left after re-verification, duplicate removal, or the length check          | S0 on the next tick (the next range)                                                                                           |

The values that hold each state in this loop:

| State | Values in this loop                                                                                                                                                                 |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S0    | Range detect returns `skip: false`: files changed between `last_sha` (or `HEAD~10` when it is missing or unreachable) and `HEAD`, outside `.loop/`, the state file, and the run log |
| S1a   | `last_sha` = the detect `HEAD`; `outcome` `issue_created`; `consecutive_failures` `0`; new Issues carry `loop:code-review` and the marker `<!-- code-review:fp:<hash16> -->`        |
| S2a   | `last_sha` = the detect `HEAD`; `outcome` `unchanged`; `consecutive_failures` `0`                                                                                                   |
| S5    | `consecutive_failures` is 3 or more; every tick records run-log `skipped` with `skip_reason` `circuit_breaker`                                                                      |

A run that files nothing because of a checker `REJECT` or an error leaves the target in S0 with the same `last_sha`, so the next run reviews a larger range. Only `rejected` raises `consecutive_failures`; the third one moves the target to S5. Closing, reopening, or editing a filed Issue changes no value in this state file. Retry limits and resets are in [State delivery](#state-delivery).

## User actions

Each row is one action a person can take on the loop's output (the filed Issues) or on the loop, the loop response, and what the person sees next. Loop rows use the IDs in [State model](#state-model); Issue rows use the IDs in [Loop Issue Handoff](../loop-issue-handoff.md).

| User action                                                                                                     | Loop response                                                                                                                                                                                                  | Values changed                                                                                                                                                 | Result and next action                                                                              | Transition              |
| --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ----------------------- |
| Do nothing with a filed Issue (triage)                                                                          | The triage loop's daily schedule triages it (see [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md#intake-paths))                                                                     | Triage labels and one triage marker comment on the Issue                                                                                                       | Read the triage comment                                                                             | T0 -> T1 / T2 / T3 / T4 |
| Do nothing with a filed Issue (autofix)                                                                         | The autofix loop's daily schedule picks it up and opens a `Fixes #N` PR (see [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md#intake-paths))                                       | Autofix state under `integration:main#issue:<N>`; a PR labeled `loop-automation`                                                                               | Review and merge the autofix PR; the merge closes the Issue                                         | A0 -> A1 -> A2 -> A3    |
| Add `autofix` to a filed Issue                                                                                  | The autofix Webhook path runs for that Issue                                                                                                                                                                   | `autofix` label; autofix state as in the autofix row                                                                                                           | Review the autofix PR                                                                               | A1 -> A2                |
| Answer the question on a filed Issue that carries `triage:needs-info`                                           | The triage Webhook path (`issue_comment`) re-triages it per [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md#user-actions); this loop reads no comments                              | None in this loop                                                                                                                                              | See the triage document for comments in other triage states                                         | T2 -> T1 / T2 / T3      |
| Close a filed Issue (completed or not planned)                                                                  | Nothing runs in this loop. The duplicate check counts closed Issues, so the same finding is not filed again                                                                                                    | Issue state only                                                                                                                                               | Count "not planned" closes for the weekly check in [Operations](#operations)                        | A4 -> A6                |
| Reopen a closed filed Issue                                                                                     | Nothing runs in this loop. The autofix schedule can pick the Issue up again                                                                                                                                    | Issue state only                                                                                                                                               | See the autofix document                                                                            | A6 -> A1                |
| Remove `loop:code-review` from a filed Issue                                                                    | Nothing runs now. The next run no longer sees the Issue in the duplicate check, and triage and autofix no longer pick it up                                                                                    | Label only                                                                                                                                                     | The same finding can be filed again. Add the label back; close the Issue instead to stop work on it | -                       |
| Start `workflow_dispatch` (no inputs)                                                                           | Same as a scheduled tick; it waits in the concurrency group `loop-state-main`                                                                                                                                  | As for a tick: Issues and `last_sha`, or run-log `skipped` (`no_changes`, `circuit_breaker`, `budget`); only runs that start the agent count toward the budget | The daily cap is `2`                                                                                | S0 -> S1a               |
| Re-run a failed run from the Actions page                                                                       | Detect runs again against the current `main` and the current state                                                                                                                                             | As for a new tick                                                                                                                                              | Issues created before a Deliver Message failure are skipped by the duplicate check                  | -                       |
| Push to `main` while a run is queued or running                                                                 | The run reviews `last_sha..<detect HEAD>`; re-verification reads the range from `target_json`, not from the checkout                                                                                           | None beyond the run's own values                                                                                                                               | The next run reviews the push                                                                       | -                       |
| Pause the loop (`gh workflow disable on-loop-code-review`)                                                      | No run starts until the workflow is enabled again                                                                                                                                                              | None; `last_sha` stays                                                                                                                                         | After `gh workflow enable`, the next run reviews everything merged meanwhile                        | -                       |
| Reset the circuit breaker by a PR to `main` that edits `.loop/state-code-review.json`                           | Nothing runs on merge; the next tick reads the new state                                                                                                                                                       | `consecutive_failures` set to `0` (or the target key removed)                                                                                                  | The next tick reviews again. Fix the cause of the rejections first                                  | S5 -> S0                |
| Change `finalize_issue_limit`, the schedule, `.loop/loop-budget.json`, or other caller inputs by PR (Slow Down) | Nothing runs on merge. The next tick uses the new values                                                                                                                                                       | Caller inputs; `.loop/loop-budget.json` caps (they override caller `budget_*`)                                                                                 | Start `workflow_dispatch` to apply them now                                                         | -                       |
| Do nothing (no file changed since `last_sha`)                                                                   | Each tick runs range detect, which returns `skip: true`                                                                                                                                                        | Run-log `skipped`, `skip_reason` `no_changes`                                                                                                                  | -                                                                                                   | -                       |
| Commits and Issues that the loop or other loops create (state, run log, filed Issues)                           | Nothing runs: the workflow has only `schedule` and `workflow_dispatch` triggers, range detect excludes `.loop/`, and `loop:code-review` is not an intake label (the triage Webhook `issues` branch rejects it) | None                                                                                                                                                           | -                                                                                                   | -                       |

Not applicable: 3, 4, 6, 7 — the loop uses no mention token, opens no PR, and deletes its agent branch in the same run, so there is no loop PR, loop branch, or review thread to act on.

## Unhandled cases

| Case                                                                                        | Why nothing follows                                                                                                                                                                                                                                                                          | Disposition |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| The circuit breaker stops the loop                                                          | Nothing tells a person: the trip shows only as run-log `skipped` (`circuit_breaker`). The 30-day cooldown in `prune_targets.sh` runs only inside a finalize state write, which never happens while the breaker blocks the only target, so the stop lasts until a person edits the state file | Follow-up   |
| The maker agent exits without output (engine or credential failure)                         | `loop-execute` only warns on a non-zero maker exit; with no diff the verdict is `REJECT`, so the run records `rejected` and counts toward the circuit breaker instead of `error` (the first dogfood run, 2026-11-11, recorded `rejected` with `tokens_total` 0)                              | Follow-up   |
| Findings beyond `finalize_issue_limit`                                                      | The cut findings appear only in the step summary and are not carried over; the cursor advances past their range. The spec accepts this to keep each run small                                                                                                                                | Accepted    |
| A person edits a filed Issue body and removes the marker, or deletes or transfers the Issue | The duplicate check matches the marker in the bodies of labeled Issues in this repository only, so the same finding can be filed again                                                                                                                                                       | Limitation  |
| The model words the same defect with a different fingerprint                                | The fingerprint comes from the model, so the duplicate check lowers duplicates but does not guarantee none                                                                                                                                                                                   | Limitation  |
| A Deliver Message failure after some Issues were created                                    | No state is written, so the next run reviews the same range; the duplicate check skips the created Issues within the fingerprint limitation                                                                                                                                                  | Accepted    |
| The "not planned" rate, Slow Down, and Kill                                                 | No automatic count exists; a person applies the rules in [Stop conditions](#stop-conditions) by hand                                                                                                                                                                                         | Accepted    |
| A person pushes to `main` during a run                                                      | The range is fixed at detect; the next run covers the push                                                                                                                                                                                                                                   | Accepted    |

## Failure and recovery

| Failure kind                                            | How it is recorded                                                                                                     | Who acts   | What they do                                                                             | How the loop resumes                                                                    |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Range detect fails                                      | The `detect` job fails; no state write and no run-log row                                                              | Maintainer | Fix the cause (for example the checkout)                                                 | The next tick                                                                           |
| Checker `REJECT` (including no `findings.json`)         | Run-log `rejected`; state `outcome` `rejected`, `last_reject_reason`, `consecutive_failures` + 1; `last_sha` unchanged | Maintainer | Read the reason; adjust `agent_maker_instructions` or `agent_checker_instructions` by PR | The next tick reviews the same, larger range; the third `rejected` in a row moves to S5 |
| `finalize_script` fails closed or Deliver Message fails | Run-log `error` with `failure_stage`; the later `loop-finalize` steps are skipped, so no state is written              | Maintainer | Read the step summary and the error; fix the cause                                       | The next tick reviews the same range; `error` does not count toward the breaker         |
| Push Agent Branch fails                                 | Run-log `error`; state `outcome` `error` (metadata); `consecutive_failures` unchanged                                  | Maintainer | Fix the token or the branch rules                                                        | The next tick                                                                           |
| Circuit breaker open                                    | Run-log `skipped`, `skip_reason` `circuit_breaker` on every tick                                                       | Maintainer | Fix the cause, then reset `consecutive_failures` in `.loop/state-code-review.json` by PR | The next tick after the merge (S5 -> S0)                                                |
| Daily budget used up                                    | Run-log `skipped`, `skip_reason` `budget`                                                                              | Maintainer | Wait, or raise the cap in `.loop/loop-budget.json` by PR                                 | The next tick or `workflow_dispatch`                                                    |

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

## Detect

### Built-in range detect

The caller omits `detect_script`, so `loop-detect` runs `range_detect.sh`. See [Built-in range detect](loop-caller-inputs-reference.md#built-in-range-detect) for the output contract.

- It lists files changed between `last_sha` and `HEAD`, excluding `.loop/`, the resolved state file, and the run-log file. No changed file skips the run.
- `verifier_context` holds `<since>..<head>` and up to 100 changed file paths. The checker uses it to confirm the evidence lies in the range.
- When the stored `last_sha` is unreachable, the range falls back to `HEAD~10`.
- `target_json.from.since` carries `last_sha` to `finalize_script`.

## Execute

The maker runs the built-in `code-review` skill on the range and writes only `.loop-code-review/findings.json`; it cannot spawn sub-agents (`agent_tool_denylist: Agent`). The checker approves only when every finding has evidence in the range diff and a real failure path. A missing `findings.json` is no diff, so the verdict is `REJECT` (`agent_unchanged_verdict`). Up to `agent_loop_max_attempts` (3) Agent→Verify cycles run per run.

## Finalize

### `finalize_script` re-verification

`render_code_review_issues.sh` guards against a forged `APPROVE` (the verdict comes from the agent job).

- It acts only when `VERDICT` is `APPROVE`; any other verdict writes nothing and exits 0, so the state still records `rejected` and the circuit breaker works.
- It reads `.loop-code-review/findings.json` from the agent branch and keeps a finding only when its evidence lines overlap lines changed by `git diff <since> <ref>` in that file. The range comes from `TARGET_JSON`, never from the checkout or the state file.
- It drops findings whose title or body exceeds the length limit, and reports the dropped count in the step summary.
- It fails closed (exit 1, no `issues.json`) on a missing `from.since` or `from.ref`, an unreachable range, a `findings.json` that is not an array, or a malformed finding.

### Issue creation

Deliver Message validates `issues.json` (`[{title, body, fingerprint}]`) and then:

1. Computes the marker `<!-- code-review:fp:<hash16> -->`, where `hash16` is the first 16 hex characters of `sha256(loop_name + "\n" + fingerprint)`.
2. Drops findings whose marker appears in an open or closed Issue that carries every `finalize_label_allowlist` label.
3. Applies `finalize_issue_limit` to the remaining findings. The cut findings go to the step summary and are not carried over.
4. Sanitizes forged markers and mentions in each body, adds the marker and the Meta block, and creates the Issue with every `finalize_label_allowlist` label.

The write token for Issue creation is the GitHub App token that `loop-finalize` already uses; the agent job holds no write credential.

## State delivery

### State

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

### Budget

`.loop/loop-budget.json` entry `code-review`: `max_runs_per_day: 2`, `max_tokens_per_day: 8000000`, `max_cost_usd_per_day: 15`, `max_attempts_per_run: 3`.

### Stop conditions

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

### Retry limits and circuit breaker

| Value                     | Rule                                                                                                                                                                                                                                       |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `agent_loop_max_attempts` | Agent→Verify cycles inside one run (`3`); the last verdict decides the run outcome                                                                                                                                                         |
| `consecutive_failures`    | `loop-finalize` adds 1 on `rejected`, keeps it on `error`, and sets it to `0` on `issue_created` and `unchanged`                                                                                                                           |
| Circuit breaker           | `loop-detect` skips the target with `skip_reason` `circuit_breaker` when `consecutive_failures` is 3 or more                                                                                                                               |
| Cooldown                  | On a finalize state write, an `integration:*` key whose `outcome` is `rejected` or `pr_closed` and whose `last_run` is older than 30 days gets `consecutive_failures` `0`; no state write happens while the breaker blocks the only target |
| Concurrency               | Workflow group `loop-state-main` (`cancel-in-progress: false`, `queue: max`), shared with the other scheduled loops and `on-loop-state-promote`                                                                                            |

## Operations

- **The label is created on demand.** Every loop label path (`issue_create`, message labels, and `pr_labels`) first creates the labels that do not exist (`ensure_repo_labels`, including `loop:code-review`), using the `issues: write` or `pull-requests: write` permission the workflow already has. An existing label is left unchanged, and a run that files nothing creates no label. Never remove the label from the allowlist: the duplicate lookup depends on it.
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
- [Loop Issue Handoff](../loop-issue-handoff.md)
- [Specification](../../../reference/specification.md)
