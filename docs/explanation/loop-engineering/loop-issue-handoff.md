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

## Autofix states (stage D and later, not implemented)

The autofix scheduled intake is not implemented. This table records the planned behavior so that the triage states and the autofix states stay consistent. Do not treat it as current behavior.

| ID  | State                                       | Trigger                                                       | Next state                                              |
| --- | ------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------- |
| A0  | Filed                                       | The code-review (L2) checker approves and re-verification passes | A1                                                   |
| A1  | Eligible                                    | The schedule picks it up (next run if over the limit)         | A2                                                      |
| A2  | Running                                     | (L1) the agent logs a fix plan                                | A1                                                      |
|     |                                             | (L2) the checker approves and a PR is created                 | A3                                                      |
|     |                                             | (L2) the checker rejects                                      | A1 (failure count +1 for the Issue; 3 failures lead to A5) |
| A3  | PR open (pending)                           | A human merges                                                | A6                                                      |
|     |                                             | A human closes the PR                                         | A4                                                      |
| A4  | Idle (PR closed, Issue open)                | A human comments on the Issue                                 | A1                                                      |
|     |                                             | A human closes the Issue                                      | A6                                                      |
| A5  | Stopped (circuit breaker)                   | State expires after 30 days, or a PR removes the state key    | A1                                                      |
| A6  | Done (Issue closed)                         | A human reopens the Issue                                     | A1 (when the eligibility conditions hold)               |

When an Issue is in A1 and carries the `autofix` label, the Webhook path handles it and the schedule no longer picks it up.
