# Loop Caller Workflows Design

Shared GitHub Actions layout for `on-loop-*.yaml` caller workflows.

**Scope:** job graph, `target_matrix` handoff, triggers, concurrency, matrix fan-out, persistence job structure.  
**Out of scope:** domain detect logic — see [workflow designs](multi-branch-loops-design.md#workflow-design-documents). Platform target model — [Multi-Branch Loops Design](multi-branch-loops-design.md).

> **Refactor complete:** Job graph lives in `ci-loop-caller.yaml`; each `on-loop-*.yaml` is a thin caller (`with:` only, no `env:`). See [Loop Caller Reusable Workflow Design](loop-caller-reusable-design.md).

## Files

| Type     | Path                                                  | Role                                           |
| -------- | ----------------------------------------------------- | ---------------------------------------------- |
| Caller   | `.github/workflows/on-loop-<name>.yaml`               | Triggers, concurrency; loop config via `with:` |
| Reusable | `.github/workflows/ci-loop-caller.yaml`               | Shared detect → execute → record-skip          |
| Reusable | `.github/workflows/ci-loop-agent.yaml`                | L1/L2/L3 execute (`loop-execute`)              |
| Actions  | `y-miyazaki/config` `loop-detect`, `loop-finalize`, … | Generic phases                                 |

## Job Graph

```text
detect (single job)
  → loop-detect
  → outputs: target_matrix (slim), handoff_artifact_name, should_run, skip_reason
  → uploads loop-handoff artifact (full result + verifier_context per target)

execute (matrix: target_matrix)
  → ci-loop-agent.yaml per cell (optional finalize job when finalize_enabled=true)
  → downloads loop-handoff artifact; resolves payloads by handoff_key
  → inputs: target_json, prompt, handoff_key, finalize config, …

record-skip (optional)
  → loop-run-log when should_run=false and skip_reason=budget|circuit_breaker
  → not used for target_budget (execute still runs; deferral is informational)
```

## Detect Job

### Required outputs

| Output                  | Source                                                                                                                  |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `should_run`            | `loop-detect` — true when `target_matrix` is non-empty                                                                  |
| `skip_reason`           | `loop-detect`                                                                                                           |
| `handoff_artifact_name` | `loop-detect` — artifact name for execute download (empty when `should_run=false`)                                      |
| `target_matrix`         | Slim JSON array of candidates (see [Specification](../../reference/specification.md#job-handoff-loop-handoff-artifact)) |
| Config passthrough      | `level`, models, allowlist, `state_file`, …                                                                             |

Each slim matrix cell carries: `target_json`, `prompt`, `handoff_key`. Full `result` and `verifier_context` live in the **loop-handoff** artifact (`payloads/<sanitized-key>.json`).

### Anti-pattern: double detect

**Forbidden:** invoking the detect script again in a caller `run:` step after `loop-detect`.

Remove Phase 0 debt: `on-loop-ci-sweeper.yaml` `Export Target Failure Context`.

### Target selection (inside `loop-detect`)

1. Read [caller `env`](multi-branch-loops-design.md#caller-configuration-canonical).
2. Enumerate integration branches / PRs; checkout per context; run `detect_script` per context.
3. Apply [trigger-aware priority](multi-branch-loops-design.md#trigger-aware-priority).
4. Cap at `LOOP_MAX_TARGETS_PER_SCHEDULE`; excess → `target_budget` on next cron.

## Execute Job (matrix)

Reusable workflow matrix cells cannot pair `needs.execute.outputs.*` with a separate finalize matrix job — GitHub Actions collapses reusable-workflow outputs across cells. **Finalize runs inside `ci-loop-agent.yaml`** when the caller sets `finalize_enabled: true`.

```yaml
execute:
  needs: detect
  if: needs.detect.outputs.should_run == 'true'
  strategy:
    matrix:
      target: ${{ fromJson(needs.detect.outputs.target_matrix) }}
  uses: ./.github/workflows/ci-loop-agent.yaml
  with:
    base_branch: ${{ matrix.target.target_json.mode == 'pull_request' && matrix.target.target_json.base.branch || matrix.target.target_json.to.branch }}
    current_sha: ${{ matrix.target.target_json.from.ref }}
    detect_result_json: "{}"
    finalize_enabled: true
    handoff_artifact_name: ${{ needs.detect.outputs.handoff_artifact_name }}
    handoff_key: ${{ matrix.target.handoff_key }}
    prompt_text: ${{ matrix.target.prompt }}
    target_json: ${{ toJson(matrix.target.target_json) }}
    # … passthrough from detect + finalize config
```

`target_json` is required. `verifier_context` and `result` are resolved at runtime from the loop-handoff artifact (or inline `detect_result_json` when non-empty).

**`DEFAULT_LEVEL` vs finalize:**

```yaml
auto_merge: ${{ needs.detect.outputs.level == 'L3' && matrix.target.target_json.finalize == 'open_pr' }}
```

## Finalize (inside ci-loop-agent)

When `finalize_enabled=true`, `ci-loop-agent` runs `loop-finalize` after `agent-l2` in the **same workflow instance**, preserving execute output pairing per matrix cell.

When `target_json.to.pr_number` is set, `ci-loop-agent` runs `loop-notify-pr` as a **sibling step** immediately after `loop-finalize` (not nested inside the composite — see [composite action composition](../../reference/specification.md#composite-action-composition)). See [loop-notify-pr Specification](../../reference/loop-notify-pr-specification.md).

### Persistence layer

All `.loop/*` writes in **finalize step** via `loop-finalize` — not separate caller `git push` steps.

| Input                       | Example                                                          |
| --------------------------- | ---------------------------------------------------------------- |
| `target_json`               | Matrix cell                                                      |
| `domain_persistence_script` | loop-ci-sweeper: `update_run_ledger.sh`; loop-docs-triage: empty |
| `state_push_branch`         | `LOOP_STATE_PUSH_BRANCH` or default branch                       |

Push branch: `LOOP_STATE_PUSH_BRANCH`, **not** `target.to.branch`.

**Merge-gated state (L2 `open_pr`):** `loop-finalize` writes `pending` to `branch_state` after creating the domain-only PR. `on-loop-state-promote.yaml` (`pull_request_target` `closed`) promotes `pending` → `last_sha` on merge. L3 `push` / `push_head` advances `last_sha` in the same finalize run.

**Invariant:** Finalize does not edit application/doc **source under repair**.

Remove Phase 0 debt: `on-loop-ci-sweeper.yaml` `Update CI Sweeper Run Ledger` caller push.

## Triggers

Document applicable triggers in every caller. Prefer one primary poll/event path plus `workflow_dispatch`.

Dogfood `on-loop-ci-sweeper.yaml` uses `workflow_run` (repair-target `workflows:` list) + `workflow_dispatch` — no `schedule`. Changelog and docs-triage callers keep `schedule` + `workflow_dispatch`.

```yaml
# Example: event-driven CI sweeper (dogfood)
on:
  workflow_dispatch: {}
  workflow_run: # zizmor: ignore[dangerous-triggers] after ops checklist
    types: [completed]
    workflows:
      - on-ci-push-markdown
      # ... repair targets only (not on-loop-* / ci-loop-*)
```

```yaml
# Example: schedule polling (changelog / docs-triage)
on:
  schedule:
    - cron: "*/15 * * * 1-5"
  workflow_dispatch: {}
```

| Trigger             | Typical use                                               |
| ------------------- | --------------------------------------------------------- |
| `schedule`          | Integration branch polling (changelog, docs-triage)       |
| `workflow_run`      | Low-latency CI failure (ci-sweeper; ops checklist)        |
| `workflow_dispatch` | Manual debug / `gh run list` scan without an event run ID |

## Concurrency

`concurrency.group` **cannot use `env`**. Embed the group name in caller workflow YAML.

### Shared state branch (callers)

All `on-loop-*.yaml` callers and `on-loop-state-promote.yaml` use the same group for a given `branch_state` (currently `loop-state-main`):

```yaml
concurrency:
  cancel-in-progress: false
  group: loop-state-main
  queue: max
```

Queued runs wait for the active run to finish (detect → execute → finalize) before starting detect, so handoff JSON is never stale relative to peer loop activity. `queue: max` allows up to 100 pending runs in FIFO order (default `queue: single` would cancel an existing pending run when a third enters the group).

`ci-loop-caller` does **not** set job-level concurrency on `execute`; matrix cells within one run may still fan out in parallel.

## Matrix Fan-Out

```yaml
detect:
  outputs:
    target_matrix: ${{ steps.detect.outputs.target_matrix }}

execute:
  needs: detect
  strategy:
    matrix:
      target: ${{ fromJson(needs.detect.outputs.target_matrix) }}
  uses: ./.github/workflows/ci-loop-agent.yaml
  with:
    finalize_enabled: true
```

Each matrix cell = one `max_runs_per_day` consumption. Cap enumeration in `loop-detect`.

## Permissions (least privilege pattern)

| Job         | Typical permissions                                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------ |
| detect      | `contents: read`, `actions: write` (upload artifact); profile may add `actions: read`, `pull-requests: read`                   |
| execute     | `actions: read` (download artifact), `contents: write`, `pull-requests: write` (when `finalize_enabled=true`), engine-specific |
| record-skip | `contents: write`, `pull-requests: write` (run-log PR fallback on protected branches)                                          |
| finalize    | Runs inside `ci-loop-agent`; inherits caller `execute` job permissions                                                         |

`ci-loop-agent` `agent-l2` also needs `pull-requests: write` — `loop-state-write` opens a state PR when `LOOP_STATE_PUSH_BRANCH` blocks direct push.

## env Conventions

- Keys **alphabetically ordered** (repository workflow convention).
- Shared caller keys: [Loop Caller `env` Reference](workflows/loop-caller-env-reference.md).
- `LOOP_*` branch/finalize caps: [Multi-Branch canonical table](multi-branch-loops-design.md#caller-configuration-canonical).
- Domain vars (`CI_SWEEPER_*`, `CHANGELOG_*`, `DOCS_TRIAGE_*`, `LOOP_DETECT_SCRIPT`) in each [workflow design doc](multi-branch-loops-design.md#workflow-design-documents).

## Adding a New Loop Caller

After [Loop Caller Reusable Workflow Design](loop-caller-reusable-design.md) is implemented, copy a thin `on-loop-*.yaml` (triggers + `with:` only).

Until then:

1. Copy `on-loop-changelog.yaml`, `on-loop-docs-triage.yaml`, or `on-loop-ci-sweeper.yaml` skeleton.
2. Add `docs/explanation/loop-engineering/workflows/loop-<name>-workflow-design.md`.
3. Link from [Multi-Branch workflow index](multi-branch-loops-design.md#workflow-design-documents).
4. Register in `mkdocs.yml` under **Explanation → Loop Engineering → Loop Workflows**.
5. Package: `.apm/packages/loop-<name>/` with `SKILL.md` + `scripts/detect_*.sh` (+ optional ledger script).

## Phase 0 Debt (resolved)

Historical debt from early caller implementations. **All items below are resolved** in current `on-loop-*.yaml`; retained for audit trail only.

| Debt                                             | Was                                          | Resolution (current)                                               |
| ------------------------------------------------ | -------------------------------------------- | ------------------------------------------------------------------ |
| Double detect script                             | `on-loop-ci-sweeper` re-ran detect in `run:` | `loop-detect` outputs `verifier_context` per matrix cell           |
| Caller ledger `git push`                         | ci-sweeper pushed ledger from caller         | `domain_persistence_script` in `loop-finalize` via `ci-loop-agent` |
| `auto_merge: level == L3` without finalize check | all L2+ callers                              | `finalize == 'open_pr'` guard on `auto_merge`                      |
| Single `DEFAULT_BASE_BRANCH` only                | all                                          | `LOOP_INTEGRATION_BRANCHES`                                        |
| `docs-updater` detect path                       | `on-loop-docs-triage`                        | `loop-docs-triage/scripts/detect_changes.sh`                       |

Next structural improvement: [Loop Caller Reusable Workflow Design](loop-caller-reusable-design.md) (`ci-loop-caller.yaml`).

## References

- [Multi-Branch Loops Design](multi-branch-loops-design.md)
- [Loop Engineering Design](loop-engineering-design.md)
- [Specification](../../reference/specification.md)
- [CI Sweeper Workflow](workflows/loop-ci-sweeper-workflow-design.md)
- [Changelog Workflow](workflows/loop-changelog-workflow-design.md)
- [Docs Triage Workflow](workflows/loop-docs-triage-workflow-design.md)
