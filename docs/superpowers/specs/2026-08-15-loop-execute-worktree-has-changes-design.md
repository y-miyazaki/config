# Loop Execute Worktree Harvest and Attempt HAS_CHANGES Design

**Status:** Implemented (A slice: harvest + attempt-1 HAS_CHANGES)
**Date:** 2026-08-15
**Primary consumers:** `loop-execute` (all loops), especially `github-pr-revise` on PR heads
**Related:** [Issue Autofix and PR Revise Full](2026-08-11-issue-autofix-pr-revise-full-design.md), PR #677 follow-up

## Problem

On PR #677, five `@loop` review comments each started `on-loop-github-pr-revise`. Runs often reported `has_changes=true` and pushed, but four comments were never applied.

Two platform defects caused that:

1. **Lost edits.** `Run Bounded Loop` already sets `working-directory` to `WORKTREE_PATH`, and `commit_worktree_if_needed` only commits that tree. Cursor (and possibly other engines) still wrote files under `GITHUB_WORKSPACE` (the default checkout). Those edits never entered the worktree commit, so they never pushed.

2. **False `has_changes` on attempt 1.** After a clean worktree, `run_bounded_loop` promotes `HAS_CHANGES=true` when `BASE_BRANCH...HEAD` still has product files. A pr-revise worktree **is** the PR head, so it is almost always ahead of `main`. A no-op implementer still looked like a successful change run. Downstream push/notify then treated the old branch as “this feedback was applied.”

## Goals

- Edits the implementer made on the runner are committed in the loop worktree (or the run fails closed with a visible reason).
- Attempt 1 of a job does not set `HAS_CHANGES=true` solely because the branch was already ahead of `BASE_BRANCH`.
- Other loops keep maker/checker retry behavior: attempt 2+ may still run the verifier on an unchanged-but-ahead branch.

## Non-goals (follow-up issues after this slice)

- Batching multiple `@loop` comments into one session
- Changing concurrency (`cancel-in-progress`)
- Injecting review-comment `path` / `line` / `diff_hunk` into detect JSON
- Start ACK (reaction) or threaded reply on the trigger comment
- Engine session memory across runs
- Changing `push.sh` inputs or per-skill `no_changes_verdict`

## Decisions

| Topic | Choice |
| ----- | ------ |
| Scope | `loop-execute` only (`agent.sh`, `loop.sh`, paired Bats). No skill package edits. |
| Lost edits | **Harvest** dirty paths from `GITHUB_WORKSPACE` into `WORKTREE_PATH` when those directories differ, then existing `commit_worktree_if_needed`. Log `::warning::`. Do not silently drop workspace dirt. |
| Harvest failure | If harvest cannot copy a path, fail the attempt with a structured error (do not set `HAS_CHANGES` from branch-ahead as a substitute). |
| `HAS_CHANGES` attempt 1 | True only when this attempt created a commit (`commit_worktree_if_needed` succeeded) **or** `HEAD` in the worktree moved vs the SHA recorded before the implementer. |
| `HAS_CHANGES` attempt 2+ | Keep today’s branch-ahead promotion so a REJECT retry can re-run the verifier without a new commit. |
| Branch-ahead on attempt 1 | **Remove.** This is the pr-revise false-success. Other loops that re-enter execute with an already-ahead branch and a no-op implementer correctly become `no_changes` (detect should have skipped if there was nothing to do). |
| `push.sh` | Unchanged. Still pushes when `LOOP_HAS_CHANGES=true`. Semantics of that flag become honest. |
| Cursor `--workspace` | Out of scope unless harvest + cwd prove insufficient; do not add engine-specific flags in this slice. |

## Architecture

```text
attempt N:
  pre_head = git -C WORKTREE rev-parse HEAD
  run implementer (existing working-directory = worktree)
  harvest_workspace_into_worktree   # no-op if GITHUB_WORKSPACE == WORKTREE_PATH
  commit_worktree_if_needed
  if commit OR HEAD != pre_head:
      HAS_CHANGES=true
  elif N > 1 AND branch has product files vs BASE:
      HAS_CHANGES=true   # existing retry path
  else:
      no-changes / NO_CHANGES_VERDICT
```

### Harvest

When `GITHUB_WORKSPACE` is set, is a directory, and is not the same resolved path as `WORKTREE_PATH`:

1. `git -C "${GITHUB_WORKSPACE}" status --porcelain`
2. For each path (skip `.git/` and empty), copy the file into `${WORKTREE_PATH}/${path}` creating parents as needed; delete in the worktree when the workspace status is `D.
3. Do not `git add`/`commit` in `GITHUB_WORKSPACE`.
4. Leave workspace dirt as-is (runner is ephemeral).

This is a **correct** change for every loop: the worktree is the only tree that is committed and pushed.

### Attempt-1 `HAS_CHANGES`

Record `pre_head` before `run_agent_capture`. After commit:

- New commit or `HEAD != pre_head` → `HAS_CHANGES=true` (agent committed itself inside the worktree).
- Attempt 1 + clean worktree + unchanged HEAD → do **not** use `list_non_loop_branch_files` to set `HAS_CHANGES`.

Attempt 2+ keeps the current `Worktree is clean; BASE...HEAD still has product files` branch.

## Impact on other CI

| Loop | Attempt 1, agent no-op, branch already ahead | After this change |
| ---- | -------------------------------------------- | ----------------- |
| github-pr-revise | False success (bug) | `no_changes` / REJECT (`no_changes_verdict`) — intended |
| changelog / ci-sweeper / docs-updater new branch | Usually not ahead until a commit | Unchanged |
| Same loops, re-run execute on existing loop branch with no new edit | Verifier + push of old commits | `no_changes` — intended; detect should skip idle targets |
| Attempt 2+ after REJECT, no extra commit | Verifier on same diff | Unchanged |

No change to allowlist/denylist, verifier criteria, or finalize PR creation.

## Testing

Paired Bats under `test/bats/.github/actions/loop-execute/lib/`:

1. Harvest copies a modified file from a fake `GITHUB_WORKSPACE` into `WORKTREE_PATH`.
2. Harvest applies a deletion recorded in workspace porcelain.
3. Harvest is a no-op when workspace path equals worktree path.
4. Attempt 1: clean worktree, `HEAD` unchanged, product files vs base → `HAS_CHANGES` stays false (extract the promotion helper or test via sourced functions).
5. Attempt 2: same situation → `HAS_CHANGES` becomes true (existing warning path).
6. `HEAD` moves without porcelain (simulated commit) → `HAS_CHANGES` true.

Existing `push.bats` / `notify_context.bats` stay as they are (`LOOP_HAS_CHANGES` still a boolean).

## Follow-up issue list (do not implement here)

Create GitHub issues after this slice lands:

1. **pr-revise comment batching** — debounce / gather open `@loop` comments into one run.
2. **Concurrency** — keep `cancel-in-progress: false`; design queue vs “latest only” without killing in-flight work.
3. **Inline review context** — `path`, `line`, `diff_hunk`, `comment.id` in detect JSON and prompt.
4. **Start ACK + thread reply** — reaction on trigger; `in_reply_to` on completion (Resolve stays human).
5. **Created By leftover** — already implemented locally (contract order, Bats edges, `printf`, SC1091); commit separately from this slice.
