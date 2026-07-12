# Loop Caller Workflows Design

Shared GitHub Actions layout for `on-loop-*.yaml` caller workflows.

**Scope:** job graph, `target_matrix` handoff, triggers, concurrency, matrix fan-out, persistence job structure.  
**Out of scope:** domain detect logic — see [workflow designs](multi-branch-loops-design.md#workflow-design-documents). Platform target model — [Multi-Branch Loops Design](multi-branch-loops-design.md).

## Files

| Type     | Path                                                  | Role                                                |
| -------- | ----------------------------------------------------- | --------------------------------------------------- |
| Caller   | `.github/workflows/on-loop-<name>.yaml`               | Domain `env`, detect script path, verifier criteria |
| Reusable | `.github/workflows/ci-loop-agent.yaml`                | L1/L2/L3 execute (`loop-execute`)                   |
| Actions  | `y-miyazaki/config` `loop-detect`, `loop-finalize`, … | Generic phases                                      |

## Job Graph

```text
detect (single job)
  → loop-detect
  → outputs: target_matrix, should_run, skip_reason

execute (matrix: target_matrix)
  → ci-loop-agent.yaml per cell (optional finalize job when finalize_enabled=true)
  → inputs: target_json, prompt, verifier_context, finalize config, …

record-skip (optional)
  → loop-run-log when skip_reason=budget|circuit_breaker
```

## Detect Job

### Required outputs

| Output             | Source                                                                        |
| ------------------ | ----------------------------------------------------------------------------- |
| `should_run`       | `loop-detect` — true when `target_matrix` is non-empty                        |
| `skip_reason`      | `loop-detect`                                                                 |
| `target_matrix`    | JSON array of candidates (see [Specification](../reference/specification.md)) |
| Config passthrough | `level`, models, allowlist, `state_file`, …                                   |

Each matrix cell carries: `target_json`, `prompt`, `verifier_context`, `result`.

### Anti-pattern: double detect

**Forbidden:** invoking the detect script again in a caller `run:` step after `loop-detect`.

Remove Phase 0 debt: `on-loop-ci-sweeper.yaml` `Export Target Failure Context`.

### Target selection (inside `loop-detect`)

1. Read [caller `env`](multi-branch-loops-design.md#caller-configuration-canonical).
2. Enumerate integration branches / PRs; checkout per context; run `detect_script` per context.
3. Apply [trigger-aware priority](multi-branch-loops-design.md#trigger-aware-priority) and `acting_on`.
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
    finalize_enabled: true
    prompt_text: ${{ matrix.target.prompt }}
    target_json: ${{ toJson(matrix.target.target_json) }}
    verifier_context: ${{ matrix.target.verifier_context }}
    # … passthrough from detect + finalize config
```

`target_json` and `verifier_context` are required platform inputs (verifier_context may be empty string).

**`DEFAULT_LEVEL` vs finalize:**

```yaml
auto_merge: ${{ needs.detect.outputs.level == 'L3' && matrix.target.target_json.finalize == 'open_pr' }}
```

## Finalize (inside ci-loop-agent)

When `finalize_enabled=true`, `ci-loop-agent` runs `loop-finalize` after `agent-l2` in the **same workflow instance**, preserving execute output pairing per matrix cell.

### Persistence layer

All `.loop/*` writes in **finalize step** via `loop-finalize` — not separate caller `git push` steps.

| Input                       | Example                                                          |
| --------------------------- | ---------------------------------------------------------------- |
| `target_json`               | Matrix cell                                                      |
| `domain_persistence_script` | loop-ci-sweeper: `update_run_ledger.sh`; loop-docs-triage: empty |
| `state_push_branch`         | `LOOP_STATE_PUSH_BRANCH` or default branch                       |

Push branch: `LOOP_STATE_PUSH_BRANCH`, **not** `target.to.branch`.

**Invariant:** Finalize does not edit application/doc **source under repair**.

Remove Phase 0 debt: `on-loop-ci-sweeper.yaml` `Update CI Sweeper Run Ledger` caller push.

## Triggers

Document **both** in every caller; enable by uncommenting one block:

```yaml
on:
  schedule:
    - cron: "*/15 * * * 1-5"
  # workflow_run:
  #   types: [completed]
  #   ...
  workflow_dispatch:
```

| Trigger             | Typical use                                     |
| ------------------- | ----------------------------------------------- |
| `schedule`          | Integration branch polling                      |
| `workflow_run`      | Low-latency CI failure (ops checklist required) |
| `workflow_dispatch` | Manual debug                                    |

## Concurrency

`concurrency.group` **cannot use `env`**. Embed pattern in YAML.

### Per-target (matrix)

```yaml
concurrency:
  cancel-in-progress: true
  group: on-loop-ci-sweeper-${{ matrix.target.target_json.key }}
```

When `target_matrix` is empty (detect-only skip), workflow-level group is sufficient:

```yaml
concurrency:
  cancel-in-progress: true
  group: ${{ github.workflow }}
```

Cross-loop: [acting_on](multi-branch-loops-design.md#cross-loop-coordination-acting_on).

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

| Job         | Typical permissions                                                                       |
| ----------- | ----------------------------------------------------------------------------------------- |
| detect      | `contents: read`, `actions: read`, `checks: read`                                         |
| execute     | `contents: write`, `pull-requests: write` (when `finalize_enabled=true`), engine-specific |
| record-skip | `contents: write`, `pull-requests: write` (run-log PR fallback on protected branches)     |
| finalize    | Runs inside `ci-loop-agent`; inherits caller `execute` job permissions                    |

`ci-loop-agent` `agent-l2` also needs `pull-requests: write` — `loop-state-write` opens a state PR when `LOOP_STATE_PUSH_BRANCH` blocks direct push.

## env Conventions

- Keys **alphabetically ordered** (repository workflow convention).
- Shared caller keys: [Loop Caller `env` Reference](workflows/loop-caller-env-reference.md).
- `LOOP_*` branch/finalize caps: [Multi-Branch canonical table](multi-branch-loops-design.md#caller-configuration-canonical).
- Domain vars (`CI_SWEEPER_*`, `CHANGELOG_*`, `DOCS_TRIAGE_*`, `LOOP_DETECT_SCRIPT`) in each [workflow design doc](multi-branch-loops-design.md#workflow-design-documents).

## Adding a New Loop Caller

1. Copy `on-loop-changelog.yaml`, `on-loop-docs-triage.yaml`, or `on-loop-ci-sweeper.yaml` skeleton.
2. Add `docs/explanation/workflows/loop-<name>-workflow-design.md`.
3. Link from [Multi-Branch workflow index](multi-branch-loops-design.md#workflow-design-documents).
4. Register in `mkdocs.yml` under **Explanation → Loop Workflows**.
5. Package: `.apm/packages/loop-<name>/` with `SKILL.md` + `scripts/detect_*.sh` (+ optional ledger script).

## Phase 0 Debt (remove in implementation)

| Debt                                             | Caller                | Resolution                                     |
| ------------------------------------------------ | --------------------- | ---------------------------------------------- |
| Double detect script                             | `on-loop-ci-sweeper`  | `loop-detect` outputs `verifier_context`       |
| Caller ledger `git push`                         | `on-loop-ci-sweeper`  | `domain_persistence_script` in `loop-finalize` |
| `auto_merge: level == L3` without finalize check | all L2+ callers       | `finalize == 'open_pr'` guard                  |
| Single `DEFAULT_BASE_BRANCH` only                | all                   | `LOOP_INTEGRATION_BRANCHES`                    |
| `docs-updater` detect path                       | `on-loop-docs-triage` | `loop-docs-triage/scripts/detect_changes.sh`   |

## References

- [Multi-Branch Loops Design](multi-branch-loops-design.md)
- [Loop Engineering Design](loop-engineering-design.md)
- [Specification](../reference/specification.md)
- [CI Sweeper Workflow](workflows/loop-ci-sweeper-workflow-design.md)
- [Changelog Workflow](workflows/loop-changelog-workflow-design.md)
- [Docs Triage Workflow](workflows/loop-docs-triage-workflow-design.md)
