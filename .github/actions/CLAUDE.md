@../workflows/CLAUDE.md

# CLAUDE.md

Behavioral rules for `.github/actions/**`. The rules of `.github/workflows/CLAUDE.md` apply here too (imported above). This file adds the loop-engineering code rules; design background: [Loop Engineering Design](../../docs/explanation/loop-engineering/loop-engineering-design.md).

---

## Loop judgements go through the gate (MUST)

Applies when adding or changing any rule that decides whether a loop run proceeds, is skipped, or how an outcome is counted (`.github/**/loop-*`, `.github/actions/lib/loop/`, `.apm/packages/**/detect_*.sh`, `on-loop-*.yaml`). Background: Design Invariants 8 and 9 in [Loop Engineering Design](../../docs/explanation/loop-engineering/loop-engineering-design.md).

| Kind of judgement                                                                                                                       | Put it in                                                    | Never in                                        |
| --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------- |
| Run admission (entity state, actor trust, mention, pending, circuit breaker, budget)                                                    | The admission gate (`.github/actions/lib/loop/admission.sh`) | Job `if`, a detect script, finalize             |
| Facts about the entity (state, author, labels, linked PRs)                                                                              | The detect script, returned as data                          | A skip decision inside the detect script        |
| Outcome handling (counter change, `pending` clear, prune eligibility)                                                                   | The single outcome mapping table in `lib/loop/outcome.sh`    | A per-action `case` on `OUTCOME`                |
| Self-retrigger and abuse filter (bot sender, event type, label name; author association or mention only as a strict subset of the gate) | Job `if`, static and cheap only                              | A bypass of a gate check, repository visibility |

Rules:

- Do not patch a symptom in the layer where it surfaced. Find the gate that owns the judgement and change it there; if no gate owns it, add the judgement to the gate, not beside it.
- One definition per concept: bot actor, trusted author association, open entity, and `skip_reason` each have exactly one definition. Do not add a second. The same holds for the names actions validate: a branch name, the loop name and the state file path have one definition in `lib/loop/check_names.sh` (`check_names_branch`, `check_names_loop_name`, `check_names_state_file`); a copy of their regex elsewhere is a defect, and a Bats case fails on it.
- State data (the state file and the run log) is read from `origin/<state_branch>` through `lib/loop/state_snapshot.sh`, never from the checked-out tree, which may be a PR head. The budget file is policy configuration, not state: read it from the trusted checkout. Code that runs with a write token comes from the trusted ref (see [Trusted ref](../../docs/explanation/loop-engineering/multi-branch-loops-design.md#trusted-ref)).
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
- Not yet renamed (rename when the file is next changed, one file per change): `build_constraints.sh`, `created_by.sh`, `deliver_*.sh`, `detect_env.sh`, `edit_paths.sh`, `ensure_labels.sh`, `git_auth.sh`, `handoff.sh`, `loop_message.sh`, `loop_meta.sh`, `redact.sh`, `target_slug.sh`, `text.sh`, `trigger_thread.sh`, `validate_loop_write_contract.sh`, `verifier_context.sh`.

Gate map (`.github/actions/lib/loop/admission.sh`):

| Function                                                           | Decides                                                                                                               |
| ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| `admission_evaluate`                                               | Run admission from `result.gate`, in one fixed order (the entry point)                                                |
| `admission_evaluate_target`                                        | Circuit breaker, then pending PR, from the target state and the pending PR state fact (before the detect script runs) |
| `admission_evaluate_delivery`                                      | A delivery that needs a PR number (`pr_push`) has one                                                                 |
| `admission_circuit_breaker_verdict`                                | The one place that reads a target state and applies the breaker                                                       |
| `admission_actor_is_bot`                                           | The one bot definition                                                                                                |
| `admission_actor_trusted`                                          | Trusted author association, on every repository                                                                       |
| `admission_budget_exceeded`                                        | Daily run and token budget                                                                                            |
| `admission_circuit_breaker_open`                                   | Circuit breaker with the 30-day half-open window                                                                      |
| `admission_read_budget_limits`, `admission_read_budget_cost_limit` | Budget caps read for the budget check                                                                                 |
| `admission_result`                                                 | Builds the `{admit, skip_reason, detail}` object                                                                      |
