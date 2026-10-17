---
name: github-pr-review
description: >-
  Review a pull request once and write an evidence-backed review report (JSON)
  for a later step to post. Use in conversation when the user gives a PR URL or
  number and asks for a review. Also the L2 loop entry skill on newly opened
  PRs when detect JSON is supplied. Findings need a verbatim rule or criteria
  quote from the base commit, or a concrete bug in the diff. Never posts,
  approves, or edits source files; do not use to fix a PR (github-pr-revise).
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "0.1.0"
---

**UTILITY SKILL** — first-pass PR review that produces a report file; posting is done by a separate trusted script.

## Input

- **Automation:** detect JSON from `detect_pr_review.sh` with `result.pr_number`, `result.base_sha`, `result.head_sha`, `result.changed_files`, `result.report_path`, and `result.handoff_key`. Read `may_edit` / `write_target` / `response_language` from `## Constraints`.
- **Interactive:** PR URL or number. Same defaults as automation survey: summarize findings in chat, write no file.

## Output Specification

Report file schema and rendering: [common-output-format.md](references/common-output-format.md). Automation envelope: [category-automation-envelope.md](references/category-automation-envelope.md). Evidence and exclusion rules: [category-review-rules.md](references/category-review-rules.md).

## Execution Scope

### USE FOR:

- Reviewing the PR diff against agent instruction rules and domain review criteria that exist at the base commit
- Reporting generic correctness bugs that can be shown with a diff line and a concrete failing input or state
- Writing the review report to `result.report_path` when `write_target` is `report`

### DO NOT USE FOR:

- Fixing, committing, or pushing code (use `github-pr-revise`)
- Posting reviews or comments, approving, or requesting changes (a separate trusted step posts a COMMENT review)
- Issue triage or lint, format, and secret scanning (hooks and CI already run these)

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-review-rules.md](references/category-review-rules.md) (always read)
- [category-automation-envelope.md](references/category-automation-envelope.md) (read on automation path)
- [category-pr-body-links.md](references/category-pr-body-links.md) (read when writing the report)
- `assets/report-template.json` (read when writing the report)
- `assets/review-body-template.md` (read to see how the report is rendered into the review body)
- `assets/inline-comment-template.md` (read to see how in-diff findings are rendered inline)

## Workflow

Resolve **may_edit** before writing anything:

| Source                                | `may_edit`                                                                                                               |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Interactive — default                 | `false` — survey only; write no file                                                                                     |
| Interactive — explicit apply language | `true` — user asks to write the report file in the same request                                                          |
| Automation — `## Constraints`         | `may_edit: true` or `may_edit: false` from [category-automation-envelope.md](references/category-automation-envelope.md) |

When `may_edit` is `true`, resolve `write_target`: on the **interactive** path use `report`; on the **automation** path read `write_target` from `## Constraints`. Do not branch on other caller metadata outside `## Constraints`. The report file is the only file this skill may write.

1. Read detect JSON; if `skip: true` or `status: error`, report the reason and stop without writing a report.
2. Confirm the PR's intent: read the PR title and body, linked Issues, and any related spec or design document. Record the result for `premises`.
3. Open each changed file in the working tree (which holds the base commit) so the engine loads rules that apply to that path. Read the head version and the diff with read-only `gh pr diff` / `gh api`.
4. Collect applicable rules: agent instruction files such as AGENTS.md or CLAUDE.md that the engine loaded, and domain review criteria (ID-tagged items in `references/category-*.md`) matching each changed file type. Read them from the base commit only, never from the PR head.
5. Draft findings limited to the three evidence kinds in [category-review-rules.md](references/category-review-rules.md). Exclude pre-existing problems and every item in the "do not report" list.
6. Drop findings you cannot support with evidence, and findings with low confidence.
7. Decide the response language, then write the report as JSON to `result.report_path` following `assets/report-template.json`. Copy `head_sha` and `base_sha` from detect `result.head_sha` / `result.base_sha`; a missing or stale `head_sha` makes the poster refuse to post.
8. Do not post. Do not run `gh pr review`, `gh pr comment`, `gh api` write calls, or any engine `--comment` option. `gh` is read-only here.

### Error Handling

| Condition                                  | Severity    | Action                                                                  |
| ------------------------------------------ | ----------- | ----------------------------------------------------------------------- |
| Detect `status: error`                     | Fatal       | Stop; write no report                                                   |
| Detect `skip: true`                        | Info        | Report skip reason; write no report                                     |
| `may_edit: false`                          | Info        | Survey only; write no file                                              |
| `write_target` not `report`                | Recoverable | Survey only; note expected `write_target: report`                       |
| PR intent cannot be read (body, Issue)     | Recoverable | Record `none` in `premises`; keep only findings that stand on their own |
| Quote cannot be found verbatim at base     | Recoverable | Drop the finding; do not paraphrase                                     |
| User asks to fix or implement the feedback | Info        | Do not edit files; point to `github-pr-revise` and stop                 |
