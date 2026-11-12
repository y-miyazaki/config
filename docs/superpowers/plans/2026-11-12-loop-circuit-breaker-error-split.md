# Loop circuit breaker error split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop bug-type failures counting toward the circuit breaker (P3), stop the changelog loop re-triggering on its own state commits (P6), and let an open breaker recover after 30 days (P1).

**Architecture:** Three small shell changes, each with a bats test, plus doc updates. No new inputs, outputs, state fields or outcome values.

**Tech Stack:** bash, jq, bats.

**Spec:** `docs/superpowers/specs/2026-11-12-loop-circuit-breaker-error-split-design.md`

## Global Constraints

- Run bats only for the touched files (`bats test/bats/<path>.bats`); never the whole suite.
- Do not run hook-covered tools (shellcheck, shfmt, prettier, markdownlint, actionlint) by hand; hooks cover them.
- Edit `.apm/packages/**` for the changelog script; do not hand-edit `.agents/`, `.claude/` copies (the Stop hook syncs them; commit the synced result).
- Shell style: follow the existing function-doc header format in each file.
- Breaker threshold stays 3; window stays 30 days; no new state fields.
- Commit trailer: `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`.

## Review Focus

- A maker exit non-zero **with** a diff must still reach the checker (outcome unchanged).
- A watch override with a non-zero maker exit stays `watch`.
- `issue_create` delivery with an `error` override is `error`; with a `watch` override it behaves as today.
- A multi-attempt run where attempt 1 fails and attempt 2 succeeds is not `error` (only the final attempt counts).
- `last_run` missing, empty, or malformed keeps the breaker open.
- A commit subject merely containing `promote state` (not `chore(loop):` + the exact prefix) is still counted.

---

### Task 1: P3 — maker failure with no diff is `error`

**Files:**

- Modify: `.github/actions/loop-finalize/lib/determine_outcome.sh` (`determine_outcome`, line ~51)
- Modify: `.github/actions/loop-execute/lib/loop.sh` (`run_bounded_loop`, maker call ~line 296, no-change branch ~line 338)
- Test: `test/bats/.github/actions/loop-finalize/lib/determine_outcome.bats`, `test/bats/.github/actions/loop-execute/lib/loop.bats`

**Interfaces:**

- Produces: `determine_outcome error <agent_result> <has_changes> <verdict> <delivery> <push_failed>` prints `error` for every delivery. `loop.sh` global `MAKER_EXIT_NONZERO` (`true`/`false`), reset at the start of each attempt, set from the `run_agent_capture` return.

- [ ] **Step 1: Write failing tests.** In `determine_outcome.bats`: `override=error` returns `error` for delivery `pr_create`, `issue_create`, `none` and `issue_comment`, with verdict `REJECT` and `APPROVE`; `override=watch` with delivery `issue_create` still returns what it returns today (assert the current value). In `loop.bats`: with a stubbed `run_agent_capture` returning 1, no changes and `AGENT_UNCHANGED_VERDICT=REJECT`, `FINALIZE_OUTCOME_OVERRIDE` is `error` and `VERDICT` is `REJECT`; same with a return of 0, the override stays empty; non-zero return with a commit produced, the override stays empty; non-zero return plus the skill's watch output, the override is `watch`; attempt 1 non-zero then attempt 2 zero with no changes, the override stays empty.
- [ ] **Step 2: Run the two bats files; expect the new cases to fail.**
- [ ] **Step 3: Implement.** In `determine_outcome`, add `elif [[ ${override} == "error" ]]; then printf '%s\n' "error"` immediately after the `push_failed` branch. In `run_bounded_loop`, set `MAKER_EXIT_NONZERO="false"` at the top of each attempt, set it to `"true"` where the existing code warns on non-zero, and in the `HAS_CHANGES != true` branch's final `else` (the `AGENT_UNCHANGED_VERDICT` path) also set `FINALIZE_OUTCOME_OVERRIDE="error"` and append `; maker exited non-zero` to `REASON` when `MAKER_EXIT_NONZERO` is `true`. Keep the watch branch first.
- [ ] **Step 4: Run both bats files; expect pass.**
- [ ] **Step 5: Commit** `fix(loop): record a maker failure with no diff as error`.

### Task 2: P6 — changelog ignores promote and clear_pending state commits

**Files:**

- Modify: `.apm/packages/repo-maintenance/.apm/skills/changelog/scripts/detect_changelog_commits.sh` (`is_loop_maintenance_commit`, line ~454)
- Test: `test/bats/.apm/packages/repo-maintenance/changelog/detect_changelog_commits.bats`

**Interfaces:**

- Produces: `is_loop_maintenance_commit chore loop "promote state for PR #12 [skip ci]"` and the `clear_pending state for PR #…` form return 0.

- [ ] **Step 1: Write failing tests** next to the existing `is_loop_maintenance_commit` tests: both new subjects return 0; `chore loop "promote state [skip ci]"` (no PR suffix) and `feat loop "promote state for PR #1"` and `chore other "promote state for PR #1"` return 1.
- [ ] **Step 2: Run the file; expect failure.**
- [ ] **Step 3: Implement.** Extend the `case "${subject}"` in the `chore`/`loop` branch with `"promote state for PR #"* | "clear_pending state for PR #"*`.
- [ ] **Step 4: Run the file; expect pass.**
- [ ] **Step 5: Commit** `fix(changelog): ignore loop promote and clear_pending state commits`; include the synced `.agents/`/`.claude/` copies if the hook produced them.

### Task 3: P1 — the circuit breaker recovers after 30 days

**Files:**

- Modify: `.github/actions/loop-detect/lib/guards.sh` (`target_circuit_breaker_open`, line ~187), `.github/actions/loop-detect/lib/detect.sh` (`target_state_blocks_candidate`, line ~1096)
- Test: `test/bats/.github/actions/loop-detect/lib/guards.bats`, `test/bats/.github/actions/loop-detect/lib/detect.bats`

**Interfaces:**

- Produces: `target_circuit_breaker_open <consecutive> [last_run]`. Open when `consecutive >= 3` and (`last_run` missing/invalid, or `last_run[0:10] >= date -u -d '30 days ago'`). The second argument is optional so existing callers keep working.

- [ ] **Step 1: Write failing tests** in `guards.bats` (use a `last_run` computed from `date` so the test does not rot): count 3 with `last_run` today is open; count 3 with `last_run` 31 days ago is closed; count 2 is closed; count 3 with no `last_run`, empty, or `garbage` is open; count 3 with no second argument is open. In `detect.bats`: a target state `{"consecutive_failures":3,"last_run":"<31 days ago>"}` is not blocked, with `<today>` is blocked and increments `CIRCUIT_BREAKER_BLOCKED`.
- [ ] **Step 2: Run both files; expect failure.**
- [ ] **Step 3: Implement.** Compute the cutoff with the same `date -u -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-30d +%Y-%m-%d` fallback as `prune_targets.sh`, and compare the first 10 characters of `last_run` as strings. In `target_state_blocks_candidate`, pass `$(jq -r '.last_run // empty' <<< "${target_state}")` as the second argument.
- [ ] **Step 4: Run both files; expect pass.**
- [ ] **Step 5: Commit** `fix(loop): let an open circuit breaker recover after 30 days`.

### Task 4: Documentation

**Files:**

- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md` (Retry Policy table near line 700–724, circuit breaker section)
- Modify: `docs/explanation/loop-engineering/workflows/loop-{changelog,ci-sweeper,code-review,docs-updater,refactor,test-gap,tech-debt}-workflow-design.md` (`Unhandled cases`)

- [ ] **Step 1:** In the Retry Policy table add the row "Maker exits non-zero with no diff → `error`; not counted toward `consecutive_failures`". In the circuit breaker text state the half-open rule (decision 4 of the spec) and replace "Consider alerting via PR comment" so it matches decision 5.
- [ ] **Step 2:** Delete the P3 rows (ci-sweeper, code-review, test-gap) and the P6 row (changelog). Change the seven CB-stop rows to disposition `Limitation` with the text "Recovers on its own once `last_run` is older than 30 days (one run is allowed through; a `rejected` result reopens it for another 30 days). No notification: the trip shows only as run-log `skipped` (`circuit_breaker`)." Remove the "stop lasts until a person edits the state file" claims, and the "dogfood state has been at 3 since …" detail.
- [ ] **Step 3:** Run `tmp/check-workflow-docs.sh` (prints nothing when clean) and the anchor checker; expect clean.
- [ ] **Step 4: Commit** `docs: update circuit breaker design for the error split and 30-day recovery`.
