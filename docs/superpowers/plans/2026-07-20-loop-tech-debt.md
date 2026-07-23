# loop-tech-debt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce the `loop-tech-debt` report loop (L2 from day one) with design documentation first, then rename package/skill, enrich detect JSON, and add the caller workflow.

**Architecture:** Report loops use the `loop-report-<domain>` naming family. Detect scripts emit all skill-input fields (same layer as `detect_changes.sh` / `detect_changelog_commits.sh`). L2 writes `docs/report/tech-debt/YYYY-MM-DD.md` via merge-gated PR. No GitHub Issue creation at any level.

**Tech Stack:** APM packages, GitHub Actions (`ci-loop-caller.yaml`), bash detect scripts, loop-tech-debt skill references.

## Global Constraints

- Report family prefix: `loop-report-<domain>` (e.g. `loop-tech-debt`, future `loop-report-errors`).
- Full APM rename: `.apm/packages/loop-tech-debt` → `loop-tech-debt` (package, skill, detect, evals).
- `loop_name`: `tech-debt`; state: `.loop/state-tech-debt.json`.
- Caller workflow: `on-loop-tech-debt.yaml`.
- Report path: `docs/report/tech-debt/YYYY-MM-DD.md`.
- Level: **L2 from start** (skip L1 observation phase).
- `no_changes_verdict`: `REJECT` when signals present but no report file written.
- Cron: Monday 08:00 UTC, weekly.
- Budget (caller default): `budget_max_runs_per_day: 2`, `budget_max_tokens_per_day: 750000`.
- No GitHub Issue creation (log + state + report PR only).
- Detect enrich fields (`report_file`, `previous_report`) live in `detect_tech_debt.sh`; sensors live in `detect_tech_debt_sensors.sh`.
- Refactoring loops (`loop-refactor-*`) are **action loops**, not report loops — mention only as future work in design doc.
- Workflow keys alphabetically ordered; follow `loop-docs-triage-workflow-design.md` structure.
- Do not edit generated dirs (`.agents/`, `.cursor/`, etc.) — edit `.apm/packages/` then `apm install --update`.

---

### Task 1: Workflow design doc + cross-references

**Files:**

- Create: `docs/explanation/loop-engineering/workflows/loop-tech-debt-workflow-design.md`
- Modify: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md` (per-loop table + detect env section)
- Modify: `docs/explanation/loop-engineering/index.md` (topic index row)
- Modify: `docs/explanation/loop-engineering/multi-branch-loops-design.md` (workflow design documents table)
- Modify: `mkdocs.yml` (nav entry under Loop Workflows)

**Interfaces:**

- Produces: design doc that downstream Tasks 2–4 implement against.

- [ ] **Step 1: Write design doc**

Create `loop-tech-debt-workflow-design.md` following `loop-docs-triage-workflow-design.md` structure. Include:

1. **Purpose** — full-repo mechanical debt scan → classify → L2 report PR.
2. **Report loop family** — `loop-report-<domain>` convention; contrast with action loops (docs-triage, ci-sweeper, future refactor).
3. **Out of scope** — code fixes, Issue creation, L1 log-only phase (skipped), CVE DB, lint duplication.
4. **Caller inputs table** with dogfood values:

| Input                           | Dogfood value                                                                                   |
| ------------------------------- | ----------------------------------------------------------------------------------------------- |
| `level`                         | `L2`                                                                                            |
| `loop_name`                     | `tech-debt`                                                                                     |
| `skill_name`                    | `loop-tech-debt`                                                                                |
| `detect_script`                 | `.agents/skills/loop-tech-debt/scripts/detect_tech_debt.sh`                                     |
| `allowlist`                     | `docs/report/tech-debt/**/*.md`                                                                 |
| `denylist`                      | `**/.env,**/credentials*,**/secrets*,**/migration/*.sql,**/infrastructure/**,src/**,.github/**` |
| `no_changes_verdict`            | `REJECT`                                                                                        |
| `pr_enabled`                    | `false`                                                                                         |
| `branch_match` / `branch_state` | `main`                                                                                          |
| `budget_max_runs_per_day`       | `2`                                                                                             |
| `budget_max_tokens_per_day`     | `750000`                                                                                        |
| `max_targets_per_schedule`      | `1`                                                                                             |
| `agent_implementer_max_turns`   | `5`                                                                                             |
| `agent_loop_max_attempts`       | `3`                                                                                             |
| `agent_implementer_model`       | `cursor-grok-4.5-low`                                                                           |
| `agent_verifier_model`          | `composer-2.5`                                                                                  |
| `engine`                        | `cursor`                                                                                        |
| `pr_title`                      | `docs(report): technical debt report (loop-tech-debt)`                                          |
| Cron                            | `0 8 * * 1` (Monday 08:00 UTC)                                                                  |

5. **Detect section** — detect outputs: `signals[]`, `hotspots[]`, `warnings[]`, `skip`, `report_file`, `previous_report`. Note full-repo default scope.
6. **Skill section** — classify per taxonomy; write `report_file` at L2; session summary always.
7. **Verifier rubric outline** — report-only allowlist; no invented paths; cap 25 Critical+High.
8. **Future work** — one paragraph: refactor loops are action loops (`loop-refactor-*` TBD), not report family.

- [ ] **Step 2: Update cross-references**

Add row to per-loop tables in:

- `loop-caller-inputs-reference.md` (design doc link + caller `on-loop-tech-debt.yaml`)
- `multi-branch-loops-design.md` workflow design documents table
- `index.md` topic index
- `mkdocs.yml` nav: `- Report Tech Debt: explanation/loop-engineering/workflows/loop-tech-debt-workflow-design.md`

- [ ] **Step 3: Validate markdown**

Run: `bash .agents/skills/markdown-validation/scripts/validate.sh docs/explanation/loop-engineering/workflows/loop-tech-debt-workflow-design.md docs/explanation/loop-engineering/index.md mkdocs.yml`

Expected: PASS (or note SKIP if tools missing).

- [ ] **Step 4: Do not commit** (user did not request commit)

---

### Task 2: APM package rename (next PR)

**Files:**

- Rename: `.apm/packages/loop-tech-debt/` → `.apm/packages/loop-tech-debt/`
- Update: `apm.yml` dependency entry
- Regenerate: `apm install --update`

Rename skill references: `loop-tech-debt` → `loop-tech-debt` throughout package.
Update report paths in `category-scope.md`, `category-input-schema.md`, `common-output-format.md`, `common-checklist.md`, SKILL.md.

---

### Task 3: Detect enrich + rename script (next PR)

**Files:**

- Rename: `detect_tech_debt.sh` → `detect_tech_debt.sh`
- Modify: `output_json` to add `report_file`, `previous_report`
- Update: bats suite path and assertions
- Prune path: `docs/report/**` stays excluded from sensors

`report_file` = `docs/report/tech-debt/$(date -u +%Y-%m-%d).md`
`previous_report` = latest existing file in that directory (empty string if none)

---

### Task 4: Caller workflow (next PR)

**Files:**

- Create: `.github/workflows/on-loop-tech-debt.yaml`
- Create: `.github/workflows/example/on-loop-tech-debt.yaml` (remote SHA pin)
- Update: `.loop/loop-budget.json` with `tech-debt` entry

Follow design doc caller inputs exactly.
