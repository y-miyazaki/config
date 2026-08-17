# Issue Triage and Entity Loops Design

**Status:** Draft (grill-me + brainstorming 2026-08-11) — **partially superseded** for entity profile scope, axis 2/3 caller choice, and normative `handoff_key` by [Entity Caller Responsibility Separation](2026-08-11-entity-caller-responsibility-separation-design.md)  
**Date:** 2026-08-11  
**Primary consumers:** Loop Engineering platform, `issue-triage` / `issue-autofix` / `pr-revise` loops  
**Related:** [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md), [Loop Caller Reusable Design](../../explanation/loop-engineering/loop-caller-reusable-design.md), [Detect scope axis](2026-08-10-detect-scope-axis-and-interactive-discovery-design.md), [Responsibility Separation](2026-08-11-entity-caller-responsibility-separation-design.md)

## Problem

1. **Issue intake is manual** — classification, analysis comments, and clarifying questions burn maintainer time.
2. **Issue → fix PR and PR revise are conflated with triage** — mixing them blocks independent rollout, engine swap, and human gates.
3. **Existing `ci-loop-caller` assumes branch/PR-head enumeration** — Issue/comment entity events do not fit without twisting detect, targets, and finalize.

## Goals

- Ship **three separate axes** (workflows + skills) with clear triggers and permissions.
- Implement **axis 1 (issue-triage)** end-to-end in this cycle; axes 2–3 as **skeletons + stubs**.
- Add a reusable **entity caller profile** for GitHub entity observation (issue now; stale-pr / advisory later).
- Keep Issue FSM on **labels**; keep LE **budget / run-log / optional state** for operations.
- Test-first for detect, FSM helpers, stubs, and entity caller contracts (Bats / existing loop test style).

## Non-Goals (this cycle)

- Full issue → code fix → draft PR implementation (axis 2 body).
- PR comment → same-branch revise implementation (axis 3 body).
- Mention (`@agent`) as a first-class trigger.
- Astro-style reporter preview / reproduce sandbox.
- Forcing entity loops onto `ci-loop-caller` / `ci-loop-caller-full-github` / `ci-loop-caller-pr-scan`.
- Copilot coding agent as the axis-2 runtime (future option; LE is the chosen final form).

## Decisions (from grill-me + brainstorming)

| ID  | Topic                    | Choice                                                                             |
| --- | ------------------------ | ---------------------------------------------------------------------------------- |
| D1  | Existing “PR creation”   | Means this-repo LE `open_pr` for docs/ci/etc.; **not** Issue→PR yet                |
| D2  | Gap                      | Larger than label+comment — Issue-triggered fix PR also unfinished                 |
| D3  | Analysis home            | LE `loop-issue-triage` (not GAW-only)                                              |
| D4  | Axes                     | **Separate** triage vs fix PR vs PR revise                                         |
| D5  | Fix runtime (final)      | LE Agent; **separate workflow** from triage                                        |
| D6  | This cycle scope         | 3 workflow skeletons + **axis 1 implemented** + axes 2–3 stubs                     |
| D7  | Clarifying questions     | Label FSM: needs-info → re-analyze on answer                                       |
| D8  | Issue progress SoT       | **Labels only**                                                                    |
| D9  | Ops SoT                  | Existing LE `.loop/` budget + run-log (+ optional `state-issue-triage.json`)       |
| D10 | Fix triggers             | `autofix` label **and** assign/dispatch command                                    |
| D11 | Mention triggers         | **Out of initial scope**                                                           |
| D12 | Who may `autofix`        | Repo **write** or above (GitHub permissions)                                       |
| D13 | Initial label set        | `needs-triage`, type (`bug`/`feature`/…), `triage:needs-info`, `triage:ready`      |
| D14 | Missing labels           | Auto-create **allowlisted** labels on first run (fixed color/description)          |
| D15 | After `triage:ready`     | Guidance comment only — **do not** auto-start fix                                  |
| D16 | Triage events            | `opened`/`reopened` + `labeled`/`unlabeled` + `issue_comment` (**exclude bots**)   |
| D17 | Fix skeleton triggers    | `autofix` label + assign/dispatch (**not** ready auto-link)                        |
| D18 | Fix eligibility          | Any type if human applied `autofix`                                                |
| D19 | PR shape (future)        | Always **draft**                                                                   |
| D20 | PR revise                | Third axis; **skeleton only** now; context via PR body `Fixes #N` (+ fetch issue)  |
| D21 | Classification           | Auto when confident; else type label omitted + `needs-triage`                      |
| D22 | Question self-censorship | Prompt forbids cutting questions for “too many”                                    |
| D23 | Duplicate issues         | Design must allow a later axis/hook; not built now                                 |
| D24 | Path guards (fix)        | Prompt/convention now; enforce later                                               |
| D25 | PR body                  | Follow repo PR template if present; else default template with required `Fixes #N` |
| D26 | Implementation approach  | **LE-native three axes**                                                           |
| D27 | Caller                   | New **`ci-loop-caller-entity`** profile — do not overload branch callers           |

## Architecture

```text
GitHub entity events
        │
        ▼
┌───────────────────────────┐
│  ci-loop-caller-entity    │  new profile (shared by entity loops)
│  event → one target       │
│  reuse ci-loop-agent      │
│  budget / run-log / state │
└───────────┬───────────────┘
            │
   ┌────────┼────────┐
   ▼        ▼        ▼
issue-triage  issue-autofix  pr-revise
 (implement)   (stub)         (stub)
```

### Axis 1 — `issue-triage` (implement)

| Item                           | Value                                                                            |
| ------------------------------ | -------------------------------------------------------------------------------- |
| `loop_name`                    | `issue-triage`                                                                   |
| `agent_implementer_skill_name` | `issue-triage`                                                                   |
| Triggers                       | `issues`: opened, reopened, labeled, unlabeled; `issue_comment`: created         |
| Level                          | L1 (no worktree file edits required)                                             |
| Detect                         | Mechanical Issue facts only                                                      |
| Execute                        | Classify, ensure allowlisted labels, post analysis/questions, FSM transitions    |
| Delivery                       | Labels + comments in Execute; finalize = run-log / optional state (no `open_pr`) |

**Label FSM (SoT)**

```text
opened → needs-triage
       → (confident) type label + analysis comment
            → triage:needs-info  (questions posted; wait for human/author reply)
            → triage:ready       (enough info; post autofix guidance)
       → (low confidence) keep/leave needs-triage; ask human
```

**Detect skip (non-exhaustive)**

- `actor_type` bot / own automation user
- Irrelevant label events (non-contract labels)
- Comments that are not answers while not in `triage:needs-info` (policy in detect + skill)

### Axis 2 — `issue-autofix` (skeleton + stub)

| Item         | Value                                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------------- |
| Triggers     | `autofix` labeled; `workflow_dispatch` / assign-equivalent command wiring                                     |
| Behavior now | Stub detect → `skip: true` or single “not implemented” comment (pick one in plan; default **skip + run-log**) |
| Future       | LE Agent implements fix → **draft** PR; PR template / default with `Fixes #N`                                 |

### Axis 3 — `pr-revise` (skeleton + stub)

| Item         | Value                                                   |
| ------------ | ------------------------------------------------------- |
| Triggers     | Reserved (command later; **no mention** in v1)          |
| Behavior now | Stub skip                                               |
| Future       | Push to existing PR head; load linked Issue via PR body |

## Entity caller profile

**Name:** `ci-loop-caller-entity.yaml` (reusable workflow)

**Why separate:** Branch callers enumerate refs and favor worktree + `open_pr`. Entity callers bind **one GitHub object** from an event, often L1 API side effects.

**Reuse:** `ci-loop-agent` / `loop-execute` / `loop-run-log` / budget / state libs.

**Do not reuse as-is:** branch `target_matrix` enumeration from `ci-loop-caller.yaml`.

**Extensibility:** Same profile later hosts `stale-pr`, security-advisory intake, etc., via thin `on-loop-*` callers + domain detect scripts.

### Target JSON (normative sketch)

```json
{
  "entity": {
    "kind": "issue",
    "number": 123,
    "node_id": "I_..."
  },
  "event": {
    "name": "issue_comment",
    "action": "created",
    "comment_id": 456
  },
  "from": { "ref": "<default-branch-sha-or-empty>" },
  "to": { "branch": "<default-branch>" },
  "finalize": "none"
}
```

Exact field names lock in the implementation plan with tests; `finalize: none` (or equivalent L1 metadata-only) for triage.

## Components (this cycle)

| Path                                                                               | Role                                                            |
| ---------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `.github/workflows/ci-loop-caller-entity.yaml`                                     | New reusable entity profile                                     |
| `.github/workflows/on-loop-issue-triage.yaml`                                      | Axis 1 dogfood caller                                           |
| `.github/workflows/on-loop-issue-autofix.yaml`                                     | Axis 2 skeleton                                                 |
| `.github/workflows/on-loop-pr-revise.yaml`                                         | Axis 3 skeleton                                                 |
| `.apm/packages/github/.apm/skills/issue-triage/`                                   | Skill + `scripts/detect_issue.sh` + label catalog + FSM helpers |
| `.apm/packages/github/.apm/skills/issue-autofix/`                                  | Stub skill + detect                                             |
| `.apm/packages/github/.apm/skills/pr-revise/`                                      | Stub skill + detect                                             |
| `docs/explanation/loop-engineering/workflows/loop-issue-triage-workflow-design.md` | Workflow design (docs-updater style)                            |
| Short design notes for autofix / pr-revise skeletons                               | Pointers + non-goals                                            |
| Bats under `test/bats/` (or skill-local per TEST-00)                               | detect, FSM, stubs, entity contract                             |
| Update `loop-engineering-design.md` status row                                     | `issue-triage` in progress / dogfood L1                         |

Edit routing: package sources under `.apm/packages/common/`; sync artifacts per repo rules. Do not hand-edit distributed `.agents/` copies as SoT.

## Error handling

| Case                                 | Behavior                                                        |
| ------------------------------------ | --------------------------------------------------------------- |
| Bot / self comment                   | detect `skip`                                                   |
| Unknown label name outside allowlist | do not create; do not apply                                     |
| Missing allowlisted label            | create with fixed metadata, then apply                          |
| Low-confidence classification        | no type label; `needs-triage`; human comment                    |
| Agent / tool failure                 | no partial label smash; run-log failure; optional Issue comment |
| Budget exceeded                      | platform skip + run-log                                         |
| Axis 2/3 invoked early               | stub skip (or documented not-implemented comment)               |

## Testing

| Layer                        | What                                   | How                                            |
| ---------------------------- | -------------------------------------- | ---------------------------------------------- |
| detect_issue                 | bot skip, event routing, fact envelope | Bats RED→GREEN                                 |
| label FSM / ensure labels    | transitions + allowlist create         | Bats                                           |
| stub detects                 | always skip                            | Bats                                           |
| entity caller contract       | required inputs / target shape         | Bats or workflow contract tests per repo norms |
| Agent classification quality | out of unit scope                      | eval / manual later                            |

TDD required for production helpers and detect scripts.

## Implementation wave

1. Land this spec (review gate).
2. writing-plans → task plan with TDD steps.
3. Entity caller profile (minimal) + contract tests.
4. `issue-triage` detect + FSM helpers (TDD) + skill + caller.
5. Axis 2/3 stub packages + skeleton callers.
6. LE design status + workflow explanation docs.
7. Dogfood dry-run / dispatch where secrets allow.

## Open implementation details (non-blocking)

Resolve in the plan with tests:

- Exact reusable workflow inputs mirroring `ci-loop-caller` alphabetically where applicable.
- Whether stub axes post a visible “not implemented” comment or silent skip (default: **silent skip + run-log**).
- How assign/command maps onto `workflow_dispatch` inputs without mention parsing.
- Whether L1 triage checks out default branch read-only for codebase-aware analysis (recommended: yes, read-only).

## Out of scope for the first implementation plan body

- Axis 2/3 agent implementation and draft PR finalize.
- Duplicate-issue lane.
- Preview releases / reporter verification.
- Mention triggers.
