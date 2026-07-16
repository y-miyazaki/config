# Loop Engineering Checklist

Operational checklist for creating and promoting loops.
For design rationale, see [Loop Engineering Design](../explanation/loop-engineering/loop-engineering-design.md).

## New Loop Creation Checklist

Use when implementing a new `on-loop-*.yaml` workflow. Add `docs/explanation/loop-engineering/workflows/loop-<name>-workflow-design.md` for domain specifics.

### Design Invariants

All must be true. See [Loop Engineering Design — Design Invariants](../explanation/loop-engineering/loop-engineering-design.md#design-invariants).

- [ ] Agent never writes to integration branches during Execute (isolated worktree only). L3 integration `push` in Finalize only, with promotion gate
- [ ] Verifier never modifies the repository (read-only phase)
- [ ] Detect never writes state; **detect script invoked once per run** (no caller re-run)
- [ ] Finalize never changes **source under repair**; `.loop/*` persistence allowed
- [ ] State advances only through Finalize (and merge-gated promote for L2 `open_pr` — see Finalize below)
- [ ] Phases communicate via GitHub Actions outputs/inputs only
- [ ] Checkout is performed by the caller workflow
- [ ] Every decision is traceable (`skip_reason`, reject reason, outcome)

### Detect vs Execute (semantic boundary)

See [CONTEXT — Semantic Findings](../explanation/loop-engineering/CONTEXT.md#language).

- [ ] Detect script emits mechanical **facts** only (`failures[]`, `changed_files`, `commits[]`, …) inside the common envelope (`skip`, `result`, `verifier_context`)
- [ ] Detect does **not** emit semantic `findings[]`, triage prose, or repair decisions
- [ ] Entry skill builds semantic output (`findings[]`, Fix/Watch/Escalate) in Execute from detect facts
- [ ] `verifier_context` carries fact summary or log excerpt for verify — not skill triage report

### Phase Contract Compliance

#### Detect

- [ ] Outputs `should_run`, `skip_reason`, `target_matrix` via `loop-detect`
- [ ] Read-only — does not modify repository or state
- [ ] `LOOP_DETECT_SCRIPT` under loop skill package (`scripts/detect_*.sh`)
- [ ] Budget / circuit breaker / `peer_active` (`acting_on`) guards via `loop-detect`
- [ ] No domain vocabulary in `loop-*` actions

#### Agent (Execute)

- [ ] L2/L3 outputs `branch`, `has_changes`, `verdict`, `reason`, `attempts`, `open_rejections`, `usage_json`, `notify_context_json`
- [ ] Worktree from `target.from` (Phase 1+)
- [ ] Respects Skill allowed paths and denylist
- [ ] Uses `ci-loop-agent.yaml`

#### Verify

- [ ] Separate agent session from implementer (inside `loop-execute`)
- [ ] Read-only; outputs `verdict`, `reason`, `open_rejections`
- [ ] Semantic quality + fit against `verifier_context` (always wired; may be empty)
- [ ] `verifier_context` wired on every execute matrix cell

#### Finalize

- [ ] Behavior matches [finalize strategy matrix](../explanation/loop-engineering/loop-engineering-design.md#finalize-strategy-matrix) for `target.finalize` + `DEFAULT_LEVEL`
- [ ] **L2 `open_pr`:** merge-gated cursor — `loop-finalize` writes `pending`; `last_sha` advances only when fix PR merges via `on-loop-state-promote.yaml` (label `loop-automation`). Fix PR is domain-only — see [State delivery philosophy](../explanation/loop-engineering/multi-branch-loops-design.md#state-delivery-philosophy)
- [ ] `open_pr`: create PR on APPROVE; `push` / `push_head`: push on APPROVE; delete agent branch on REJECT
- [ ] L3 `auto_merge` only when `finalize=open_pr` — not for `push` / `push_head`
- [ ] State, run-log, domain ledger via `domain_persistence_script` in finalize job (no caller `git push` for `.loop/*`)
- [ ] `outcome: watch` for Skill Watch (no `consecutive_failures` increment)
- [ ] `loop-finalize` + `if: always()` with appropriate guards
- [ ] `loop-notify-pr` when `target_json.to.pr_number` is set ([spec](loop-notify-pr-specification.md)); includes bot fix PR link for `pull_request` + `open_pr`
- [ ] `pr_exclude` for PR-head watch; no `pr_require` label opt-in
- [ ] GitHub-entity loops (issue/stale): caller grants `issues: write` / `pull-requests: write`; skill performs API actions in **Execute**; Finalize advances state cursor (no file PR at L1)

#### Skill

- [ ] SKILL.md: allowed paths, behavioral rules, generic orchestration
- [ ] **No named consumer domain skills** in distributable skill `references/` (caller `prompt_instructions` owns stack routing A')
- [ ] CI failure loops: caller `agent_verifier_criteria` appendix for failure-kind defer (B) where needed

#### Caller (`on-loop-*.yaml`)

- [ ] `prompt_instructions` includes repo-specific overlay (stack routing table for `loop-ci-sweeper`-type loops)
- [ ] `agent_verifier_criteria` matches observation trigger (CI log fit, doc factual accuracy, changelog version rules, …)
- [ ] Fix PRs labeled `loop-automation` for `on-loop-state-promote` matching

### Multi-Branch Targets (Phase 1+)

See [Multi-Branch Loops Design](../explanation/loop-engineering/multi-branch-loops-design.md) and [Loop Caller Workflows](../explanation/loop-engineering/loop-caller-workflows-design.md).

- [ ] `LOOP_INTEGRATION_BRANCHES` and/or `LOOP_PULL_REQUESTS` (`pr_enabled`) in caller `with:`
- [ ] `target_matrix` with `mode`, `from`, `to`, stable `key` per cell
- [ ] Matrix execute/finalize; capped by `LOOP_MAX_TARGETS_PER_SCHEDULE`
- [ ] `LOOP_PR_EXCLUDE`; bots excluded unless `LOOP_PR_INCLUDE_BOTS`
- [ ] `DEFAULT_LEVEL=L2` unless L3 gate passed; L3 = auto-merge on bot fix PR when `finalize=open_pr`
- [ ] Per-target `concurrency.group` when using matrix fan-out

### Workflow Structure

- [ ] Follows [Loop Caller Workflows Design](../explanation/loop-engineering/loop-caller-workflows-design.md)
- [ ] `timeout-minutes` on all jobs; least-privilege permissions per job
- [ ] env keys alphabetically ordered
- [ ] Unique state file (`.loop/state-<loop>.json`)
- [ ] Denylist includes standard paths

### Retry Policy

- [ ] **State cursor (general):** L2 `open_pr` → merge-gated `pending`; API-only / no file diff → cursor on verifier APPROVE in same finalize run; L3 push → cursor in same finalize run
- [ ] `consecutive_failures` + `attempt_fingerprint` on `target.key`
- [ ] Pause at 3+ consecutive failures (`circuit_breaker`)

---

## L1 → L2 Promotion Checklist

- [ ] Loop operated at L1 for 2+ weeks
- [ ] State schema documented in workflow design doc
- [ ] SKILL.md includes build/test commands (or GitHub-entity deliverable rules for non-file loops)
- [ ] Implementer and verifier separate sessions
- [ ] Denylist includes auth, payments, secrets, infrastructure
- [ ] Daily token cap configured
- [ ] `.loop/loop-run-log.md` in use

---

## L2 → L3 Promotion Checklist

- [ ] Approval Rate > 80%, PR Merge Rate > 90%, Human Override Rate < 10% (2 weeks)
- [ ] [cobusgreyling Pre-Flight Safety](https://github.com/cobusgreyling/loop-engineering/blob/main/docs/safety.md#pre-flight-safety-check) complete
- [ ] L3 enables GitHub auto-merge on bot fix PRs (`finalize=open_pr`); never default `DEFAULT_LEVEL=L3` for new adopters
- [ ] Stop conditions and escalation path defined

