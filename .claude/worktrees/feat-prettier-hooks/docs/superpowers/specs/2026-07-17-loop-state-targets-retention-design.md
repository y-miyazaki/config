# Loop State Targets Retention Design

**Status:** Approved — implemented  
**Date:** 2026-07-17  
**Trigger:** [state-ci-sweeper.json](https://github.com/y-miyazaki/config/blob/main/.loop/state-ci-sweeper.json) accumulates `pull_request:*` `rejected` entries with no TTL; run-log already prunes at 30 days. Domain ledger [state-ci-sweeper-run-ledger.json](https://github.com/y-miyazaki/config/blob/main/.loop/state-ci-sweeper-run-ledger.json) already prunes but at **7 days** — align to 30.

## Problem

1. `.loop/state-*.json` `targets` are upsert-only. Closed or rejected `pull_request:*` keys (and reject metadata on watch targets) remain forever.
2. `.loop/state-ci-sweeper-run-ledger.json` (`runs` keyed by `workflow_run_id`) already drops aged entries in `update_run_ledger.sh`, but the cutoff is **7 days**, not the same 30-day window as run-log / the state policy below.

## Goals

- Align retention with run-log: **30 days**.
- Never lose watch-target cursors (`last_sha`, `pending`) on `integration:*` (and other non-PR watch keys).
- Keep in-flight work: open / `pending` / non-terminal target outcomes untouched.
- Apply the same TTL to **domain persistence ledgers** (ci-sweeper run ledger today; future ledgers follow the same rule).
- Prune on existing write paths (no new cron-only job).

## Non-Goals

- Deleting `integration:*` (or other watch-branch) target keys.
- Immediate delete on REJECT/merge (history retained up to 30 days).
- Changing circuit-breaker threshold (`consecutive_failures >= 3`).
- Changing `CI_SWEEPER_REJECT_RETRY_POLICY` semantics (only retention window).
- Sharing one prune helper across packages in this change (optional follow-up).

## Scope (artifacts)

| Artifact              | Path (dogfood)                                    | Prune today              | This design                       |
| --------------------- | ------------------------------------------------- | ------------------------ | --------------------------------- |
| Loop state            | `.loop/state-<loop>.json` → `targets`             | none                     | add 30-day rules below            |
| Run log               | `.loop/loop-run-log.md`                           | 30 days                  | unchanged (reference)             |
| CI sweeper run ledger | `.loop/state-ci-sweeper-run-ledger.json` → `runs` | **7 days** (all entries) | **30 days** (all settled entries) |

## Decisions

### Shared

| Topic | Choice                                                                                              |
| ----- | --------------------------------------------------------------------------------------------------- |
| TTL   | **30 days** (same window as run-log)                                                                |
| Clock | ISO timestamp; compare date prefix `YYYY-MM-DD` or full ISO ≥ cutoff (ledger already uses full ISO) |

### Loop state `targets`

| Topic                            | Choice                                                                                                             |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Watch keys (`integration:*`, …)  | **Never delete the key.** Always keep `last_sha` and `pending`.                                                    |
| Watch keys after terminal REJECT | After 30 days: clear reject history fields and reset `consecutive_failures` to `0` (cooldown). Keep cursor fields. |
| `pull_request:*`                 | Terminal + `last_run` older than 30 days + no `pending` → **delete key**.                                          |
| In-flight                        | Any key with `pending`, or non-terminal outcome → keep as-is.                                                      |
| When to prune                    | Each `loop-state-write` before commit.                                                                             |
| Clock field                      | `last_run`; missing → do not prune that key.                                                                       |

### Run ledger `runs` (ci-sweeper)

| Topic         | Choice                                                                                                                                                                                        |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Key           | `workflow_run_id` (immutable; no “open pending” object)                                                                                                                                       |
| What to prune | Entries with `updated_at` older than 30 days — **all ledger outcomes** (`pr-created`, `rejected`, `watch`, `no-action`). Each run id is finished once recorded; TTL is pure dedupe retention. |
| When to prune | Existing path: every `update_run_ledger.sh` write (already prunes; only change cutoff 7 → 30).                                                                                                |
| Reject retry  | After prune, a vanished `rejected` entry may be retried under `block`/`limited` as if unseen — acceptable cooldown after 30 days (same spirit as state reject-field reset).                   |

## Terminal vs non-terminal (state `targets` only)

**Terminal** (eligible for prune after 30 days):

- `rejected`
- `pr-closed`

**Non-terminal** (never prune solely by age):

- `pr-created` (especially with `pending`)
- `watch`
- `no-op` on watch keys — watch keys are never deleted anyway
- Any entry with a present `pending` object — **never delete key** regardless of `outcome`

## Rules (normative)

### State `targets`

```text
for each key, entry in targets:
  if entry.pending exists:
    keep  # in-flight
    continue

  age_ok = last_run present AND last_run date < (now - 30 days)

  if key matches /^pull_request:/:
    if outcome in {rejected, pr-closed} AND age_ok:
      delete targets[key]
    else:
      keep

  else:  # watch / integration:* (and any non-pull_request key)
    keep key always
    if outcome in {rejected, pr-closed} AND age_ok:
      clear last_reject_reason, open_rejections
      set consecutive_failures = 0
      # leave last_sha, last_run, outcome
```

### Run ledger `runs`

```text
cutoff = now - 30 days   # was 7 days in update_run_ledger.sh
for each run_id, entry in runs:
  if entry.updated_at < cutoff:
    delete runs[run_id]
  else:
    keep
```

Implementation note: today jq already does  
`.runs |= with_entries(select(.value.updated_at >= $cutoff))` — change cutoff only; keep behavior.

## Architecture

```text
loop-state-write (each write)
  load state JSON
  → prune_targets_by_retention(state)   # new pure helper
  → apply advance/pending/metadata/…
  → commit/push

update_run_ledger.sh (each ledger update)
  merge run entry
  → prune runs by updated_at >= cutoff (30d)   # existing; retune cutoff
```

Prefer a pure function under `.github/actions/loop-state-write/lib/` for targets prune, callable from bats without git.

Ledger prune stays inside `loop-ci-sweeper` `scripts/update_run_ledger.sh` (and its bats). Update skill `references/category-run-ledger.md` to say 30 days.

## Error handling

- Invalid `targets` / `runs` object → skip prune for that file; do not fail the write solely for prune.
- Unparseable timestamps → keep entry (fail-safe).
- Unknown state outcomes → keep (only listed terminal outcomes prune keys / reject fields).

## Testing

### State `prune_targets`

| Case                                                  | Expectation                                                                        |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `integration:main` old `rejected`, no pending         | Key remains; reject fields cleared; `consecutive_failures=0`; `last_sha` unchanged |
| `integration:main` with `pending`                     | Unchanged                                                                          |
| `pull_request:355` `rejected`, `last_run` 31 days ago | Key deleted                                                                        |
| `pull_request:401` `rejected`, `last_run` 5 days ago  | Key kept                                                                           |
| `pull_request:N` with `pending`                       | Key kept even if outcome terminal                                                  |
| `pull_request:N` `pr-closed`, aged                    | Key deleted                                                                        |
| Missing `last_run`                                    | Key kept                                                                           |

### Ledger (`update_run_ledger` / bats)

| Case                                 | Expectation                                          |
| ------------------------------------ | ---------------------------------------------------- |
| Entry `updated_at` 8 days ago        | **Kept** after change (was deleted under 7-day rule) |
| Entry `updated_at` 31 days ago       | Deleted                                              |
| Fresh `rejected` / `pr-created`      | Kept                                                 |
| Existing bats asserting 7-day cutoff | Update expectations to 30 days                       |

## Documentation updates (implementation phase)

- [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md) / multi-branch state: 30-day prune for terminal `pull_request:*`; watch keys permanent with reject-field cooldown.
- [CI Sweeper Workflow Design](../../explanation/loop-engineering/workflows/loop-ci-sweeper-workflow-design.md) + `category-run-ledger.md`: ledger retention **30 days** (was 7).
- Header comment in `update_run_ledger.sh` (“Prune entries older than 7 days” → 30).

## Open follow-ups (out of scope)

- Shared `prune_cutoff_date` helper between run-log, state-write, and ledger.
- Explicit `merged` outcome name for state targets.
- Other future domain ledgers: default to the same 30-day `updated_at` prune unless they gain a `pending` concept.
