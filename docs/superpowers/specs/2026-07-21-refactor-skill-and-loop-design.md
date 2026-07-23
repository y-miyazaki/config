# Refactor Skill and Loop Design

**Status:** Approved (grill-me session 2026-07-21); O3 intent routing added 2026-07-21  
**Date:** 2026-07-21  
**Primary package (Phase 1):** `.apm/packages/refactor` → skill `refactor`  
**Future package (Phase 2):** `.apm/packages/loop-refactor` → skill `loop-refactor` + `detect_refactor.sh`  
**Related:** [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md) (action loop family; future `loop-refactor-*`), [Report Tech Debt Workflow Design](../../explanation/loop-engineering/workflows/loop-tech-debt-workflow-design.md) (report-only; not an input to Apply)

## Problem

Repositories need **behavior-preserving structural improvement** (duplication, clearer expression, shallow boundary moves) that lint and `loop-tech-debt` do not cover.

- Lint / SAST already own style, unused, naming, and complexity metrics.
- `loop-tech-debt` detects mechanical debt signals (markers, deps, docs links, churn) and **publishes reports only**. It does not emit refactor opportunities, and Apply must not live under a `report-*` name.
- Famous refactor skills often center on code smells that duplicate lint, or on architecture / GoF work too broad for L2 automation.

The gap is a **shared skill contract** usable interactively and later as a loop entry skill, with stack-specific verification and optional characterization tests when a safety net is missing.

## Goals

- Ship a distributable **`refactor` skill** (Phase 1) with a deterministic workflow: select one target → ensure verification foundation → apply O2-scoped change → verify → report.
- Keep the skill **repository-neutral**; named validation / language skills arrive via caller or user `## Instructions` (stack routing A'), matching loop-ci-sweeper.
- Reuse existing `*-validation` skills where they already gate the stack; add language-specific refactor domain material only when test-addition or O2 steps are missing.
- Define Phase 2 **`loop-refactor`** as an action loop: mechanical H1 hints + path allowlist → same `refactor` contract (or thin `loop-refactor` wrapper that invokes it).
- Document an explicit boundary vs `loop-tech-debt` (no Apply, no R1 feed in v1).

## Non-Goals

- Putting Apply into `loop-tech-debt` or renaming that loop to absorb refactor.
- Using tech-debt report findings as the primary detect input in Phase 1–2 (R1 deferred indefinitely unless a later ADR reopens it).
- L2 automation of deep-module redesign, GoF introduction, or schema / architecture migration (O3 — loop L2 forbidden; interactive proposal path only).
- Detect or skill criteria centered on lint/SAST smells (long method, naming, unused, complexity scores).
- Default SonarQube (or similar) as detect; optional duplication-only opt-in is a later caller feature, not Phase 1.
- Mandatory dedicated SubAgent product surface; platform Implementer / Verifier and optional explore subagents suffice.
- CVE / dependency upgrade / feature behavior changes.

## Decisions (from grill-me)

| ID  | Topic                       | Choice                                                                                                                                                                                             |
| --- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C+D | Skills vs tech-debt Apply   | Skills are the repair engine (**C**). Tech-debt stays report-only. Apply is a separate action path later (**not** mode on report).                                                                 |
| R   | Work shape                  | **R4 + R2**: same skill for interactive and automation; structure-driven (duplication, expression, shallow boundaries).                                                                            |
| T   | Loop targeting (Phase 2)    | **T4**: mechanical hints ∩ path allowlist. Lint territory excluded from detect and from skill checklist center.                                                                                    |
| H   | Hint kinds (Phase 2 detect) | **H1**: `duplication_block`, `oversized_unit` only. No TODO/refactor markers (those stay tech-debt). Sonar default off; future opt-in may feed **duplication only**.                               |
| S   | Skill packaging             | **S2**: generic orchestration skill + language/stack domain via A'. No required custom SubAgent definitions.                                                                                       |
| O   | Allowed operations (L2)     | **O2**: O1 plus shallow same-package moves and import/wiring cleanup. **O3** (deep redesign, patterns) out of L2.                                                                                  |
| I   | Interactive O3 entry        | **Architecture-improvement intent** (natural language — not `max_tier`). Phase A: proposal only. Phase B: one O2 slice per run after explicit user approval.                                       |
| V   | Verification                | **V4**: stack-specific gates; if insufficient for O2, auto-downgrade to O1. If no characterization net exists for a supported language, **add tests/checks first** (or same PR), then apply.       |
| D   | Delivery order              | **D1 + D3**: design → `refactor` skill → add language domain material only when validation reuse cannot cover test-addition or O2 steps; reuse `*-validation`. Loop package after skill is stable. |
| N   | Naming                      | **N1**: skill `refactor`; future loop package / entry `loop-refactor`.                                                                                                                             |

### O1 vs O2 (normative)

| Tier | Allowed                                                                                                                                       | Forbidden on L2                                    |
| ---- | --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| O1   | Deduplicate; clarify expression without API change; extract/inline function or module; remove dead branch when behavior equivalence is proven | Feature changes; public API semantics changes      |
| O2   | O1 + shallow move within the same package/module boundary; import and wiring cleanup                                                          | Cross-package redesign; new patterns; deep modules |
| O3   | Architecture-improvement intent: Phase A proposal; Phase B one approved O2 slice per run                                                      | Not invoked by Phase 2 loop; no one-shot apply     |

### Architecture-improvement intent (interactive O3 — normative)

Users do **not** pass `max_tier: O3`. Classify intent from natural language before edits:

| Intent           | Triggers (examples)                                                                                                                                                                       | Path                                              |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| **structural**   | dedupe, extract, clarify, shallow move; default when ambiguous                                                                                                                            | O1/O2 apply workflow                              |
| **architecture** | architecture improvement, module boundary, deep module, redesign, responsibility split, testability at seams (JA: アーキテクチャ改善, 設計見直し, モジュール整理, 境界の見直し, 責務分離) | Phase A → user approval → Phase B (O2 slice only) |

**Phase A (architecture):** explore target area; emit deepening proposal (problem, candidates, phased plan, risks). Outcome `proposal`. No cross-boundary apply.

**Phase B (architecture):** user names **one** approved slice → run structural path (O2 cap) for that slice only.

`constraints.max_tier` remains a **loop / tool cap** (`O1` \| `O2` only) — not the primary interactive O3 entry.

### Verification (normative)

| Stack (v1)               | Prefer                                                                     | If missing foundation                                                                 |
| ------------------------ | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Go                       | `go test` for touched packages                                             | Add characterization `*_test.go` for existing behavior, then refactor                 |
| Shell                    | `shellcheck` + bats when suite exists                                      | Add/extend bats for behavior under change when domain rules require TEST-00           |
| Terraform                | `terraform fmt/validate`, tflint; **no unintended plan drift** as contract | Do not invent terratest in Phase 1 unless a follow-up task adds terraform domain glue |
| GitHub Actions           | actionlint / existing workflow validation skills                           | Same — validation skills via A'; do not invent new product behavior                   |
| Future (Python, Rust, …) | Language domain + validation skill + test command                          | Extend domain package when the language is adopted                                    |

Unsupported language for a target: **Watch / skip** — do not invent tests in an unknown stack.

Lint tools may run as part of a stack gate. Findings that are purely lint-territory **must not** become the primary reason to select or expand a refactor target.

## Architecture

### Phase 1 — Interactive / agent-invoked skill

```text
User or agent
  → skill `refactor`
       → read ## Instructions (optional A' skill names)
       → classify intent: structural (default) | architecture-improvement
       → pick ONE target (path/symbol) within allowlist if present
       → [architecture] Phase A: proposal report only — stop unless user approved one slice
       → [structural or Phase B] ensure characterization / stack gate (add tests if supported & missing)
       → apply O1 or O2 change (downgrade if gate weak)
       → run validation skills / commands
       → session report (structured)
```

### Phase 2 — Action loop (after Phase 1 stable)

```text
on-loop-refactor.yaml (caller)
  → loop-detect + detect_refactor.sh
       → hints[]: duplication_block | oversized_unit (facts only)
       → skip if empty or outside allowlist
  → Execute: skill_name=loop-refactor (or refactor with loop envelope)
       → same contract as Phase 1; one hint → one target per run
  → Verify → Finalize open_pr
```

Entry skill remains **repository-neutral**. Consumer caller supplies `prompt_instructions` (A') and `agent_verifier_criteria` (defer / REJECT rules).

### Relationship to other loops

| Package                  | Role                                 | Coupling to refactor                   |
| ------------------------ | ------------------------------------ | -------------------------------------- |
| `loop-tech-debt`         | Report mechanical debt               | None in v1 (no feed, no Apply)         |
| `loop-ci-sweeper`        | Fix CI failures                      | Orthogonal; may call validation skills |
| `loop-docs-triage`       | Fix doc drift                        | Orthogonal                             |
| `loop-refactor` (future) | Structural improvement from H1 hints | Owns observation trigger for refactor  |

## Package layout (Phase 1)

```text
.apm/packages/refactor/
  apm.yml
  .apm/skills/refactor/
    SKILL.md
    references/
      common-checklist.md
      common-output-format.md
      category-scope.md
      category-input-schema.md          # interactive + future loop envelope
      category-operations.md            # O1/O2 closed ops; O3 architecture intent (interactive)
      category-verification.md          # V4 + test-addition rules; lint exclusion
    scripts/                            # optional helpers; prefer validation skills
```

Authoring must follow `.apm/AGENTS.md` and `agent-skills` instruction standards (five H2 sections, waza token budget, imperative style).

Phase 2 adds `.apm/packages/loop-refactor/` with detect script, bats (TEST-00), caller example under `.github/workflows/example/`, and a workflow design under `docs/explanation/loop-engineering/workflows/`.

## Skill contract (Phase 1 — summary)

Full text lives in SKILL.md + references; this section is normative for implementers.

### USE FOR

- Behavior-preserving structural edits in O1/O2
- Architecture-improvement requests: Phase A proposal; Phase B one approved O2 slice per run
- Adding characterization tests/checks when the target stack is supported and no net exists
- Invoking named validation skills listed in `## Instructions`

### DO NOT USE FOR

- Feature work, bugfix that changes intended behavior, dependency upgrades
- Lint-driven cleanup as the primary mission
- One-shot cross-boundary apply or GoF introduction (architecture path is propose → approve → slice)
- O3 apply under loop L2 automation
- Detect script ownership or loop state management (Phase 2 entry may wrap; detect stays in `scripts/`)
- Consuming `docs/report/tech-debt/**` as required input

### Workflow outline

1. Parse input (paths, optional hint, constraints). If nothing actionable → report No-op; stop.
2. Load checklist + operations + verification references.
3. Classify intent: **structural** (default) or **architecture-improvement** (`category-operations.md` triggers). Record in session report.
4. Select **one** target. Prefer H1-like evidence when present; otherwise user-specified symbol/path.
5. **Architecture intent, no approved slice:** Phase A — emit proposal (problem, candidates, phased plan, risks). Outcome `proposal`; stop.
6. **Structural intent, or architecture Phase B with one approved slice:** establish verification foundation (add characterization tests/checks if required and language supported).
7. Apply minimal O1/O2 diff. If O2 gate fails → O1 only or Watch.
8. Run stack validation (A' skills / commands). On failure → repair once within scope or revert and Watch.
9. Emit structured session report per `common-output-format.md`.

## Detect contract (Phase 2 — summary)

Closed `hints[].kind`:

| kind                | Meaning                                                               | Must not include                           |
| ------------------- | --------------------------------------------------------------------- | ------------------------------------------ |
| `duplication_block` | Repeated token/AST-approximate blocks above threshold                 | Style/naming/complexity from linters       |
| `oversized_unit`    | File or function over line/byte threshold (size only, not complexity) | Cognitive complexity / maintainability idx |

`skip=true` when no hints after allowlist filter. Always exit 0; errors → `status=error` + `warnings[]` pattern consistent with sibling detects.

Prune paths: align with other loop detects (`.git`, agent roots, `node_modules`, `docs/report/**`, build dirs).

## Reference skills (borrow / avoid)

| Source                                         | Borrow                                       | Avoid in L2 center                     |
| ---------------------------------------------- | -------------------------------------------- | -------------------------------------- |
| skillcreatorai-style behavior-preserving flows | Test-before/after, small steps               | Smell auto-detect as primary           |
| apothem `refactor-extract`                     | Behavioral spec → change → regression verify | Clean-room rewrite of large surfaces   |
| Fowler catalog                                 | Named operations for O1/O2 steps             | Full smell taxonomy overlapping lint   |
| mattpocock `tdd`                               | Red-green discipline when adding tests       | Making TDD the only entry              |
| mattpocock `improve-codebase-architecture`     | Deep-module vocabulary; proposal-first flow  | Automatic L2 deepening; one-shot apply |
| VoltAgent-style broad specialists              | —                                            | GoF/DB/architecture in the loop        |

## Implementation phases

### Phase 1 (this plan’s first implementation plan)

1. Spec (this document) — done when committed/merged as agreed.
2. Implementation plan under `docs/superpowers/plans/`.
3. APM package `refactor` + references + eval/waza readiness.
4. Dogfood: invoke skill manually in `config` (and optionally one Go/shell consumer).
5. Docs: short pointer from loop-engineering index under “future action loops” if not already covered.

### Phase 2 (separate plan)

1. Workflow design: `docs/explanation/loop-engineering/workflows/loop-refactor-workflow-design.md`
2. Package `loop-refactor` + `detect_refactor.sh` + bats
3. Example caller `on-loop-refactor.yaml`
4. L2 dogfood with tight allowlist; promote only after stable runs

## Testing strategy

| Layer       | Phase 1                                                                 | Phase 2                                      |
| ----------- | ----------------------------------------------------------------------- | -------------------------------------------- |
| Skill       | `waza check` / agent-skills-review; eval.yaml if used in sibling skills | Same                                         |
| Detect      | —                                                                       | Bats suite TEST-00 paired with detect script |
| Integration | Manual skill run on fixture paths                                       | Loop dry-run / dogfood cron with budget caps |

## Risks

| Risk                                       | Mitigation                                                               |
| ------------------------------------------ | ------------------------------------------------------------------------ |
| Skill becomes lint cleanup                 | Checklist + DO NOT USE FOR; verifier REJECT lint-only diffs              |
| Test addition expands into feature specs   | Characterization of **existing** behavior only                           |
| O2 moves without adequate gates            | V4 downgrade to O1                                                       |
| Architecture intent misclassified          | Default to structural when ambiguous; architecture triggers in checklist |
| O3 one-shot apply on user request          | Phase A proposal first; Phase B one O2 slice only after approval         |
| Drift into tech-debt coupling              | Explicit non-goal; no report path in input schema v1                     |
| Token / scope blowups on full-repo explore | One target per run; allowlist; lean-ctx for agent context fetch          |

## Open items (explicit, non-blocking for Phase 1)

- Exact duplication algorithm and size thresholds for Phase 2 detect (choose when implementing detect; document in detect design or workflow design).
- Whether Phase 2 entry skill is a thin `loop-refactor` wrapper or reuses `refactor` with a loop input schema only — prefer thin wrapper for trigger clarity; decide in Phase 2 plan.
- Sonar CPD opt-in env keys — defer to Phase 2+ caller design.

## Success criteria

- Phase 1: `refactor` skill installs via APM, passes skill review gates, and produces a minimal behavior-preserving change + report on a dogfood path without requiring the tech-debt report.
- Phase 2: `loop-refactor` opens L2 PRs from H1 hints only, with allowlist and verifier rejecting O3 / lint-primary / behavior-changing diffs.
