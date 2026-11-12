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

---

## Loop judgements go through the gate (MUST)

Applies when adding or changing any rule that decides whether a loop run proceeds, is skipped, or how an outcome is counted (`.github/**/loop-*`, `.github/actions/lib/loop/`, `.apm/packages/**/detect_*.sh`, `on-loop-*.yaml`). Background: Design Invariants 8 and 9 in [Loop Engineering Design](loop-engineering-design.md).

| Kind of judgement                                                                    | Put it in                                                    | Never in                                    |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------- |
| Run admission (entity state, actor trust, mention, pending, circuit breaker, budget) | The admission gate (`.github/actions/lib/loop/admission.sh`) | Job `if`, a detect script, finalize         |
| Facts about the entity (state, author, labels, linked PRs)                           | The detect script, returned as data                          | A skip decision inside the detect script    |
| Outcome handling (counter change, `pending` clear, prune eligibility)                | The single outcome mapping table in `lib/loop/outcome.sh`    | A per-action `case` on `OUTCOME`            |
| Self-retrigger filter (bot sender, event type, label name)                           | Job `if`, static and cheap only                              | Actor trust, mention, repository visibility |

Rules:

- Do not patch a symptom in the layer where it surfaced. Find the gate that owns the judgement and change it there; if no gate owns it, add the judgement to the gate, not beside it.
- One definition per concept: bot actor, trusted author association, open entity, and `skip_reason` each have exactly one definition. Do not add a second.
- Repository visibility is never a trust signal. Actor trust is `author_association` (MEMBER, OWNER, COLLABORATOR) on every repository.
- Every new skip condition adds a `skip_reason` value from the shared vocabulary and a Bats case that proves the run is skipped.
- Every new outcome adds a row to the outcome mapping table and a Bats case for the counter, `pending` and prune effect.
- Missing facts fail closed: a gate that cannot read a fact skips the run with a reason, never proceeds.
- When a design doc's `Unhandled cases` gains a `Follow-up` row, name the gate that should own the fix.
