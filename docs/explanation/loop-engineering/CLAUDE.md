# CLAUDE.md

Behavioral rules for `docs/explanation/loop-engineering/**`. Directory-scoped maintainer rules, hand-authored and repo-owned.

Design background: [Loop Engineering Design](loop-engineering-design.md).

---

## Loop workflow design docs (MUST)

Applies when creating or editing `workflows/loop-*-workflow-design.md`.

- Follow [Loop Workflow Design Template](workflows/loop-workflow-design-template.md) (section order and families).
- `User actions` (with `Values changed` and `Transition` columns) and `Unhandled cases` are required.
- Transition IDs come from [Loop Issue Handoff](loop-issue-handoff.md), the template's `S0–S5` (Scheduled loop states), or the document's own `State model`.
- Behavior-changing findings found while documenting are recorded as `Follow-up`; do not fix them in the doc change.
- When the design document and the implementation disagree, the implementation is the baseline and the document is corrected. Also judge whether the implementation is wrong, and record a `Follow-up` row when it is (full rule: the template's "How to use this template" section).
