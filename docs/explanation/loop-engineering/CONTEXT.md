# Loop Engineering

Autonomous repository maintenance via scheduled or event-triggered GitHub Actions callers, bounded Agent→Verify execution, and domain-specific detect scripts.

## Language

**Detect Phase**:
Mechanical extraction of facts that may produce loop targets. Emits structured JSON (`failures[]`, `changed_files`, `commits[]`, …). Does not commit fixes.
_Avoid_: Execute, repair, triage (when meaning "fix")

**Execute Phase**:
Bounded Agent→Verify session in a worktree. May edit files at L2+. Driven by prompt, allowlist, and an entry skill.
_Avoid_: Detect, finalize

**Verify Phase**:
Separate agent pass that APPROVE/REJECTs the implementer diff against caller criteria and `verifier_context`. Does not re-run CI.
_Avoid_: Validation (skill-run checks inside execute)

**Finalize Phase**:
Platform step after APPROVE — open PR, push, ledger/state updates.
_Avoid_: Execute, detect

**Entry Skill**:
The skill named in the loop prompt (`skill_name` input). May orchestrate other skills or perform repair directly.
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
How the agent fixes a target (which domain skills, minimal diff scope, Watch/defer). Owned primarily by entry skill quality and prompt; bounded by allowlist and verifier.
_Avoid_: Detect, routing (when implying mechanical routers)

**Caller Instructions**:
Repo-specific text in `prompt_instructions`, appended to the implementer prompt under `## Instructions`. Includes **stack routing (A')** — which domain skills to invoke for this repository (workflow names, stacks, skill paths). This is the coupling point between caller and consumer skill catalog.
_Avoid_: Entry skill (for named skill paths)

**Stack Routing (A')**:
Mapping from CI failure context (workflow name, log tool, optional detect `stack_hint`) to domain validation/repair skills. **Primary source: caller `prompt_instructions`** (e.g. `on-loop-ci-sweeper.yaml`). Entry skill describes generic orchestration only — read `## Instructions` for dispatch; do not hardcode consumer skill names in distributable skill `references/`.
_Avoid_: Entry skill references (for named skill coupling)

**Failure Kind Defer (B)**:
Rules that defer certain failure kinds (coverage threshold, dependency breakage) to Watch or future domain skills. **Generic defer rules** in entry skill (`DO NOT USE FOR`, checklist). **Named skills and REJECT criteria** in caller `agent_verifier_criteria` appendix.
_Avoid_: Detect gate (for defer policy alone); named skills in entry skill references

**GitHub API Action (Execute)**:
Issue labels, comments, or PR comments applied during **Execute** by the entry skill (via `gh` / API) — not Finalize. Caller supplies permissions; verifier confirms API outcome fit. Finalize records state cursor and run-log.
_Avoid_: Finalize (for label/comment delivery)
