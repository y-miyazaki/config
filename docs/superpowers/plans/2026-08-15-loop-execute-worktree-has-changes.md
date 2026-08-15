# Loop Execute Worktree Harvest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover implementer edits written to `GITHUB_WORKSPACE` into the loop worktree, and stop attempt-1 `HAS_CHANGES` from being true only because the PR branch is already ahead of base.

**Architecture:** Add `harvest_workspace_into_worktree` next to `commit_worktree_if_needed` in `agent.sh`. In `run_bounded_loop`, record `pre_head`, harvest, commit, then promote `HAS_CHANGES` from this-attempt commit/HEAD movement; keep branch-ahead promotion only for attempt 2+.

**Tech Stack:** bash, Bats, git

## Global Constraints

- Do not change `push.sh` or skill `no_changes_verdict`.
- Do not change attempt 2+ branch-ahead verifier retry.
- Do not edit `.apm/` skill trees.
- TEST-00: pair Bats with `agent.sh` / `loop.sh` behavior changes.
- TDD: failing tests first.

---

### Task 1: Harvest workspace dirt into worktree

**Files:**
- Modify: `.github/actions/loop-execute/lib/agent.sh`
- Test: `test/bats/.github/actions/loop-execute/lib/agent.bats`

**Interfaces:**
- Produces: `harvest_workspace_into_worktree` — uses `GITHUB_WORKSPACE`, `WORKTREE_PATH`; returns 0 on success/no-op, 1 on copy failure.

- [ ] Write failing Bats for copy, delete, and same-path no-op
- [ ] Implement harvest
- [ ] Tests pass

### Task 2: Attempt-scoped HAS_CHANGES promotion

**Files:**
- Modify: `.github/actions/loop-execute/lib/loop.sh`
- Test: `test/bats/.github/actions/loop-execute/lib/loop.bats`

**Interfaces:**
- Consumes: `harvest_workspace_into_worktree`, `commit_worktree_if_needed`
- Produces: `promote_has_changes_after_attempt ATTEMPT PRE_HEAD ATTEMPT_COMMITTED` mutating `HAS_CHANGES`

- [ ] Write failing Bats for attempt 1 vs 2 vs HEAD-moved
- [ ] Wire harvest + pre_head + promote into `run_bounded_loop`
- [ ] Tests pass
