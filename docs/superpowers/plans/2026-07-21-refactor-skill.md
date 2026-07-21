# Refactor Skill (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship distributable APM package `refactor` with skill `refactor` (S2 orchestration + A' validation routing) and normative references for O1/O2, V4 verification, and session reporting — interactive / agent-invoked only.

**Architecture:** One repository-neutral orchestration skill under `.apm/packages/refactor/`. Stack-specific gates and named `*-validation` skills arrive via caller/user `## Instructions` (A'), matching loop-ci-sweeper. Detail lives in `references/`; `SKILL.md` stays under the waza token budget. No detect script, no loop package, no SubAgent product surface in Phase 1.

**Tech Stack:** APM packages, Markdown skill/references (agent-skills five-H2 contract), `apm install` / `apm audit`, `agent-skills-review` / `waza check`.

## Global Constraints

- Spec source of truth: `docs/superpowers/specs/2026-07-21-refactor-skill-and-loop-design.md` (do not reopen grill decisions).
- **Phase 1 only** — do NOT create `loop-refactor`, `detect_refactor.sh`, `on-loop-refactor.yaml`, Sonar integration, or workflow design for Phase 2.
- Package source of truth: `.apm/packages/refactor/` only. Never edit generated `.agents/`, `.claude/`, `.cursor/`, `.kiro/`, `.vscode/`, or `apm_modules/`.
- After skill/package edits: `apm install --update` when verifying install; `apm audit --ci` when verifying packages.
- Authoring: `.apm/AGENTS.md` + agent-skills standards (five H2 sections, imperative style, waza token budget).
- Decisions locked: **S2**, **O2** (O3 out of L2), **V4**, **N1** (`refactor`), **R4+R2**, no tech-debt report coupling, lint/SAST must not be the center of selection or checklist.
- Stack routing **A'**: do not hardcode consumer skill names in distributable `references/`; dispatch via `## Instructions`.
- Context fetch: use **lean-ctx** for all read/search/file gather (prefer lean-ctx MCP / hooks over raw bulk reads).
- Commit only when the user asks. Do not push unless asked. Plan steps say "Do not commit".

## File map (Phase 1)

| Path                                                   | Responsibility                                                          |
| ------------------------------------------------------ | ----------------------------------------------------------------------- |
| `.apm/packages/refactor/apm.yml`                       | APM package manifest (`config-refactor`)                                |
| `.apm/packages/refactor/.apm/skills/refactor/SKILL.md` | Thin orchestration contract (5 H2 sections)                             |
| `.../references/common-checklist.md`                   | Always-on guards (one target, O1/O2, lint exclusion, no tech-debt feed) |
| `.../references/common-output-format.md`               | Session report sections + metrics table                                 |
| `.../references/category-scope.md`                     | Allow/deny path defaults; one-target rule                               |
| `.../references/category-input-schema.md`              | Interactive + future loop envelope fields                               |
| `.../references/category-operations.md`                | Closed O1/O2 ops; O3 forbidden on L2                                    |
| `.../references/category-verification.md`              | V4 stack gates + characterization test-addition; lint exclusion         |
| `.../eval.yaml`                                        | Minimal eval suite stub (sibling pattern)                               |
| `apm.yml` (repo root)                                  | Wire local dep `./.apm/packages/refactor`                               |
| `docs/explanation/loop-engineering/index.md`           | Short “future action loops” pointer to Phase 1 skill / Phase 2 TBD      |

No `scripts/` required in Phase 1 (prefer validation skills via A').

---

### Task 1: Scaffold APM package + wire root `apm.yml`

**Files:**

- Create: `.apm/packages/refactor/apm.yml`
- Create: `.apm/packages/refactor/.apm/skills/refactor/` (directory)
- Modify: `apm.yml` (repo root) — add `./.apm/packages/refactor` under `dependencies.apm`

**Interfaces:**

- Produces: installable package name `config-refactor` with empty skill dir ready for Task 2+.
- Consumes: existing root `apm.yml` local-path dependency style (see `loop-ci-sweeper`).

- [ ] **Step 1: Create package manifest**

Create `.apm/packages/refactor/apm.yml`:

```yaml
name: config-refactor
version: 1.0.0
description: Behavior-preserving refactor orchestration skill (O1/O2) with stack verification via Instructions
author: y-miyazaki
license: Apache-2.0
target: all
includes: auto

dependencies:
  apm: []
  mcp: []
```

- [ ] **Step 2: Create skill directory**

```bash
mkdir -p .apm/packages/refactor/.apm/skills/refactor/references
```

Do not create `scripts/` in Phase 1.

- [ ] **Step 3: Wire root `apm.yml`**

In repo-root `apm.yml`, under `dependencies.apm` (local path list), add after the existing loop packages (alphabetically with other locals is fine; keep list readable):

```yaml
- ./.apm/packages/refactor
```

Place it near other local packages (e.g. after `loop-report-tech-debt` or in alpha order among `./.apm/packages/*`).

- [ ] **Step 4: Sanity check paths**

Run: `test -f .apm/packages/refactor/apm.yml && test -d .apm/packages/refactor/.apm/skills/refactor/references && rg -n 'packages/refactor' apm.yml`

Expected: both tests succeed; `apm.yml` shows the new dependency line.

- [ ] **Step 5: Do not commit**

---

### Task 2: Write `SKILL.md` (orchestration contract)

**Files:**

- Create: `.apm/packages/refactor/.apm/skills/refactor/SKILL.md`

**Interfaces:**

- Consumes: Task 1 directory; normative contract from spec §§ Skill contract, O1/O2, V4, Decisions S/O/V/N.
- Produces: five-H2 skill that references all six reference files (created in Tasks 3–4). Links may exist before reference bodies land; Tasks 3–4 fill them.

- [ ] **Step 1: Write SKILL.md**

Create `.apm/packages/refactor/.apm/skills/refactor/SKILL.md` with this content (keep thin for waza ≤500 tokens; do not paste full O1/O2 tables here):

```markdown
---
name: refactor
description: >-
  Apply behavior-preserving structural improvements within O1/O2 and verify with
  stack gates. Use when deduplicating, clarifying expression, or making shallow
  same-package moves — not for lint-driven cleanup, features, dependency upgrades,
  or architecture/GoF redesign.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

Paths/symbols and optional hint/constraints — see [category-input-schema.md](references/category-input-schema.md).
Optional stack routing via caller/user `## Instructions` (A'): named `*-validation` skills.

## Output Specification

Session report per [common-output-format.md](references/common-output-format.md).

## Execution Scope

- Select **one** target per run; stay within [category-scope.md](references/category-scope.md).
- Apply only [category-operations.md](references/category-operations.md) O1/O2; downgrade per V4 when gates are weak.
- Invoke validation skills/commands from `## Instructions` and [category-verification.md](references/category-verification.md).
- Do not invent a dedicated SubAgent product; reuse platform Implementer/Verifier and existing skills.

### USE FOR:

- Behavior-preserving O1/O2 structural edits
- Adding characterization tests/checks when the stack is supported and no net exists
- Invoking named validation skills listed in `## Instructions`

### DO NOT USE FOR:

- Feature work, behavior-changing bugfixes, or dependency upgrades
- Lint/SAST-driven cleanup as the primary mission
- O3 architecture / GoF / deep-module redesign under automation
- Detect ownership or loop state (Phase 2)
- Consuming `docs/report/report-tech-debt/**` as required input

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-scope.md](references/category-scope.md) (always read)
- [category-operations.md](references/category-operations.md) (always read before edits)
- [category-verification.md](references/category-verification.md) - Read before apply and after edits.
- [category-input-schema.md](references/category-input-schema.md) - Read when parsing structured input or future loop envelope.

## Workflow

1. Parse input per [category-input-schema.md](references/category-input-schema.md). If nothing actionable → emit session report with Outcome `no-op`; stop.
2. Load checklist, operations, verification, and scope references.
3. Select **one** target (prefer H1-like hint when present; else user path/symbol). Reject lint-only selection reasons.
4. Establish verification foundation per [category-verification.md](references/category-verification.md) (add characterization tests/checks if required and language supported; else Watch/skip for unsupported stacks).
5. Apply minimal O1/O2 diff. If O2 gate fails → O1 only or Watch.
6. Run stack validation from `## Instructions` / verification reference. On failure → repair once within scope or revert and Watch.
7. Emit structured session report per [common-output-format.md](references/common-output-format.md).
```

- [ ] **Step 2: Structural self-check**

Confirm YAML frontmatter has `name`, `description`, `license`, `metadata.author`, `metadata.version`. Confirm exactly these H2 headings in order: Input → Output Specification → Execution Scope → Reference Files Guide → Workflow.

- [ ] **Step 3: Do not commit**

---

### Task 3: Checklist + output format + scope references

**Files:**

- Create: `.apm/packages/refactor/.apm/skills/refactor/references/common-checklist.md`
- Create: `.apm/packages/refactor/.apm/skills/refactor/references/common-output-format.md`
- Create: `.apm/packages/refactor/.apm/skills/refactor/references/category-scope.md`

**Interfaces:**

- Consumes: Task 2 link names; spec checklist / output / scope norms.
- Produces: H1 commons + H2 category-scope per agent-skills S-03.

- [ ] **Step 1: Write `common-checklist.md`** (must start with `#`)

```markdown
# Refactor Checklist

## Target selection

- Exactly **one** target (path or symbol) per run
- Prefer structure-driven evidence (duplication, oversized unit, user-named symbol) — not lint/SAST smell scores
- Do not require or read `docs/report/report-tech-debt/**`

## Operations

- Stay in O1/O2 closed set (`category-operations.md`)
- No public API semantics changes; no feature behavior changes
- O3 (deep redesign, GoF, large boundary splits) → Watch / stop — do not apply under this skill's automation path

## Verification

- Establish characterization / stack gate before or with the edit (`category-verification.md`)
- If O2 lacks an adequate gate → downgrade to O1 or Watch (V4)
- Unsupported language → Watch / skip — do not invent tests for an unknown stack
- Lint tools may run as part of a stack gate; lint-only findings must not expand the target

## Output

- Emit all session report sections per [common-output-format.md](common-output-format.md)
- Do not claim validation passed when commands failed or were not run

## Error handling

- Nothing actionable → Outcome `no-op`, empty Applied Change, stop
- Validation fails after one in-scope repair → revert or leave Watch; record failure
- Missing validation tooling named in Instructions → note in Session Metrics; Watch unless a single safe O1 clarification remains gated by existing tests
```

- [ ] **Step 2: Write `common-output-format.md`** (must start with `#`)

Create the file with this exact body (the inner report skeleton is indented as an example block in the real file using a fenced `markdown` code block):

````markdown
# Refactor Session Report Format

Use this structure for every run, including no-op exits.

## Session report

```markdown
# Refactor Session Report

## Target

- **Path/symbol:** <one target>
- **Evidence:** <user request | duplication_block | oversized_unit | other structure hint>
- **Tier applied:** <O1 | O2 | none>

## Applied Change

- <minimal diff summary, or "None">

## Characterization / Gates

- **Added or used:** <tests/commands, or "None">
- **Downgrade:** <none | O2→O1 | Watch reason>

## Watch Items

- <deferred O3, unsupported stack, weak gate, or "None">

## Session Metrics

| Field      | Value                                         |
| ---------- | --------------------------------------------- |
| Targets    | <0 or 1>                                      |
| Tier       | <O1 \| O2 \| none>                            |
| Validation | <commands/skills and pass/fail, or "Not run"> |
| Outcome    | <applied \| no-op \| watch \| reverted>       |
```

## Rules

- Always emit all `##` sections; use `None` or `0` when empty.
- `## Session Metrics` MUST use a Field | Value table.
- Do not claim validation passed when commands failed or were not run.
- Do not include tech-debt report paths as required inputs or evidence.
````

- [ ] **Step 3: Write `category-scope.md`** (must start with `##`)

```markdown
## Path Scope

Allowlist and denylist may be supplied by the user, caller Instructions, or (future) loop env. Defaults below are safe dogfood baselines for this config repository; consumers should override.

### Allowlist (dogfood example)

`.apm/packages/**`, `scripts/**`, `docs/**/*.md`, `README.md`, `apm.yml`, `.github/workflows/**`

### Denylist

`**/.env`, `**/credentials*`, `**/secrets*`, `**/migration/*.sql`, `docs/report/**`, `node_modules/**`, `apm_modules/**`, `**/.git/**`

### Rules

- Edit only allowlist paths; never touch denylist paths
- One target per run — do not expand into a repo-wide cleanup
- Generated agent trees (`.agents/`, `.claude/`, `.cursor/`, …) are not edit targets in the config repo; edit `.apm/packages/` sources instead
```

- [ ] **Step 4: Header-level check**

- `common-checklist.md` and `common-output-format.md` first heading level = `#`
- `category-scope.md` first heading level = `##`

- [ ] **Step 5: Do not commit**

---

### Task 4: Input schema + operations + verification references

**Files:**

- Create: `.apm/packages/refactor/.apm/skills/refactor/references/category-input-schema.md`
- Create: `.apm/packages/refactor/.apm/skills/refactor/references/category-operations.md`
- Create: `.apm/packages/refactor/.apm/skills/refactor/references/category-verification.md`

**Interfaces:**

- Consumes: Tasks 2–3; spec O1/O2 table, V4 table, Phase 2 hint kinds (schema only — no detect).
- Produces: remaining category references; all category-\*.md start with `##`.

- [ ] **Step 1: Write `category-input-schema.md`**

````markdown
## Input Schema

Interactive runs may pass free-form path/symbol in the user prompt. When structured JSON is present (interactive helper or future loop envelope), parse:

```json
{
  "target": "path/or/symbol",
  "hint": {
    "kind": "duplication_block",
    "path": "scripts/example.sh",
    "detail": "optional locator"
  },
  "allowlist": [".apm/packages/**", "scripts/**"],
  "denylist": ["docs/report/**"],
  "constraints": {
    "max_tier": "O2"
  }
}
```

| Field                  | Type         | Description                                         |
| ---------------------- | ------------ | --------------------------------------------------- |
| `target`               | string       | Single path or symbol; required when no `hint.path` |
| `hint`                 | object       | Optional structure hint (future detect H1 shapes)   |
| `hint.kind`            | string       | `duplication_block` or `oversized_unit` only        |
| `hint.path`            | string       | Path associated with the hint                       |
| `hint.detail`          | string       | Optional locator (range, symbol name)               |
| `allowlist`            | string[]     | Optional path globs; intersect with defaults        |
| `denylist`             | string[]     | Optional path globs; union with defaults            |
| `constraints.max_tier` | `O1` \| `O2` | Cap operation tier (default `O2`)                   |

### Rules

- If neither actionable `target` nor `hint` → no-op
- `hint.kind` values outside the closed set → ignore hint; fall back to `target` or no-op
- Do **not** accept tech-debt report file paths as required input fields in v1
- Stack skill names are **not** schema fields — they arrive under `## Instructions` (A')
````

- [ ] **Step 2: Write `category-operations.md`**

```markdown
## Allowed Operations (O1 / O2)

Closed operation set for this skill. Anything outside → Watch / stop.

### O1

Allowed:

- Deduplicate repeated logic
- Clarify expression without API or behavior change
- Extract or inline function/module within existing boundaries
- Remove dead branch when behavior equivalence is proven

Forbidden:

- Feature changes
- Public API semantics changes
- Dependency upgrades / CVE-driven edits as the mission

### O2

Allowed:

- Everything in O1
- Shallow move within the **same** package/module boundary
- Import and wiring cleanup required by that move

Forbidden on L2 / automation path:

- Cross-package redesign
- New design patterns (GoF) or deep-module redesign (**O3**)
- Large boundary splits

### O3 (out of scope for this skill's automation path)

Deep-module redesign, GoF introduction, schema/architecture migration — interactive/human only; emit Watch, do not apply under loop L2 expectations.
```

- [ ] **Step 3: Write `category-verification.md`**

```markdown
## Verification (V4)

Stack-specific gates. Prefer existing `*-validation` skills named in `## Instructions` (A').

### Stack table (v1)

| Stack          | Prefer                                                     | If missing foundation                                                 |
| -------------- | ---------------------------------------------------------- | --------------------------------------------------------------------- |
| Go             | `go test` for touched packages                             | Add characterization `*_test.go` for existing behavior, then refactor |
| Shell          | `shellcheck` + bats when suite exists                      | Add/extend bats when domain rules require TEST-00                     |
| Terraform      | `terraform fmt/validate`, tflint; no unintended plan drift | Do not invent terratest in Phase 1                                    |
| GitHub Actions | actionlint / workflow validation skills                    | Reuse validation skills via A'; do not invent new product behavior    |
| Unsupported    | —                                                          | Watch / skip — do not invent tests                                    |

### Characterization tests

- Capture **existing** behavior only — do not expand into feature specs
- Add tests/checks before or in the same change as the refactor when the stack is supported and no net exists
- After tests are green on current behavior, apply O1/O2, then re-run gates

### Downgrade (V4)

- If the gate is insufficient for O2 → apply **O1 only** or Watch
- Lint/SAST may appear inside a stack gate; their findings must **not** become the primary reason to select or expand a target

### Instructions (A')

- Read `## Instructions` for named validation skills and commands
- Do not hardcode consumer skill package paths into this reference
```

- [ ] **Step 4: Header-level check**

All three files start with `##`.

- [ ] **Step 5: Do not commit**

---

### Task 5: Minimal `eval.yaml`

**Files:**

- Create: `.apm/packages/refactor/.apm/skills/refactor/eval.yaml`

**Interfaces:**

- Consumes: sibling pattern from `loop-ci-sweeper` eval.yaml (structure only; no Phase 2 detect assertions).
- Produces: eval stub with graders that assert session report sections exist.

- [ ] **Step 1: Write eval.yaml**

```yaml
name: refactor-eval
description: >-
  Evaluation suite for refactor.
  Verifies session report sections, O1/O2 scope language, and no-op exits.
skill: refactor
version: "1.0"
config:
  trials_per_task: 3
  timeout_seconds: 180
  parallel: false
  executor: mock
  model: claude-sonnet-4-20250514
metrics:
  - name: task_completion
    weight: 1.0
    threshold: 0.8
    description: Verify evaluation task completes successfully.
graders:
  - type: code
    name: has_structured_output
    weight: 1.0
    config:
      assertions:
        - "'Session Metrics' in output"
        - "'Target' in output"
        - "'Applied Change' in output or 'no-op' in output or 'Watch' in output"
  - type: text
    name: report_sections
    weight: 0.5
    config:
      regex_match:
        - (Target|Applied Change|Session Metrics)
  - type: behavior
    name: bounded_runtime
    weight: 0.5
    config:
      max_tool_calls: 30
      max_tokens: 120000
      max_duration_ms: 180000
tasks: []
```

Note: `tasks: []` is intentional for Phase 1 — no eval task fixtures required to ship the skill; graders document the contract. Do not add `evals/tasks/` unless a follow-up asks for dogfood evals.

- [ ] **Step 2: Do not commit**

---

### Task 6: Install, audit, and skill review gates

**Files:**

- Touch via tooling: generated agent skill trees (via `apm install` only — do not hand-edit)
- Verify: `.apm/packages/refactor/**`, installed `refactor` skill under agent roots

**Interfaces:**

- Consumes: Tasks 1–5 complete tree.
- Produces: evidence that package installs and passes review/waza gates.

- [ ] **Step 1: Regenerate install**

Run: `apm install --update`

Expected: success; `refactor` skill appears under configured agent roots (e.g. `.claude/skills/refactor/SKILL.md` and/or `.agents/skills/refactor/SKILL.md`).

- [ ] **Step 2: Package audit**

Run: `apm audit --ci`

Expected: PASS for `config-refactor` / no new package integrity failures.

- [ ] **Step 3: Waza / agent-skills-review scripts**

From the installed `agent-skills-review` skill directory (path may be `.claude/skills/agent-skills-review` or `.agents/skills/agent-skills-review`):

```bash
bash scripts/validate_waza.sh refactor
bash scripts/validate.sh <path-to-refactor-SKILL.md>
```

Expected: waza token budget PASS (or warning only if repo policy treats >500 as warning — fix SKILL.md if MUST fail). `validate.sh` structural checks PASS (S-01 five sections, S-02 frontmatter, reference header levels).

If scripts are missing: run `agent-skills-review` skill workflow manually and record SKIP with reason — still fix any obvious S-01/S-02 issues.

- [ ] **Step 4: Content policy spot-check (manual)**

Confirm by search in `.apm/packages/refactor/`:

- No requirement to read `docs/report/report-tech-debt`
- DO NOT USE FOR / checklist exclude lint-primary mission
- No `detect_refactor`, `loop-refactor`, or SubAgent product definitions

Run: `rg -n 'report-tech-debt|detect_refactor|loop-refactor|SubAgent' .apm/packages/refactor/`

Expected: no matches that couple Phase 1 to those (mentions of “Phase 2” deferral in SKILL DO NOT USE FOR are OK; do not add detect/loop files).

- [ ] **Step 5: Do not commit**

---

### Task 7: Docs pointer (future action loops)

**Files:**

- Modify: `docs/explanation/loop-engineering/index.md`

**Interfaces:**

- Consumes: Phase 1 skill name `refactor`; Phase 2 deferred.
- Produces: short index pointer only — **no** Phase 2 workflow design doc.

- [ ] **Step 1: Add topic index row**

In `docs/explanation/loop-engineering/index.md` topic index table, add a row (after report-tech-debt or in a sensible place):

```markdown
| **refactor** skill (Phase 1); future **loop-refactor** (action loop) | [Refactor skill & loop design](../../superpowers/specs/2026-07-21-refactor-skill-and-loop-design.md) |
```

Do not add mkdocs nav for a Phase 2 workflow design that does not exist yet. Do not create `docs/explanation/loop-engineering/workflows/loop-refactor-workflow-design.md` in Phase 1.

- [ ] **Step 2: Markdown validation (if available)**

Run: `bash .agents/skills/markdown-validation/scripts/validate.sh docs/explanation/loop-engineering/index.md`

Expected: PASS or SKIP if tools missing.

- [ ] **Step 3: Do not commit**

---

### Task 8: Parent review gate + dogfood checklist (no code required)

**Files:**

- None required (optional manual dogfood notes under `tmp/` only if used)

**Interfaces:**

- Consumes: Tasks 1–7 evidence.
- Produces: parent sign-off checklist before claiming Phase 1 done; then invoke **requesting-code-review** (or equivalent) per handoff.

- [ ] **Step 1: Acceptance checklist**

Parent verifies:

1. `.apm/packages/refactor/` exists with `apm.yml` + skill `refactor` + six references + `eval.yaml`
2. Root `apm.yml` lists `./.apm/packages/refactor`
3. `apm install --update` and `apm audit --ci` succeeded
4. Waza / agent-skills-review gates addressed
5. No Phase 2 artifacts (`loop-refactor`, detect, caller workflow)
6. No tech-debt report coupling; lint not center of criteria
7. Index pointer present

- [ ] **Step 2: Optional dogfood (manual)**

Invoke skill `refactor` on a tiny allowlisted fixture path in this repo (e.g. a small duplicated helper under `scripts/` **only if** safe and gated). Prefer dry observation: confirm skill loads references and would no-op cleanly on empty input. Record outcome in the session; do not expand scope.

- [ ] **Step 3: Request code review**

Use **requesting-code-review** (or repo equivalent) on the Phase 1 diff before claiming done.

- [ ] **Step 4: Do not commit** (unless user explicitly asks)

---

## Out of scope (reject if a subagent starts these)

- `.apm/packages/loop-refactor/`
- `detect_refactor.sh` / bats for detect
- `.github/workflows/on-loop-refactor.yaml` or example callers
- Sonar / CPD integration
- Putting Apply into `loop-report-tech-debt`
- O3 automation, GoF catalogs as L2 ops
- Hardcoding named validation skills inside `references/` (breaks A')

## Spec coverage (self-review)

| Spec item                            | Task                              |
| ------------------------------------ | --------------------------------- |
| Package layout Phase 1               | 1–5                               |
| Skill contract USE/DO NOT / workflow | 2–4                               |
| O1/O2 normative                      | 4 (`category-operations.md`)      |
| V4 + characterization                | 4 (`category-verification.md`)    |
| S2 + A' Instructions                 | 2, 4                              |
| No lint-primary / no tech-debt feed  | 2–4, 6 spot-check                 |
| No SubAgent product                  | 2 Execution Scope                 |
| eval/waza readiness                  | 5–6                               |
| Docs future pointer                  | 7                                 |
| Phase 2 deferred                     | Global Constraints + Out of scope |

## Placeholder scan

No TBD/TODO steps; reference bodies inlined; commands explicit; commits deferred to user ask.
