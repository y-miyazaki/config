# Loop Workflow Design Doc Format

Unify the format of the per-loop design documents under `docs/explanation/loop-engineering/workflows/`, and add a base template for new loop workflows.

## Intent

- Human operations are under-documented. Only `loop-github-issue-triage-workflow-design.md` and `loop-github-issue-autofix-workflow-design.md` have a **User actions** section with state transitions. The other design documents describe the loop from the workflow's side only.
- Section names, order, and depth differ between documents (for example `Out of scope` vs `Out scope`, different positions of `Caller inputs`), which makes them hard to read and compare.
- New loop workflows have no base to copy from.

The document's main job is **coverage**: for every human operation or trigger, state which values change and whether anything follows. An agent (or a reviewer) must be able to use the document to find cases that nothing follows up.

## Goals

1. One base template, `workflows/loop-workflow-design-template.md`, that every loop design document follows.
2. A **User actions** table with a **Transition** column in every loop design document, including scheduled loops (where the human operations are the responses to the loop's output: merge, close, ignore, manual dispatch).
3. A closed catalog of human operations and state-bearing values that each document is checked against, so gaps are visible.
4. A **Unhandled cases** subsection: every operation the loop does not follow up is listed with a disposition, not omitted.
5. A short MUST rule in `/workspace/CLAUDE.md` so new and edited loop design documents follow the template.
6. Migrate the 11 existing design documents to the template.

## Non-goals

- No change to workflow behavior, scripts, or inputs. Migration moves and adds documentation only. Where documenting a case reveals a behavior gap, record it under **Unhandled cases** with the disposition `Follow-up`; do not fix it here.
- `workflows/loop-caller-inputs-reference.md` is a shared reference, not a per-loop design. It is out of the migration (my call).
- No new lint or Bats check for headings in this change (my suggestion for later: a heading-order check next to `test/bats/github-actions/workflow-header.bats`).
- No rewrite of existing prose beyond what the template needs (moving, renaming headings, adding the new sections).

## Anti-goals

- A template so heavy that authors fill sections with `None`. Optional sections are omitted, not stubbed.
- Duplicating state rules. State IDs and rule bodies live in one place; documents reference them.
- Documents that describe the happy path only.

## Template

### Document families

| Family                               | Documents                                                                                     | Difference                                                                                                                                      |
| ------------------------------------ | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Human-triggered / event entity loops | `github-issue-triage`, `github-issue-autofix`, `github-pr-revise`, `github-pr-review`         | Use **Intake paths**, **Caller shape**, and the contract sections (Detect / Skill / Delivery) instead of the Detect → Execute → Finalize triple |
| Scheduled detect loops               | `changelog`, `ci-sweeper`, `code-review`, `docs-updater`, `refactor`, `tech-debt`, `test-gap` | Use **Detect**, **Execute**, **Finalize**, **State**                                                                                            |

### Section order

`R` = required, `O` = optional (omit when it does not apply).

| #   | Section (H2)                                                                                                                                     | R/O | Content                                                                                        |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------ | --- | ---------------------------------------------------------------------------------------------- |
| 0   | Title (H1), one-line summary, Layer table, `Artifacts:` line, shared-keys link                                                                   | R   | Same header shape in every document                                                            |
| 1   | `Purpose`                                                                                                                                        | R   | What the loop does, the level (L1 / L2), what it never does. Behaviors to know as a short list |
| 2   | `Use cases`                                                                                                                                      | R   | Supported use cases. Each row: use case, trigger, outcome, **Transition** (state ID)           |
| 3   | `Out of scope`                                                                                                                                   | R   | Exact heading text                                                                             |
| 4   | `Intake paths`                                                                                                                                   | O   | Event family only: each path, its gating, who it handles                                       |
| 5   | `State model`                                                                                                                                    | R   | State IDs this loop uses and where they are defined (see below)                                |
| 6   | `User actions`                                                                                                                                   | R   | Table: User action / Loop response / Values changed / Result and next action / Transition      |
| 7   | `Unhandled cases`                                                                                                                                | R   | Table: Case / Why nothing follows / Disposition (`Accepted`, `Limitation`, `Follow-up`)        |
| 8   | `Failure and recovery`                                                                                                                           | R   | Per failure kind: how it is recorded, who acts, what they do, how the loop resumes             |
| 9   | `Caller inputs` (+ `Domain detect environment`)                                                                                                  | R   | Keys and defaults; shared keys link to the inputs reference                                    |
| 10  | Mechanics: `Detect` / `Execute` / `Finalize` (scheduled), or `Caller shape` / `Detect contract` / `Skill contract` / `Delivery contract` (event) | R   | Same names within a family                                                                     |
| 11  | `State delivery` / `Ledger` / `Operations`                                                                                                       | O   | Where state is stored, retry limits, circuit breaker, concurrency                              |
| 12  | `Implementation Checklist`                                                                                                                       | R   | Loop-specific items                                                                            |
| 13  | `References`                                                                                                                                     | R   |                                                                                                |

### State model

- Issue loops (triage, autofix): reuse the IDs in `loop-issue-handoff.md` (T0–T4, A0–A6). Do not copy rule bodies.
- Scheduled loops (my call) share one canonical table `S0–S5`, defined once in the template's `State model` section: S0 target detected, S1 PR/Issue open (pending), S2 merged / done, S3 closed without merge (idle), S4 ignored (left open), S5 stopped (circuit breaker). A scheduled loop's `State model` links to that table and adds only loop-specific rows with the suffix `S2a`, `S3a`, and so on. Rule bodies are not copied.
- Event loops without Issue state (`pr-revise`, `pr-review`) define their own table in `State model` with prefix `V` (pr-revise) and `W` (pr-review). Columns: ID / State / Trigger / Next state, the same as `loop-issue-handoff.md`.
- **Transition** is a real state change from one of these tables, never a free-text label. A row that changes no state uses `-`.

### Source of truth and gap dispositions

- When a design document and the workflow YAML / entry skill / scripts disagree, the implementation wins. The document is corrected. For every discrepancy, the builder also judges whether the implementation itself is wrong (a missing guard, a stuck state, a silent failure, or paths that behave inconsistently). When it is, the discrepancy is recorded under `Unhandled cases` with disposition `Follow-up` and a one-line reason. The builder does not change behavior. Loops marked "not yet run" are documented from the implementation and flagged `unverified on GitHub`.
- Dispositions: `Accepted` (the loop intentionally does nothing, with the reason), `Limitation` (a known constraint of the platform or engine, with the reason), `Follow-up` (should be handled; a person must decide). A row without a reason is not valid.
- The author may not close a gap as `Accepted` on their own when the case leaves a PR, Issue, or label stuck with no human path to recover. That case is `Follow-up` and is listed in the final report for the user to decide.

### Coverage rules (the checkable part)

For each document, the author (and a reviewing agent) walks two catalogs and confirms each item has a row in **User actions** or **Unhandled cases**.

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

State-bearing values catalog (each value must say which operation changes it, or that none does):

- Labels, marker comments, ACK reactions
- Run-log rows and their `outcome`
- State or ledger keys, retry counters, circuit breaker
- Concurrency group and queue
- Handoff artifact; branch and PR existence

An item applies when the loop reads or writes the object it names (for example, item 7 applies when the loop opens a PR or posts review threads; item 4 applies when the loop opens PRs). Skipped items are not silent: the `User actions` section ends with one line, `Not applicable: <item numbers> — <reason>`. A catalog item that applies but has no row is a gap and must be fixed in the document.

The **Values changed** column is what makes the gap check possible: a value that appears in **Caller inputs**, **State**, or **Detect** but never appears in **Values changed** of any row is suspect.

### User actions row shape

| Column                 | Rule                                                                            |
| ---------------------- | ------------------------------------------------------------------------------- |
| User action            | One action one row; written from the person's side                              |
| Loop response          | What runs (path, workflow, trigger) or `Nothing runs` and why                   |
| Values changed         | Exact label, marker, run-log outcome, or state key that changes; `None` if none |
| Result and next action | What the person sees and what they do next                                      |
| Transition             | State ID transition (`A3 -> A6`) or `-`                                         |

## Placement and rules

- Template: `docs/explanation/loop-engineering/workflows/loop-workflow-design-template.md` (kebab-case, matches the `docs/` naming rule). It contains the section skeleton and one-line guidance per section, not prose.
- `/workspace/CLAUDE.md` gets a new section **Loop workflow design docs (MUST)** (my call: root file because the user asked for CLAUDE.md and `docs/` has no scoped CLAUDE.md). It states: new or edited `workflows/loop-*-workflow-design.md` follows the template; **User actions** and **Unhandled cases** are required; Transition IDs come from `loop-issue-handoff.md` or the document's own `State model`; behavior-changing findings are recorded, not silently fixed.
- No sync targets are affected (`docs/` is hand-edited). `markdownlint-cli2` and `markdown-link-check` run in the Stop hook; they are not run manually.

## Migration plan (11 documents)

For each document:

1. Read the matching `on-loop-*.yaml` workflow and entry skill to list the real triggers and the state-bearing values.
2. Rename and reorder headings to the template. Fix heading typos (`Out scope`).
3. Add `State model`, `User actions`, `Unhandled cases`, `Failure and recovery`. Reuse existing material (for example the `pr-revise` Trigger UX and concurrency tables, the `ci-sweeper` run ledger and REJECT retry policy) instead of rewriting it.
4. Walk the two catalogs and record every gap.
5. Keep anchors stable, or grep `docs/`, `.github/`, `.apm/packages/`, and the repository root Markdown files for links to the 11 files and update every inbound link (for example `/workspace/.github/workflows/CLAUDE.md` links to `#concurrency-and-pr_push-landing` in `pr-revise`).

Scope notes (my calls): `loop-state-promote` has a workflow but no design document of its own. It is out of this change and not a twelfth document; if a scheduled loop's `State delivery` section depends on it, link to the workflow. `code-review` stays in the scheduled family; `github-pr-review` is the event family.

Order: triage and autofix first (already have User actions, validate the template against them), then `pr-revise`, `pr-review`, then the scheduled loops. After the template is validated on the first two, the remaining nine can be migrated in parallel.

## Verification

- Behavior is unchanged: the diff touches only `docs/` and `CLAUDE.md`.
- Per document: both catalogs walked; each gap is a row or an `Unhandled cases` entry.
- Link and Markdown checks come from the Stop hook output.
- Not verified by this change: that documented behavior matches a live GitHub run. Several loops are noted as not yet run (see `Stage E` in the autofix document).

## Left to the builder

- Exact wording of the template's one-line guidance.
- Loop-specific state row suffixes (`S2a`, ...).
- Whether a gap needs a `Follow-up` Issue reference; the builder lists them in the final report and does not file Issues.
