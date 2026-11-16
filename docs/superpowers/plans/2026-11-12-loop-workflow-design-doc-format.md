# Loop Workflow Design Doc Format Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a base template for loop workflow design documents and migrate the 11 existing documents under `docs/explanation/loop-engineering/workflows/` to it, with human operations and state transitions covered.

**Architecture:** One template file holds the section order, the shared scheduled-loop state table (`S0–S5`), and the two coverage catalogs. A short MUST section in `/workspace/CLAUDE.md` points to it. Each existing document is reorganized to the template and gains `State model`, `User actions`, `Unhandled cases`, and `Failure and recovery`, sourced from the workflow YAML and scripts.

**Tech Stack:** Markdown only. Checks: `grep`, plus the Stop hook (`markdownlint-cli2`, `markdown-link-check`) which is not run manually.

**Spec:** `docs/superpowers/specs/2026-11-12-loop-workflow-design-doc-format-design.md`

## Global Constraints

- Docs only. No change to workflows, scripts, inputs, or behavior. Findings that look like behavior bugs go to `Unhandled cases` as `Follow-up`.
- File names kebab-case. Template path: `docs/explanation/loop-engineering/workflows/loop-workflow-design-template.md`.
- Exact H2 names: `Purpose`, `Use cases`, `Out of scope`, `Intake paths` (event family, optional), `State model`, `User actions`, `Unhandled cases`, `Failure and recovery`, `Caller inputs`, `Implementation Checklist`, `References`.
- `User actions` columns, in order: `User action`, `Loop response`, `Values changed`, `Result and next action`, `Transition`. The section ends with `Not applicable: <item numbers> — <reason>` when catalog items are skipped.
- `Unhandled cases` columns: `Case`, `Why nothing follows`, `Disposition` (`Accepted` | `Limitation` | `Follow-up`); every row has a reason. A stuck PR, Issue, or label with no human recovery path is `Follow-up`, never `Accepted`.
- State IDs: Issue loops reuse `T0–T4` / `A0–A6` from `loop-issue-handoff.md`; scheduled loops link the template's `S0–S5` and add `S2a`-style rows; `pr-revise` uses `V`, `pr-review` uses `W`. `Transition` is a real state change or `-`.
- When a document and the implementation disagree, the implementation wins.
- `loop-caller-inputs-reference.md` and `loop-state-promote` are out of scope.
- Do not run `markdownlint-cli2`, `markdown-link-check`, or `prettier` manually (Stop / PostToolUse hooks run them). Do not commit unless the user asks.

## Review Focus

- A scheduled loop whose human operations are only "responses to its PR" still has a `User actions` table (not omitted).
- A value in `Caller inputs` / state / detect that no `Values changed` cell mentions (silent state).
- A renamed H2 that breaks an inbound anchor (`#concurrency-and-pr_push-landing` and others).
- A `Transition` cell that names a state ID not defined in `State model` or the linked table.
- `Accepted` dispositions without a reason, or covering a stuck state.

---

### Task 1: Base template

**Files:**

- Create: `docs/explanation/loop-engineering/workflows/loop-workflow-design-template.md`

**Interfaces:**

- Produces: the H2 section order and names (Global Constraints); the `S0–S5` table anchor `#scheduled-loop-states`; the two catalogs under `#coverage-catalogs`; `User actions` and `Unhandled cases` row shapes. Tasks 3–6 link to these anchors.

- [ ] **Step 1: Write the check first.** Create `tmp/check-workflow-docs.sh` (temp files go to `tmp/`) that, for every `docs/explanation/loop-engineering/workflows/loop-*-workflow-design.md` and the template, prints `<file> missing <H2>` for each required H2 (`Purpose`, `Use cases`, `Out of scope`, `State model`, `User actions`, `Unhandled cases`, `Failure and recovery`, `Caller inputs`, `Implementation Checklist`, `References`) using `grep -q "^## $h"`.
- [ ] **Step 2: Run it** with `bash tmp/check-workflow-docs.sh`. Expected: many `missing` lines for the existing 11 documents.
- [ ] **Step 3: Write the template** from the spec's "Template" section: header block (title, summary, Layer table, `Artifacts:` line), the section order table with one-line guidance per section (no prose), both families' mechanics headings, the `Scheduled loop states` table (`S0` detected, `S1` PR/Issue open, `S2` merged / done, `S3` closed without merge, `S4` ignored, `S5` stopped by circuit breaker, columns ID / State / Trigger / Next state), the `Coverage catalogs` (11 human operations, state-bearing values, applicability rule, `Not applicable:` line), and the row shapes for `User actions` and `Unhandled cases` with the disposition rules. Use a one-row example for each table.
- [ ] **Step 4: Verify** that `bash tmp/check-workflow-docs.sh` reports nothing for the template file, and that the Stop hook output for the template is clean.

### Task 2: CLAUDE.md rule

**Files:**

- Modify: `/workspace/CLAUDE.md` (add a section after `## Hook-covered tools (MUST)`, before `## Conventions`)

**Interfaces:**

- Consumes: template path and the `User actions` / `Unhandled cases` requirement (Task 1).

- [ ] **Step 1: Add `## Loop workflow design docs (MUST)`** with: scope (`docs/explanation/loop-engineering/workflows/loop-*-workflow-design.md`, new or edited); follow `loop-workflow-design-template.md`; `User actions` (with `Values changed` and `Transition`) and `Unhandled cases` are required; Transition IDs come from `loop-issue-handoff.md`, the template's `S0–S5`, or the document's own `State model`; behavior-changing findings are recorded as `Follow-up`, not fixed in the doc change. Keep to the style of neighboring sections (short table or bullets, under 15 lines).
- [ ] **Step 2: Verify** with `grep -n "Loop workflow design docs (MUST)" /workspace/CLAUDE.md`. Expected: one match. The link target exists: `ls docs/explanation/loop-engineering/workflows/loop-workflow-design-template.md`.

### Task 3: Validate the template on triage and autofix

**Files:**

- Modify: `docs/explanation/loop-engineering/workflows/loop-github-issue-triage-workflow-design.md`
- Modify: `docs/explanation/loop-engineering/workflows/loop-github-issue-autofix-workflow-design.md`
- Modify (only if the template needs a fix): `loop-workflow-design-template.md`

**Interfaces:**

- Consumes: template sections, `T0–T4`, `A0–A6` in `loop-issue-handoff.md`.

- [ ] **Step 1: Read the implementation** for each loop: `.github/workflows/on-loop-github-issue-triage.yaml` and `on-loop-github-issue-autofix.yaml`, the entry skill `SKILL.md`, and the detect script. List triggers and state-bearing values.
- [ ] **Step 2: Reorganize** each document to the template order. Rename headings to the exact names (`Out of scope`, `Use cases`). Add `State model` (link to `loop-issue-handoff.md` IDs), add `Values changed` to the existing `User actions` table, add `Unhandled cases` and `Failure and recovery` (reuse the existing `Residual risks`, circuit breaker, and `triage:failed` material).
- [ ] **Step 3: Walk both catalogs** (spec "Coverage rules"). Every applicable item has a `User actions` row or an `Unhandled cases` row; add the `Not applicable:` line.
- [ ] **Step 4: Verify** `bash tmp/check-workflow-docs.sh` reports nothing for these two files; every `Transition` ID appears in `loop-issue-handoff.md`: run `grep -o '[TA][0-9]' <doc> | sort -u` and compare with the IDs defined there.
- [ ] **Step 5: Template fixes.** If these two documents exposed a section that does not fit, fix the template and note the change in the final report; do not start Task 4 before the template is settled.

### Task 4: pr-revise and pr-review

**Files:**

- Modify: `docs/explanation/loop-engineering/workflows/loop-github-pr-revise-workflow-design.md`
- Modify: `docs/explanation/loop-engineering/workflows/loop-github-pr-review-workflow-design.md`

**Interfaces:**

- Consumes: template; defines `V0..` (pr-revise) and `W0..` (pr-review) in each document's `State model`.

- [ ] **Step 1: Read the implementation:** `on-loop-github-pr-revise.yaml`, `on-loop-github-pr-review.yaml`, entry skills, `push_target.sh`, `render_review.sh`. For pr-revise list: mention token, ACK reaction, comment batching, concurrency group, `pr_push` conflict. For pr-review list: open / `synchronize` / reopen events, marker, delivery.
- [ ] **Step 2: Reorganize** to the event-family template (`Intake paths`, `Caller shape`, `Detect contract`, `Skill contract`, `Delivery contract`). Keep the heading `Concurrency and pr_push landing` (anchor referenced from `.github/workflows/CLAUDE.md`).
- [ ] **Step 3: Add** `State model` (`V` / `W` tables), `User actions` (pr-revise: mention, mention without a trigger, edit/delete comment, push to the PR branch while running, resolve thread by hand, close PR, mention while queued; pr-review: open, push, reopen, draft toggle, re-request, no action), `Unhandled cases`, `Failure and recovery`.
- [ ] **Step 4: Verify** `bash tmp/check-workflow-docs.sh` clean for both; `grep -rn "concurrency-and-pr_push-landing" /workspace --include=*.md` still resolves to an existing heading.

### Task 5: Scheduled loops, group A (changelog, refactor, docs-updater, tech-debt)

**Files:**

- Modify: the four matching `docs/explanation/loop-engineering/workflows/loop-*-workflow-design.md` files

**Interfaces:**

- Consumes: template `#scheduled-loop-states` (`S0–S5`).

- [ ] **Step 1: For each document**, read the `on-loop-<name>.yaml` workflow, the entry skill, the detect script, and the ledger/state script. List triggers, state keys, retry counters, circuit breaker, and the output PR or report.
- [ ] **Step 2: Reorganize** to the scheduled-family order. These four already share `Detect / Execute / Finalize / State delivery`; keep that content and move it, do not rewrite it.
- [ ] **Step 3: Add** `State model` (link to `S0–S5`, add `S2a`-style rows only for real differences, for example `tech-debt` report-only output), `User actions` (merge / close / ignore the output, manual `workflow_dispatch`, edit inputs after failure, push to the loop branch, do nothing), `Unhandled cases`, `Failure and recovery`, and the `Not applicable:` line.
- [ ] **Step 4: Verify** `bash tmp/check-workflow-docs.sh` clean for the four files; each `Transition` ID is `S0–S5`, an `S?a` row defined in the same document, or `-`.

### Task 6: Scheduled loops, group B (ci-sweeper, code-review, test-gap)

**Files:**

- Modify: the three matching `loop-*-workflow-design.md` files

**Interfaces:**

- Consumes: template `#scheduled-loop-states`.

- [ ] **Step 1: Read the implementation** as in Task 5. Special inputs: `ci-sweeper` run ledger, REJECT retry policy, `detect_pr_denylist`, PR mode; `code-review` range detect, issue creation, budget, stop conditions; `test-gap` ledger, circuit breaker, observation trigger.
- [ ] **Step 2: Reorganize.** `ci-sweeper` and `test-gap` keep their extra sections (`Failure contexts`, `End-to-end flows`, `Ledger`, `Operations and status`) after the mandatory ones, placed in template slot 11; `code-review` gets the scheduled-family headings it lacks (`Detect` / `Execute` / `Finalize`) by regrouping existing sections (`Built-in range detect`, `finalize_script re-verification`).
- [ ] **Step 3: Add** `State model`, `User actions`, `Unhandled cases`, `Failure and recovery`, and the `Not applicable:` line. For `code-review`, include the human response to the Issues it files (these feed triage and autofix: reference `T0` / `A0`).
- [ ] **Step 4: Verify** `bash tmp/check-workflow-docs.sh` clean for the three files; Transition IDs defined (as in Task 5).

### Task 7: Link sweep and final report

**Files:**

- Modify: any file that links to a renamed heading (found by the sweep)

- [ ] **Step 1: Sweep inbound links.** `grep -rnE "loop-(changelog|ci-sweeper|code-review|docs-updater|github-issue-autofix|github-issue-triage|github-pr-review|github-pr-revise|refactor|tech-debt|test-gap)-workflow-design\.md#" /workspace --include=*.md --include=*.yaml --include=*.sh --exclude-dir=node_modules --exclude-dir=.git`. For each anchor, confirm a matching heading exists in the target (`grep -n "^#.*<heading text>" <target>`). Fix any broken anchor by editing the link (or restoring the heading if it is referenced from `.github/workflows/CLAUDE.md`).
- [ ] **Step 2: Run the final structure check** `bash tmp/check-workflow-docs.sh`. Expected: no output.
- [ ] **Step 3: Collect gaps.** List every `Follow-up` row across the 11 documents (`grep -rn "Follow-up" docs/explanation/loop-engineering/workflows/`).
- [ ] **Step 4: Final report** to the user in the AGENTS.md Completion form (Implementation / Verification / Risks). Include: the list of `Follow-up` gaps for the user to decide; what was not verified (live GitHub behavior; hook results are read from the Stop hook output, not re-run); sibling-pattern search result (documents or headings in `loop-engineering/` outside `workflows/` that use the old heading names, and their disposition).
- [ ] **Step 5: Clean up** `tmp/check-workflow-docs.sh` if it is not meant to be kept (ask the user before keeping it as a repo check).
