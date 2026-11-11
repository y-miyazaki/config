# Loop Issue Handoff

State transitions of one Issue that the code-review loop filed, as it moves through the triage loop and the autofix loop. Each workflow design document references these transition IDs from its User actions section.

Triage is advisory and does not feed autofix, so the triage states and the autofix states move independently. The rule bodies live in one place each: the lister conditions are in [Issue Triage Workflow Design](workflows/loop-github-issue-triage-workflow-design.md#intake-paths), and the gating rules are in [Loop Engineering Design](loop-engineering-design.md#intake-gating-self-retrigger-prevention). This table references them and does not repeat them.

## Triage states

Current behavior. The triage loop is described in [Issue Triage Workflow Design](workflows/loop-github-issue-triage-workflow-design.md).

| ID  | State                                           | Trigger                                                                  | Next state               |
| --- | ----------------------------------------------- | ------------------------------------------------------------------------ | ------------------------ |
| T0  | Not triaged (lister conditions)                 | The daily schedule picks it up (per-run limit in [Intake paths](workflows/loop-github-issue-triage-workflow-design.md#intake-paths))                       | T1 / T2 / T3 / T4        |
| T1  | `triage:ready`                                  | A human removes `triage:ready` and comments after the marker comment     | T0                       |
| T2  | `triage:needs-info`                             | A human comments (Webhook)                                               | Re-triage -> T1 / T2 / T3 |
| T3  | `triage:failed`                                 | A human removes the label and starts `workflow_dispatch`                 | Re-triage                |
| T4  | Low confidence (still `needs-triage`, marker present) | A human comments after the marker comment                          | T0                       |
|     | The agent failed (no label or comment applied)  | The next run (the retry limit in [Intake paths](workflows/loop-github-issue-triage-workflow-design.md#intake-paths) can exclude the Issue)    | T0                       |

## Autofix states

The conditions for A1 are in [Issue Autofix Workflow Design](workflows/loop-github-issue-autofix-workflow-design.md#intake-paths). The table is split by what exists today.

### Stage D (L1): current behavior

The scheduled `loop-scheduled` job moves an Issue only between A1 and A2 (the code-review loop performs A0).

| ID  | State    | Trigger                                                                                                          | Next state |
| --- | -------- | ---------------------------------------------------------------------------------------------------------------- | ---------- |
| A0  | Filed    | The code-review (L2) checker approves and re-verification passes                                                 | A1         |
| A1  | Eligible | The schedule picks it up (next run if over `detect_max_targets`)                                                  | A2         |
| A2  | Running  | (L1) The agent logs a fix plan (see [Intake paths](workflows/loop-github-issue-autofix-workflow-design.md#intake-paths))              | A1         |

### Stage E and later (not implemented)

Stage E promotes the schedule to L2 and aligns the Webhook key with the schedule key (see [Stage E](workflows/loop-github-issue-autofix-workflow-design.md#stage-e-not-implemented)). The states below are planned for the scheduled path. Do not treat them as current behavior for the schedule.

The Webhook path with the `autofix` label already creates PRs today, but it uses a different key. A person can move such an Issue through A3, A4 and A6 now, and the PR rules apply. The per-key circuit breaker (A5) and the A2 to A3 move by the schedule are not implemented.

| ID  | State                        | Trigger                                                       | Next state                                                 |
| --- | ---------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------- |
| A2  | Running                      | (L2) The checker approves and a PR is created                 | A3                                                         |
|     |                              | (L2) The checker rejects                                      | A1 (failure count +1 for the Issue; 3 failures lead to A5) |
| A3  | PR open (pending)            | A human merges                                                | A6                                                         |
|     |                              | A human closes the PR                                         | A4                                                         |
| A4  | Idle (PR closed, Issue open) | A human comments on the Issue                                 | A1                                                         |
|     |                              | A human closes the Issue                                      | A6                                                         |
| A5  | Stopped (circuit breaker)    | State expires after 30 days, or a PR removes the state key    | A1                                                         |
| A6  | Done (Issue closed)          | A human reopens the Issue                                     | A1 (when the eligibility conditions hold)                  |

When an Issue is in A1 and carries the `autofix` label, the Webhook path handles it and the schedule no longer picks it up.
