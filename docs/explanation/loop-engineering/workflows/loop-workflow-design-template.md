# Loop Workflow Design Template

Base template for every per-loop design document under `docs/explanation/loop-engineering/workflows/`. Copy the section skeleton, replace each guidance line with loop content, and omit optional sections that do not apply.

| Layer        | Document                                                                  |
| ------------ | ------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)              |
| Caller shell | [Loop Caller Reusable Workflow Design](../loop-caller-reusable-design.md) |
| Spec         | The design spec of this loop (link by title)                              |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                  |

**Artifacts:** `on-loop-<name>.yaml` · skill `<name>` · detect script · other loop-specific scripts

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

## How to use this template

- Keep the H2 names and order in the table. `R` means required; `O` means optional and is omitted when it does not apply, never stubbed with `None`.
- Write one-line guidance as content, not prose padding. Prefer tables for operations, states, and failures.
- State IDs and rule bodies live in one place. Reference them; do not copy them.
- When the document and the workflow YAML, entry skill, or scripts disagree, the implementation wins. Correct the document. For every such difference, also judge whether the implementation itself is wrong (a missing guard, a stuck state, a silent failure, or paths that behave inconsistently); when it is, record it under `Unhandled cases` as `Follow-up` with a one-line reason.
- Put loop-specific subsections (for example a rollout stage or deferred checks) as H3 under the nearest template H2, and keep their anchors.

### Section order

| #   | Section (H2)                                                                                                                                     | R/O | Content                                                                                        |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------ | --- | ---------------------------------------------------------------------------------------------- |
| 0   | Title (H1), one-line summary, Layer table, `Artifacts:` line, shared-keys link                                                                   | R   | Same header shape in every document                                                            |
| 1   | `Purpose`                                                                                                                                        | R   | What the loop does, the level (L1 / L2), what it never does; behaviors to know as a short list |
| 2   | `Use cases`                                                                                                                                      | R   | Each row: use case, trigger, outcome, Transition (state ID)                                    |
| 3   | `Out of scope`                                                                                                                                   | R   | Exact heading text                                                                             |
| 4   | `Intake paths`                                                                                                                                   | O   | Event family only: each path, its gating, who it handles                                       |
| 5   | `State model`                                                                                                                                    | R   | State IDs this loop uses and where they are defined                                            |
| 6   | `User actions`                                                                                                                                   | R   | Table: User action / Loop response / Values changed / Result and next action / Transition      |
| 7   | `Unhandled cases`                                                                                                                                | R   | Table: Case / Why nothing follows / Disposition (`Accepted`, `Limitation`, `Follow-up`)        |
| 8   | `Failure and recovery`                                                                                                                           | R   | Per failure kind: how it is recorded, who acts, what they do, how the loop resumes             |
| 9   | `Caller inputs` (+ `Domain detect environment`)                                                                                                  | R   | Keys and defaults; shared keys link to the inputs reference                                    |
| 10  | Mechanics: `Detect` / `Execute` / `Finalize` (scheduled), or `Caller shape` / `Detect contract` / `Skill contract` / `Delivery contract` (event) | R   | Same names within a family                                                                     |
| 11  | `State delivery` / `Ledger` / `Operations`                                                                                                       | O   | Where state is stored, retry limits, circuit breaker, concurrency                              |
| 12  | `Implementation Checklist`                                                                                                                       | R   | Loop-specific items                                                                            |
| 13  | `References`                                                                                                                                     | R   | Links by document title                                                                        |

### Document families

| Family                               | Documents                                                                                     | Mechanics headings                                                                       |
| ------------------------------------ | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Human-triggered / event entity loops | `github-issue-triage`, `github-issue-autofix`, `github-pr-revise`, `github-pr-review`         | `Intake paths`, `Caller shape`, `Detect contract`, `Skill contract`, `Delivery contract` |
| Scheduled detect loops               | `changelog`, `ci-sweeper`, `code-review`, `docs-updater`, `refactor`, `tech-debt`, `test-gap` | `Detect`, `Execute`, `Finalize`, `State`                                                 |

## Purpose

What the loop does, its level (L1 comments and labels only, or L2 opens PRs), and what it never does.

Behaviors to know:

- One short bullet per behavior a reader would otherwise miss.

## Use cases

| Use case              | Trigger                   | Outcome                | Transition |
| --------------------- | ------------------------- | ---------------------- | ---------- |
| Example: stale target | Daily schedule detects it | PR opened with the fix | S0 -> S1   |

## Out of scope

- What this loop deliberately does not do, one bullet each.

## Intake paths

Omit this section for scheduled loops. For each path, state the events, the gating rule, and which targets it handles.

- **Path name** (`event`, `workflow_dispatch`): who it handles and the gating rule (link to the intake gating section of [Loop Engineering Design](../loop-engineering-design.md)).

## State model

List the state IDs this loop uses and where they are defined. Do not copy rule bodies.

- Issue loops (triage, autofix): reuse the IDs in [Loop Issue Handoff](../loop-issue-handoff.md) (`T0`-`T4`, `A0`-`A6`).
- Scheduled loops: link to [Scheduled loop states](#scheduled-loop-states) and add only loop-specific rows with the suffix `S2a`, `S3a`, and so on.
- Event loops without Issue state: define a table with the columns ID / State / Trigger / Next state, using prefix `V` (pr-revise) or `W` (pr-review).

Transition is a real state change from one of these tables, never a free-text label. A row that changes no state uses `-`. A Transition may span several states (`A0 -> A1 -> A2 -> A3`) or branch (`T2 -> T1 / T2 / T3`). In Issue loops, rows for Issues that the handoff table does not track use `-`, and `State model` says why.

### Scheduled loop states

Scheduled loops share this table. Each document defines it only through this link.

| ID  | State                       | Trigger                                             | Next state       |
| --- | --------------------------- | --------------------------------------------------- | ---------------- |
| S0  | Target detected             | The scheduled detect job finds a target             | S1 / S4          |
| S1  | PR or Issue open (pending)  | The loop opens the PR or Issue                      | S2 / S3 / S5     |
| S2  | Merged or done              | A person merges the PR or resolves the Issue        | S0 (next target) |
| S3  | Closed without merge (idle) | A person closes the PR or Issue without merging     | S0 / S4          |
| S4  | Ignored (left open)         | A person does nothing and the output stays as it is | S2 / S3          |
| S5  | Stopped (circuit breaker)   | Consecutive failures reach the loop's limit         | S0 (after reset) |

## User actions

One row per person action, written from the person's side. For scheduled loops, the actions are the responses to the loop's output: merge, close, ignore, manual dispatch.

| User action                | Loop response                              | Values changed                                            | Result and next action                      | Transition |
| -------------------------- | ------------------------------------------ | --------------------------------------------------------- | ------------------------------------------- | ---------- |
| Example: merge the loop PR | Nothing runs; the next schedule re-detects | Ledger key for the target; run-log `outcome` is unchanged | The person sees the target gone from detect | S1 -> S2   |

| Column                 | Rule                                                                            |
| ---------------------- | ------------------------------------------------------------------------------- |
| User action            | One action, one row; written from the person's side                             |
| Loop response          | What runs (path, workflow, trigger) or `Nothing runs` and why                   |
| Values changed         | Exact label, marker, run-log outcome, or state key that changes; `None` if none |
| Result and next action | What the person sees and what they do next                                      |
| Transition             | State ID transition (`A3 -> A6`) or `-`                                         |

The section ends with one line when catalog items are skipped:

`Not applicable: <item numbers> — <reason>`

### Coverage catalogs

Walk both catalogs and confirm each item has a row in `User actions` or `Unhandled cases`. An item applies when the loop reads or writes the object it names. For example, item 7 applies when the loop opens a PR or posts review threads, and item 4 applies when the loop opens PRs. A skipped item is not silent: list it in the `Not applicable:` line. An item that applies but has no row is a gap and must be fixed in the document.

Human operations catalog:

1. Create, edit, or comment on an Issue or PR (including a comment answering a question)
2. Add or remove a label the loop reads or writes
3. Mention the bot (when the loop uses a mention token)
4. Merge a loop PR; close a loop PR without merging; delete the loop branch
5. Close or reopen the Issue
6. Push to the loop's branch before or while the loop runs (conflict)
7. Resolve a review thread
8. Start `workflow_dispatch` manually; re-run a failed run
9. Edit configuration (inputs, allowlist, state file) after a failure
10. Do nothing (leave the output as is)
11. Events caused by the loop itself or other bots (self-retrigger prevention)

State-bearing values catalog. Each value must say which operation changes it, or that none does:

- Labels, marker comments, ACK reactions
- Run-log rows and their `outcome`
- State or ledger keys, retry counters, circuit breaker
- Concurrency group and queue
- Handoff artifact; branch and PR existence

A value that appears in `Caller inputs`, `State`, or `Detect` but never in the `Values changed` column of any row is suspect.

## Unhandled cases

List every operation the loop does not follow up. Do not omit them.

| Case                                    | Why nothing follows                                    | Disposition |
| --------------------------------------- | ------------------------------------------------------ | ----------- |
| Example: person deletes the loop branch | The next run recreates the branch from the base branch | Accepted    |

Dispositions:

- `Accepted`: the loop intentionally does nothing; state the reason.
- `Limitation`: a known constraint of the platform or engine; state the reason.
- `Follow-up`: the case should be handled and a person must decide.

Every row has a reason; a row without one is not valid. A PR, Issue, or label that is stuck with no human recovery path is `Follow-up`, never `Accepted`.

## Failure and recovery

| Failure kind             | How it is recorded                                               | Who acts   | What they do                     | How the loop resumes                       |
| ------------------------ | ---------------------------------------------------------------- | ---------- | -------------------------------- | ------------------------------------------ |
| Example: agent job fails | Run-log `outcome` is `error`, `failure_stage` is `agent_execute` | Maintainer | Fix the cause and re-run the job | The next scheduled run picks the target up |

## Caller inputs

Keys and defaults specific to this loop. Shared keys link to [Loop Caller Inputs Reference](loop-caller-inputs-reference.md); do not repeat them.

### Domain detect environment

Environment variables the loop's detect script reads, with defaults. Omit when the loop has none.

## Detect

Scheduled family. What the detect job selects, its limits, and its output JSON. Event family uses `Caller shape`, `Detect contract`, `Skill contract`, and `Delivery contract` here instead.

## Execute

Scheduled family. What the agent job does, the checker role, and the REJECT policy.

## Finalize

Scheduled family. How the PR or Issue is created, the delivery outcome values, and what is recorded in the run log.

## State delivery

Optional. Where state is stored, retry limits, circuit breaker, and concurrency. Rename to `Ledger` or `Operations` when that fits the loop better.

## Implementation Checklist

- [ ] Loop-specific item, one per line.

## References

- Links by document title, for example [Loop Engineering Design](../loop-engineering-design.md) and [Loop Issue Handoff](../loop-issue-handoff.md).
