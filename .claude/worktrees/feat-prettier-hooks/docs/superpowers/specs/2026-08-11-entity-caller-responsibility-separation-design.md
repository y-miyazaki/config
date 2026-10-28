# Entity Caller Responsibility Separation Design

**Status:** Draft (grill-me 2026-08-11 follow-up)  
**Date:** 2026-08-11  
**Primary consumers:** Loop Engineering platform, `ci-loop-caller-entity`, issue / future external entity loops  
**Supersedes (partially):** [Issue Triage Entity Loops Design](2026-08-11-issue-triage-entity-loops-design.md) sections on entity profile scope, axis 2/3 caller choice, and normative `target_json` (issue-fixed fields)  
**Implementation (axes 2–3):** [Issue Autofix and PR Revise Full Design](2026-08-11-issue-autofix-pr-revise-full-design.md)
**Related:** [Loop Caller Reusable Design](../../explanation/loop-engineering/loop-caller-reusable-design.md), [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md)

## Problem

1. **`prepare` inline scripts in `on-loop-*`** map GitHub events in the caller — weak portability and duplicates LE’s “thin caller + domain detect” pattern.
2. **Platform knows GitHub Issue shapes** (`issue_number`, `entity.kind: "issue"` fixed in `loop_entity_target.sh`) — adding Backlog/Notion later would fork similar workflows.
3. **Axis 2/3 skeletons sit on `ci-loop-caller-entity`** while code landing belongs on branch/PR-head callers — profile meaning blurs.
4. **Progress vs ops state** and **dispatch side effects** need explicit contracts so dual SoT and LLM-fired HTTP do not creep in.

## Goals

- Lock **responsibility boundaries** so new entity sources add a skill + thin caller only.
- Keep **two caller profiles** (fan-out vs single-target), not one profile per SaaS.
- Treat **repo branch as the integration anchor** for every loop (checkout, `.loop/*`, L2+ PR).
- Align axis 2/3 with **P3 + H2-1**: entity (or human) gates → single autofix/revise intake → branch/PR-head caller.
- Prefer **detect scripts + trusted hooks** for side-effect gates (LE + GAW safe-output style).

## Non-Goals (this design cycle)

- Implementing Backlog / Notion skills or webhooks.
- Full axis 2/3 agent bodies (draft PR / revise push) beyond contracts and intake shape.
- Moving budget/run-log off `.loop/` or inventing a third caller profile for “scan”.
- Replacing label FSM with `.loop/state` as progress SoT.

## Decisions (grill-me)

| ID  | Topic                   | Choice                                                                                                                                      |
| --- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| E1  | Profile split axis      | **Enumeration model only**: fan-out (`ci-loop-caller*`) vs single-target (`ci-loop-caller-entity`). Not by domain (Issue/Backlog/Notion).   |
| E2  | Branch role             | **Integration anchor** always: `branch_state` for `.loop/*`, read-only checkout for L1 analysis, worktree/PR for L2+. Entity ≠ “no branch”. |
| E3  | Domain knowledge        | **detect + SKILL + verifier rubric** only. Workflows pass opaque `detect_domain_env_json` and orchestrate.                                  |
| E4  | Progress SoT            | **3a — external labels/status only** (Astro/GAW pattern). Comments are audit/history.                                                       |
| E5  | Ops                     | `.loop/` **budget + run-log** only initially. No entity cursor required for triage.                                                         |
| E6  | Re-run gate             | **R2** — run when progress labels allow (e.g. `needs-triage` / `triage:needs-info`) and on human comments while needs-info; skip bots.      |
| E7  | Failure stop            | **T2** — allowlisted `triage:failed`; detect skips until a human removes it. Retry counters deferred.                                       |
| E8  | N entities / tick       | User-visible “many” = **matrix fan-out** (1 Agent context / 1 entity). Not one Agent holding many issues.                                   |
| E9  | Axis 2 parent           | **P3** — eligibility/guidance on entity or human gate; **code loop on branch caller**.                                                      |
| E10 | Intake                  | **H2-1** — single `on-loop-issue-autofix` with `labeled(autofix)` + `repository_dispatch` + `workflow_dispatch` → **branch caller only**.   |
| E11 | Double-start            | **D4** — concurrency `loop-autofix-issue-${n}` + detect skip if open/draft PR already references `Fixes #N`.                                |
| E12 | Who dispatches          | **X4** — detect emits machine flag; **Agent does not** HTTP-dispatch.                                                                       |
| E13 | Dispatch placement      | **Y3** — allowlisted **skill hook script** runs after detect (trusted path). Platform only invokes the hook when present.                   |
| E14 | Platform generalization | **G1** — remove Issue-fixed assumptions from platform now so Backlog/Notion can plug in later without new profiles.                         |
| E15 | Detect → matrix key     | **S1** — detect emits `handoff_key`; platform treats it as opaque. Business dedup stays in detect.                                          |
| E16 | Axis 3                  | **R-A** — same shape as axis 2: single intake → PR-head/branch caller (not entity for code revise).                                         |
| E17 | Event mapping           | Move GitHub `event_path` / dispatch fetch **into skill detect scripts** (or skill-local helpers). Delete caller `prepare` jobs.             |
| E18 | External systems        | Future Backlog/Notion = new skill + thin `on-loop-*` + same `ci-loop-caller-entity`. No `ci-loop-caller-backlog`.                           |

## Architecture

```text
Thin on-loop-* (triggers, concurrency, secrets, with:)
        │
        ├─ L1 observe/mutate metadata ──► ci-loop-caller-entity
        │                                   detect_script → handoff_key
        │                                   optional skill hook (Y3)
        │                                   → ci-loop-agent (may_edit false)
        │
        └─ Code land (autofix / revise) ─► ci-loop-caller* (branch / PR-head)
                                            worktree + open_pr / push_head
                                            branch_state integration anchor
```

### Layer responsibilities

| Layer                                       | Knows                                                                | Must not know                         |
| ------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------- |
| `on-loop-*`                                 | triggers, concurrency, secrets, loop tunables                        | Issue/Backlog field mapping jq        |
| `ci-loop-caller-entity`                     | budget, single matrix, handoff, agent wiring, optional hook invoke   | `issue_number`, label FSM, Notion API |
| `loop_entity_target` / `loop-entity-detect` | `skip`, `handoff_key`, opaque `result`, prompt assembly              | GitHub-specific result keys           |
| skill `detect_*.sh`                         | payload → facts, skip, `handoff_key`, dispatch flags, business dedup | workflow YAML structure               |
| skill `SKILL.md` + Agent                    | classify, labels/comments/external API, guidance                     | firing `repository_dispatch` (X4)     |
| skill hook script (Y3)                      | trusted dispatch / similar side effects from detect flags            | LLM reasoning                         |
| branch caller + finalize                    | worktree, PR, `.loop/*` promote                                      | triage FSM                            |

### Detect envelope (entity, normative)

Common LE envelope unchanged: `status`, `skip`, `result`, optional `verifier_context`.

**Platform-required when `skip=false`:**

```json
{
  "status": "ok",
  "skip": false,
  "result": {
    "handoff_key": "entity:issue:123"
  },
  "verifier_context": "optional markdown"
}
```

- `handoff_key` is **required** and opaque to platform (S1).
- All other `result` fields are domain facts for the Agent prompt (titles, labels, backlog fields, …).
- Optional machine flags for Y3 (names lock in implementation plan), e.g. `dispatch_requested`, `dispatch_event_type`, `dispatch_client_payload` — interpreted only by the skill hook, not by generic platform logic beyond “run hook if script exists and flag set”.

**Deprecated for platform reads:** `result.issue_number` as the matrix identity (detect may still set it for the Agent; platform must not require it).

### Target matrix (platform)

Single-element (or empty) array. Each element:

- `handoff_key` — from detect
- `prompt` — skill run + detect JSON + caller instructions + level/delivery constraints (**no hardcoded “use gh Issue API”** in platform prompt builder; skill owns that)
- `target_json` — must satisfy `ci-loop-agent` compatibility (`from.ref` / `to.branch` from `branch_state` / checkout) plus opaque passthrough of detect `result` as needed for handoff artifact
- `verifier_context`, `result` — per existing handoff rules

### Axis wiring (final form)

| Axis            | Intake workflow                | Reusable caller              | Notes                                              |
| --------------- | ------------------------------ | ---------------------------- | -------------------------------------------------- |
| 1 issue-triage  | `on-loop-issue-triage`         | `ci-loop-caller-entity`      | L1; labels + comments; `triage:failed` (E7)        |
| 2 issue-autofix | `on-loop-issue-autofix` (H2-1) | **branch** `ci-loop-caller*` | Not entity for code; D4 dedup in detect            |
| 3 pr-revise     | `on-loop-pr-revise`            | **PR-head / branch** caller  | R-A; entity only if a future L1-only gate is added |

Human remains the default autofix trigger (`autofix` label / dispatch). Automatic Y3 dispatch from triage is optional later; intake shape is ready (E10/E12/E13).

## Comparison to external practice

| Source                          | Progress SoT                                   | Dedup / stop                                       | Relevance                                               |
| ------------------------------- | ---------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------- |
| Astro / Cloudflare triagebot    | Labels FSM; no private DB; comments as history | Re-triageable labels; `failed` + caps; skip labels | Validates E4/E6/E7                                      |
| GitHub Agentic Workflows triage | Unlabeled → label; safe-outputs                | Skip if labeled; max ops; hide-older-comments      | Validates thin progress SoT + trusted side effects (X4) |
| rust-lang triagebot             | Labels + **Postgres** for queues               | Capacity / assignment                              | Only if LE later needs queue capacity — out of scope    |

## Migration from current dogfood

Already landed skeletons may still use `prepare` jobs and entity caller for axis 2/3 stubs. This design requires:

1. Generalize `scripts/lib/loop_entity_target.sh` to **S1** (`handoff_key`).
2. Move event mapping into `detect_issue.sh` (and stubs) — **remove `prepare`**.
3. Retarget `on-loop-issue-autofix` / `on-loop-pr-revise` to **branch/PR-head caller** (stubs may still skip).
4. Add `triage:failed` to label catalog + detect skip + skill/FSM docs.
5. Document Y3 hook path convention (implement hook later or no-op).
6. Update `loop-caller-reusable-design.md` entity section to match E1–E18.

Edit routing: package SoT under `.apm/packages/common/`; `scripts/lib/` for shared libs; do not hand-edit distributed `.agents/` as SoT.

## Error handling

| Case                                    | Behavior                                                                       |
| --------------------------------------- | ------------------------------------------------------------------------------ |
| Missing `handoff_key` when `skip=false` | detect contract error — fail detect step                                       |
| `triage:failed` present                 | detect `skip` until human removes label                                        |
| Dispatch flag set but no hook script    | no-op + log; do not fail triage Agent path unless caller marks hook required   |
| Open `Fixes #N` PR on autofix intake    | detect skip (E11)                                                              |
| Budget exceeded                         | platform skip + run-log (unchanged)                                            |
| Agent failure mid-triage                | prefer apply `triage:failed` when partial success is unsafe; avoid label smash |

## Testing

| Layer                             | What                                                                                 |
| --------------------------------- | ------------------------------------------------------------------------------------ |
| `loop_entity_target`              | Uses `handoff_key`; empty on skip; rejects skip=false without key                    |
| `detect_issue`                    | Emits `handoff_key`; maps event without caller prepare; skips bots / `triage:failed` |
| Autofix detect (when implemented) | Skips when `Fixes #N` PR exists; respects concurrency inputs documented for caller   |
| Workflows                         | No `prepare` job; actionlint / ghalint / zizmor clean                                |

## Open implementation details

- Exact Y3 script path/name under skill `scripts/` (e.g. `hooks/dispatch_requested.sh` vs flag-driven single hook).
- Whether stub autofix caller switches to branch reusable in the same PR as G1 or immediately after.
- Concurrency group expression for H2-1 when trigger is `repository_dispatch` (payload must carry issue number).

## Out of scope for the following implementation plan body

- Backlog/Notion skills.
- Live automatic triage→autofix dispatch (intake + hook contract only).
- T3/T4 retry counters and entity ops cursors in `.loop/state`.
