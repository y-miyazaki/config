# Loop State Targets Retention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or implement task-by-task with TDD. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 30-day retention for loop state `targets` (terminal PR keys / watch reject cooldown) and align ci-sweeper run ledger prune from 7 days to 30 days.

**Architecture:** Pure `prune_targets.sh` under `loop-state-write/lib/`, called from `run.sh` after `load_state_tmp`. Ledger cutoff change only in APM-source `update_run_ledger.sh`.

**Tech Stack:** bash, jq, bats

**Spec:** [Loop State Targets Retention Design](../specs/2026-07-17-loop-state-targets-retention-design.md)

## Global Constraints

- Never delete `integration:*` (non-`pull_request:`) keys or their `last_sha` / `pending`.
- TTL = 30 days (same as run-log).
- Edit APM package sources under `.apm/packages/`; regenerate with `apm install --update`.

---

### Task 1: Ledger cutoff 7 → 30

**Files:**

- Modify: `.apm/packages/loop-ci-sweeper/.apm/skills/loop-ci-sweeper/scripts/update_run_ledger.sh`
- Modify: `test/bats/.apm/packages/loop-ci-sweeper/update_run_ledger.bats`
- Modify: `.apm/packages/loop-ci-sweeper/.apm/skills/loop-ci-sweeper/references/category-run-ledger.md` (if present)
- Run: `apm install --update`

### Task 2: `prune_targets` pure lib + bats (TDD)

**Files:**

- Create: `.github/actions/loop-state-write/lib/prune_targets.sh`
- Create: `test/bats/.github/actions/loop-state-write/lib/prune_targets.bats`

### Task 3: Wire into `loop-state-write` `main`

**Files:**

- Modify: `.github/actions/loop-state-write/lib/run.sh`

### Task 4: Docs

**Files:**

- Spec status → Approved / Implemented
- Brief note in loop-engineering-design / ci-sweeper workflow design / category-run-ledger
