# Loop Engineering

Autonomous repository maintenance via scheduled or event-triggered GitHub Actions callers, bounded Agent→Verify execution, and domain-specific detect scripts.

This page is the ubiquitous language for **this repository**. [cobusgreyling/loop-engineering](https://github.com/cobusgreyling/loop-engineering) is a pattern catalog. Roles are Maker/Checker; pipeline phases stay Detect / Execute / Verify / Finalize. See [Phase vs role vs artifact](#phase-vs-role-vs-artifact).

## Language

**Detect Phase**:
Mechanical extraction of facts that may produce loop targets. Emits structured JSON (`failures[]`, `changed_files`, `commits[]`, …). Does not commit fixes.
_Avoid_: Execute, repair, triage (when meaning "fix")

**Execute Phase**:
Bounded Maker session in a worktree (`agent_maker_*`). May edit files at L2+. Driven by prompt, allowlist, and an entry skill. With Verify, this is one Agent→Verify run inside `loop-execute`.
_Avoid_: Detect, finalize

**Verify Phase**:
Separate Checker pass that APPROVE/REJECTs the Maker diff against caller criteria and `verifier_context` (`agent_checker_*`). Does not re-run CI.
_Avoid_: Validation (skill-run checks inside execute)

**Finalize Phase**:
Platform step after APPROVE — open PR, push, ledger/state updates.
_Avoid_: Execute, detect

**Entry Skill**:
The skill named in the loop prompt (`agent_maker_skill_name` input). May orchestrate other skills or perform repair directly.
_Avoid_: Loop package, domain skill (when meaning the same thing)

**Domain Skill**:
Any skill under agent roots (`.agents/skills`, `.claude/skills`, …) the entry skill or agent invokes for specialized repair or validation.
_Avoid_: Loop package

**Loop Package**:
APM distributable unit: entry skill + detect script (+ optional ledger script). Bound to one observation trigger family.
_Avoid_: Skill, workflow

**Observation Trigger**:
What causes detect to run and what facts it can see (failed workflow run, git diff on branch, conventional commits, CI artifacts, …).
_Avoid_: Detect method, cron

**CI Failure Sensor**:
Detect path that lists failed workflow runs (`ci-sweeper` / `detect_ci_failures.sh`). One observation trigger family among several.
_Avoid_: CI sweeper (when meaning the whole loop), self-healing CI

**Target**:
One matrix cell after detect — branch/PR context, detect JSON, prompt, verifier context.
_Avoid_: Job, failure

**Semantic Findings**:
Structured triage output (`findings[]`, classification, `ignored[]`) produced in **Execute** by the entry skill from detect **facts**. Never emitted by detect scripts.
_Avoid_: Detect output, mechanical facts

**Repair Strategy**:
How the agent fixes a target (which domain skills, minimal diff scope, Watch/defer). Owned primarily by entry skill quality and prompt; bounded by allowlist and Checker.
_Avoid_: Detect, routing (when implying mechanical routers)

**Caller Instructions**:
Repo-specific text in `agent_maker_instructions`, appended to the Maker prompt under `## Instructions`. Includes **stack routing (A')** — which domain skills to invoke for this repository (workflow names, stacks, skill paths). This is the coupling point between caller and consumer skill catalog.
_Avoid_: Entry skill (for named skill paths)

**Stack Routing (A')**:
Mapping from CI failure context (workflow name, log tool, optional detect `stack_hint`) to domain validation/repair skills. **Primary source: caller `agent_maker_instructions`** (e.g. `on-loop-ci-sweeper.yaml`). Entry skill describes generic orchestration only — read `## Instructions` for dispatch; do not hardcode consumer skill names in distributable skill `references/`.
_Avoid_: Entry skill references (for named skill coupling)

**Failure Kind Defer (B)**:
Rules that defer certain failure kinds (coverage threshold, dependency breakage) to Watch or future domain skills. **Generic defer rules** in entry skill (`DO NOT USE FOR`, checklist). **Named skills and REJECT criteria** in caller `agent_checker_instructions` appendix.
_Avoid_: Detect gate (for defer policy alone); named skills in entry skill references

**GitHub API Action (Execute)**:
Issue labels, comments, or PR comments applied during **Execute** by the entry skill (via `gh` / API) — not Finalize. Caller supplies permissions; the Checker confirms API outcome fit. Finalize records state cursor and run-log.
_Avoid_: Finalize (for label/comment delivery)

**Maker / Checker** (roles):
Two agent sessions in one `loop-execute` run. **Maker** edits (or surveys) in Execute (`agent_maker_*`). **Checker** APPROVE/REJECTs in Verify (`agent_checker_*`, skill often `loop-verifier`). Same agent session must not hold both roles.
_Avoid_: Implementer, Verifier (retired role names); renaming `loop-verifier` in the same change as GHA inputs

**Autonomy Level**:
`level` on the caller: **L1 (Report)** / **L2 (Assisted)** / **L3 (Unattended)**. Skills must not branch on `level`.
_Avoid_: Observe (do not use for L1)

## Phase vs role vs artifact

Three layers. Do not collapse them.

| Layer | Names | What it is |
| ----- | ----- | ---------- |
| **Phase** (job boundary) | Detect, Execute, Verify, Finalize | Pipeline steps. **Verify** stays a phase name even though the agent is the Checker |
| **Role** (who acts) | Maker, Checker | LE primitive. Maker ≈ old Implementer. Checker ≈ old Verifier |
| **Artifact / skill** | `verifier_context`, `loop-verifier` | Payload and skill id. Not renamed with the roles |

| Retired identifier | Current |
| ------------------- | ------- |
| `agent_implementer_*` | `agent_maker_*` |
| `agent_verifier_instructions` / `_model` / `_max_turns` / `_skill_name` | `agent_checker_*` |
| Implementer / Verifier (prose for the agent) | Maker / Checker |

Keep as-is: Verify phase, `verifier_context`, `VERIFIER_CONTEXT`, `loop-verifier`, validation inside Execute (`validate_agent_report.sh`).

## Terminology bridge

Catalog ([loop-engineering](https://github.com/cobusgreyling/loop-engineering)) vs this repository. Roles are Maker/Checker here; phases stay Detect / Execute / Verify / Finalize.

| Catalog | This repository |
| ------- | --------------- |
| Pattern (`patterns/registry.yaml`) | Loop (`loop_name`, `on-loop-<loop_name>.yaml`). Names need not match |
| Triage skill | Detect (facts) + Execute entry skill (semantic findings) |
| Implementer / Maker sub-agent | Execute **Maker** session (`agent_maker_*`) |
| Verifier / Checker sub-agent | Verify **Checker** session (`agent_checker_*`; skill `loop-verifier`) |
| `STATE.md` / `LOOP.md` | `.loop/state-*.json`, `loop-run-log.md`, `loop-budget.json`; design docs under this folder |
| Loop Ready Score (`loop-audit`) | [Loop Engineering Checklist](../../reference/loop-engineering-checklist.md) |
| L1 Report / L2 Assisted / L3 Unattended | Same labels. L1 is **Report**, never Observe |
| Human gate | L2 merge of the fix PR, L3 allowlist auto-merge, or escalate — not a fifth pipeline job |
| `/loop` scheduler | GitHub Actions `on-loop-*` |
