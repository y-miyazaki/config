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

---

## Script and function naming (MUST)

Applies to scripts under `.github/actions/**/lib/` and `.github/actions/lib/loop/`. The file stem tells the role, and the function prefix tells the file, so `grep` finds every judgement of one kind.

| File stem                          | Role                                                                         | Rule                                                                                         |
| ---------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `admission.sh`                     | The gate: every decision whether a run proceeds or is skipped                | Only `.github/actions/lib/loop/admission.sh`; functions start with `admission_`              |
| `detect.sh`                        | Collects facts and builds the target set; makes no shared admission decision | `loop-detect/lib`, `loop-entity-detect/lib`; skill scripts are `detect_<loop>.sh`            |
| `outcome.sh`                       | Maps an outcome to its effect (counter, prune); the one outcome table        | Only `.github/actions/lib/loop/outcome.sh`; functions start with `outcome_`                  |
| `run.sh`                           | Action entry point; orchestrates, decides nothing itself                     | One per action, `<action>/lib/run.sh`                                                        |
| `check_*.sh`                       | Validates inputs or a contract and returns a status; no side effects         | New validators use `check_`; existing `validate_*.sh` are renamed when they are next changed |
| `push_race.sh`, `state_pr.sh`, ... | One mechanism per file, named for the mechanism                              | Functions start with the file stem (`push_race_`, `state_pr_`)                               |

Rules:

- A function in a shared `lib/loop/<stem>.sh` file starts with `<stem>_`. `main` is the only exception. A new or renamed function that does not follow this is rejected in review.
- A run or skip decision outside `admission.sh` is a defect (see Loop judgements go through the gate). A function named `admission_*` is the only kind of function that returns an admit or skip decision.
- Facts are named for what they read (`detect_*`, `read_*`), decisions for what they refuse (`admission_*`), effects for what they write (`write_*`, `deliver_*`).
- Not yet renamed (rename when the file is next changed, one file per change): `build_constraints.sh`, `created_by.sh`, `deliver_*.sh`, `edit_paths.sh`, `ensure_labels.sh`, `handoff.sh`, `loop_message.sh`, `loop_meta.sh`, `redact.sh`, `target_slug.sh`, `text.sh`, `trigger_thread.sh`, `validate_loop_write_contract.sh`, `verifier_context.sh`.

Gate map (`.github/actions/lib/loop/admission.sh`):

| Function                                                           | Decides                                                                |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| `admission_evaluate`                                               | Run admission from `result.gate`, in one fixed order (the entry point) |
| `admission_actor_is_bot`                                           | The one bot definition                                                 |
| `admission_actor_trusted`                                          | Trusted author association, on every repository                        |
| `admission_budget_exceeded`                                        | Daily run and token budget                                             |
| `admission_circuit_breaker_open`                                   | Circuit breaker with the 30-day half-open window                       |
| `admission_read_budget_limits`, `admission_read_budget_cost_limit` | Budget caps read for the budget check                                  |
| `admission_result`                                                 | Builds the `{admit, skip_reason, detail}` object                       |
