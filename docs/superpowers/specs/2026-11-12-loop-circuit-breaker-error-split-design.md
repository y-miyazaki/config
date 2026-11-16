# Loop circuit breaker: separate errors from rejections (P1, P3, P6)

Date: 2026-11-12. Follows the per-loop design doc unification (PR #1223), whose `Unhandled cases` tables record these as `Follow-up`.

## Intent

The circuit breaker (CB) exists to stop **wasted cost**: with `REJECT` the range stays eligible (`last_sha` does not advance), so the same range is re-run until `consecutive_failures >= 3` (`loop-engineering-design.md`, Retry Policy). Three defects defeat that design:

| ID  | Defect                                                                                                                                                                                                                                                                                   | Evidence                                                                                                                                                                          |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P3  | A maker that exits non-zero with no diff is recorded as `rejected`, so a bug (engine or credential failure, 0 tokens) counts as wasted cost. `error` is not counted by design (`write_state.sh` `resolve_consecutive_failures`).                                                         | `loop.sh` run_bounded_loop: non-zero exit only warns, then `VERDICT=${AGENT_UNCHANGED_VERDICT}`; first dogfood run 2026-11-11 recorded `rejected`, `tokens_total` 0               |
| P6  | The changelog scan counts the loop's own `chore(loop): promote state for PR #N [skip ci]` and `clear_pending state for PR #N [skip ci]` commits as changelog-worthy, so a loop PR close/merge triggers a run that adds nothing, which is `REJECT` and counts toward the CB.              | `is_loop_maintenance_commit` drops only `append run log [skip ci]` and `update state [skip ci]`; `loop-state-promote/lib/run.sh` writes `${WRITE_MODE} state for PR #N [skip ci]` |
| P1  | An open CB never recovers on its own. The 30-day cooldown lives in `prune_targets.sh`, which runs only inside a finalize state write, and a blocked single-target loop never reaches finalize. The dogfood state files for changelog, docs-updater, tech-debt and test-gap are at 3 now. | `detect.sh` `target_state_blocks_candidate`; `prune_targets.sh` cooldown                                                                                                          |

## Decisions

1. **Meaning of the counter.** `consecutive_failures` counts runs that started the agent and produced no value through a judgment (`rejected`, including "no diff"). It does not count runs that failed to run (`error`). No new counter, no new outcome value, no new threshold (stays 3).
2. **P3.** When the final attempt's maker exited non-zero **without spending any tokens**, there is no diff and no watch override, the run's outcome is `error`. A non-zero exit after spending tokens (turn limit, timeout) is wasted cost and stays `rejected`: a maker that failed to start is a bug, one that burned tokens is what the breaker exists to stop, so the attempt's token delta is the signal. Usage is measured only for the `claude` and `cursor` engines (`copilot` and `codex` bypass the usage wrappers, so a delta of 0 would mean "unknown"); on those the exit stays `rejected`, the cost-safe side. `determine_outcome` honors an `error` override ahead of the delivery branches (today `issue_create` loops ignore any override). The verdict stays `REJECT`; only the outcome changes. Non-zero exit with a diff is unchanged (the checker decides).
3. **P6.** `is_loop_maintenance_commit` also drops `chore(loop)` commits whose subject starts with `promote state for PR #` or `clear_pending state for PR #`.
4. **P1.** Detect treats the CB as open only while `last_run` is within 30 days (same window and `last_run` field as `prune_targets.sh`). After that, one run is allowed through (half-open): a `rejected` result reopens the CB for another 30 days, any other outcome closes it (the prune cooldown resets the counter). Finalize reads the stored count before the cooldown only for a `rejected` or `pr_closed` run already at 3 or more (otherwise the probe counts 0 to 1 and the breaker takes three more runs to reopen); every other case keeps the existing post-prune behavior, so a target below 3 still restarts at 1. Missing or invalid `last_run` keeps the CB open (fail-safe, same as prune).
5. **No notification.** The design suggests alerting; a notification needs a destination (an Issue needs `issues: write` on the record-skip job, de-duplication and closing). That is more moving parts than the problem needs. The trip stays visible as run-log `skipped` (`circuit_breaker`) and the `::warning::` in detect; recovery is automatic. My call; revisit only if a trip goes unnoticed in practice.

## Non-goals

- P2 (a no-diff run counts toward the CB) stays: it burns tokens, so counting it matches the purpose. Reducing no-op runs is P6 and detect breadth, not a CB exemption.
- No change to P4, P5, P7–P18, the threshold, or the state schema.
- Resetting the dogfood state files by hand is not part of this work (they recover through decision 4).

## Documentation

- `loop-engineering-design.md`: Retry Policy table gets the `error` row (maker exits non-zero, no diff → `error`, not counted) and states the 30-day half-open rule.
- Per-loop `Unhandled cases`: the P3 rows (ci-sweeper, code-review, test-gap) and the P6 row (changelog) are removed (fixed); the CB-stop rows (changelog, code-review, docs-updater, refactor, tech-debt, ci-sweeper, test-gap) change to `Limitation`: recovers after 30 days, no notification.
- Rule from `docs/explanation/loop-engineering/CLAUDE.md` applies: the implementation is the baseline.

## Verification

Bats for each touched script, run only for the touched directories (never the full suite). No workflow YAML changes.
