# Loop Engineering Checklist

Operational checklist for creating and promoting loops.
For design rationale, see [Loop Engineering Design](../explanation/loop-engineering-design.md).

## New Loop Creation Checklist

Use when implementing a new `on-loop-*.yaml` workflow.

### Design Invariants

All must be true. Violation of any item is a blocking issue.

- [ ] Agent never writes to the default branch directly
- [ ] Verifier never modifies the repository (read-only phase)
- [ ] Detect never writes state
- [ ] Finalize never changes source code
- [ ] State advances only through Finalize
- [ ] Each phase communicates only via GitHub Actions outputs/inputs (no implicit filesystem coupling)
- [ ] Checkout is performed by the caller workflow, not by composite actions
- [ ] Every decision is traceable (skip reason, reject reason, outcome are recorded)

### Phase Contract Compliance

#### Detect

- [ ] Outputs `skip` (bool) and structured `result`
- [ ] Read-only — does not modify repository or state
- [ ] Detection logic is inline in the caller (not in a reusable workflow or action)
- [ ] Uses `loop-state-read` for previous SHA retrieval
- [ ] Uses `loop-prompt-generate` for prompt assembly

#### Agent (Execute)

- [ ] Outputs `branch` (string) and `has_changes` (bool)
- [ ] At L2/L3, also outputs `verdict`, `reason`, and `attempts` from the bounded Agent→Verify loop
- [ ] Operates on an isolated branch only (never default branch)
- [ ] Respects Skill's allowed paths
- [ ] Does not touch files on denylist
- [ ] Uses reusable workflow `ci-loop-agent.yaml` (`loop-agent-once` at L1; `loop-worktree-setup` + `loop-execute` at L2/L3)

#### Verify

- [ ] Outputs `verdict` (APPROVE/REJECT) and `reason`
- [ ] Read-only — does not modify repository
- [ ] Runs as a separate agent session from the implementer (Maker-Checker inside `loop-execute`)
- [ ] Evaluates semantic quality only (factual accuracy, relevance, no hallucination)
- [ ] Does not evaluate lint/CI concerns (that is CI's job)
- [ ] Uses a model equal to or more powerful than the Agent model
- [ ] Denylist is passed and enforced
- [ ] Verification runs inside `loop-execute` (via `ci-loop-agent.yaml`); there is no separate `ci-loop-verifier` workflow

#### Finalize

- [ ] Creates PR on APPROVE, deletes branch on REJECT
- [ ] Updates state file with outcome, SHA, and reject reason (if applicable)
- [ ] Does not perform notifications or trigger downstream workflows
- [ ] Runs with `if: always()` condition (with appropriate guards)
- [ ] Uses `loop-finalize` action

#### Skill

- [ ] SKILL.md defines allowed paths explicitly
- [ ] Self-contained (no references to external skills)
- [ ] Includes behavioral rules and constraints
- [ ] Does not guarantee correctness (that is Verifier's job) or CI passing (that is CI's job)

### Workflow Structure

- [ ] `concurrency` group prevents parallel executions of the same loop
- [ ] `timeout-minutes` set for all jobs
- [ ] `permissions` follow least privilege per job
- [ ] env keys are alphabetically ordered
- [ ] State file path is unique to this loop (`.loop/state-<domain>.json`)
- [ ] Denylist includes: `**/.env`, `**/credentials*`, `**/secrets*`, `**/migration/*.sql`, `**/infrastructure/**`

### Retry Policy

- [ ] SHA advances on every successful Finalize (no same-diff retry)
- [ ] Only detect-phase failures or cancellations leave SHA unchanged
- [ ] State records `consecutive_failures` count
- [ ] State records `last_reject_reason` on REJECT
- [ ] Loop pauses (skip=true) after 3+ consecutive failures

---

## L1 → L2 Promotion Checklist

All must be satisfied before promoting a loop from L1 (Report) to L2 (Assisted).

### Prerequisites

- [ ] Loop has operated at L1 for 2+ weeks without incident
- [ ] State file schema is documented
- [ ] SKILL.md includes build/test commands

### Safety

- [ ] Implementer and verifier are separate agent sessions
- [ ] Denylist explicitly includes auth, payments, secrets, and infrastructure paths
- [ ] Auto-merge eligible paths are restricted via allowlist (L2 does not auto-merge by default)

### Budget

- [ ] Daily token cap is configured
- [ ] Maximum sub-agent count is configured

### Observability

- [ ] Approval Rate is tracked (target: > 70%)
- [ ] Consecutive failure count is monitored (alert at 3+)

---

## L2 → L3 Promotion Checklist

All must be satisfied over a 2-week window before promoting to L3 (Unattended).

### Metrics Gate

- [ ] Approval Rate > 80%
- [ ] PR Merge Rate > 90%
- [ ] Human Override Rate < 10%

### Safety Gate

- [ ] Denylist + budget cap + metrics + human gate are all established
- [ ] Stop conditions are defined (Slow Down / Pause / Kill triggers)
- [ ] Branch protection with Required Status Checks is enforced
- [ ] Auto-merge restricted to path allowlist only

### Operational Readiness

- [ ] Weekly digest is configured for team visibility
- [ ] Medium-risk changes route to human gate
- [ ] Escalation path is defined for consecutive failures
