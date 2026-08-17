# Loop Caller Reusable Workflow Design

Extract shared `detect` → `execute` → `record-skip` job graph from `on-loop-*.yaml` into a single reusable workflow (`ci-loop-caller.yaml`). Thin callers pass loop-specific configuration via `with:` — the same pattern as `on-ci-push-*.yaml` and `on-cd-*.yaml`.

**Status:** Implemented  
**Scope:** GitHub Actions workflow structure for loop callers. Domain detect logic and platform target model are unchanged.  
**Supersedes (partially):** caller-level `env:` blocks (see [Loop Caller Inputs Reference](workflows/loop-caller-inputs-reference.md)).

## Problem

Each `on-loop-<name>.yaml` previously duplicated ~150 lines of identical job wiring (resolved by `ci-loop-caller.yaml`; see [Implementation checklist](#implementation-checklist)).

| Job         | Actions / reusable called                          |
| ----------- | -------------------------------------------------- |
| detect      | `loop-detect`                                      |
| ack-trigger | `gh api` reactions (optional; pr-revise UX)        |
| execute     | `ci-loop-agent.yaml` (matrix over `target_matrix`) |
| record-skip | `loop-run-log`                                     |

Loop-specific values (budget, allowlist, verifier rubric, detect script path) differ per file. Because `workflow_call` does not accept a shared job graph without duplication, configuration was placed in workflow-level `env:` and mapped into action `with:` inside each caller.

That `env:` pattern was a **workaround for copied jobs**, not a platform requirement. Other callers in this repository (`on-ci-push-markdown.yaml`, `on-ci-push-shell-script.yaml`, `on-cd-mkdocs.yaml`) already use **thin `on-*` + `with:` on a reusable workflow** with no `env:` block.

## Goal

| Objective           | Detail                                                                                    |
| ------------------- | ----------------------------------------------------------------------------------------- |
| Single job graph    | One `ci-loop-caller.yaml` owns `detect`, optional `ack-trigger`, `execute`, `record-skip` |
| Thin callers        | Each `on-loop-<name>.yaml`: `on:`, `concurrency`, `permissions`, one job with `with:`     |
| No caller `env:`    | Configuration via `ci-loop-caller` `inputs` and caller `with:` literals                   |
| Preserve invariants | Matrix fan-out, finalize inside `ci-loop-agent`, budget, shared workflow concurrency      |
| Extensibility       | New loops add caller `with:` + optional inputs; reusable jobs stay stable                 |

## Target Architecture

Full nest (detect / optional ack-trigger / execute / L1 vs L2 jobs): [Loop Engineering Design — Workflow Architecture Diagram](loop-engineering-design.md#workflow-architecture-diagram).

Thin-caller delta only:

| Caller                          | Extra `with:` vs schedule loops                                                                           |
| ------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `on-loop-github-pr-revise.yaml` | `ack_trigger_comment: true` (start `eyes` reaction; see [`ack-trigger`](#ack-trigger-optional-start-ack)) |

`finalize_enabled` gates the `loop-finalize` **step** inside `finalize-l2`, not whether the `finalize-l2` **job** runs. L1 has no `agent-l2` / worktree path. Job internals: `agent-l1` → `loop-agent-once`; `agent-l2` → `loop-worktree-setup` + `loop-execute`.

### File Responsibilities

| File                     | Role                                                                                     |
| ------------------------ | ---------------------------------------------------------------------------------------- |
| `on-loop-<name>.yaml`    | Triggers, workflow identity, concurrency group, permissions, loop config in `with:`      |
| `ci-loop-caller.yaml`    | Shared detect / optional ack-trigger / matrix execute / record-skip orchestration        |
| `ci-loop-agent.yaml`     | Level-gated agent + finalize jobs (`agent-l1`/`finalize-l1` vs `agent-l2`/`finalize-l2`) |
| `.github/actions/loop-*` | Phase implementations (unchanged)                                                        |

## Design Invariants (Must Not Break)

These constraints come from [Loop Caller Workflows Design](loop-caller-workflows-design.md) and [Multi-Branch Loops Design](multi-branch-loops-design.md). The refactor must preserve them.

| Invariant                           | Rationale                                                                                                                                                                                                                    |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Separate `on-loop-*` per loop**   | Independent cron, workflow name, concurrency; CI sweeper `workflow_run.workflows` lists repair targets only                                                                                                                  |
| **Finalize inside `ci-loop-agent`** | Reusable-workflow matrix collapses outputs across cells; finalize must pair with execute in the same workflow instance                                                                                                       |
| **Single detect per run**           | Domain `detect_script` invoked only by `loop-detect`; no second `run:` detect in caller                                                                                                                                      |
| **`target_matrix` handoff**         | `detect` outputs slim JSON array + `handoff_artifact_name`; large `result` / `verifier_context` in loop-handoff artifact; `execute` matrix uses `fromJson(needs.detect.outputs.target_matrix)` and resolves by `handoff_key` |
| **Shared workflow concurrency**     | `on-loop-*.yaml` use `loop-state-<branch_state>` with `cancel-in-progress: false` and `queue: max` so detect runs on fresh state before execute                                                                              |
| **Budget / circuit breaker**        | `record-skip` when `should_run == false` and `skip_reason` is `budget` or `circuit_breaker`                                                                                                                                  |
| **`target_budget` deferral**        | When fan-out cap defers targets, `should_run` stays `true` and execute runs; `skip_reason=target_budget` is informational only — not recorded by `record-skip` (by design)                                                   |
| **State push branch**               | `.loop/*` run-log/budget persistence uses `branch_state`. L2 `open_pr` loops use merge-gated `pending` on `branch_state` and `on-loop-state-promote`.                                                                        |
| **Alphabetical keys**               | `inputs`, `with`, `env` (inside reusable jobs), `permissions` keys sorted A→Z                                                                                                                                                |

## Thin Caller Pattern

Follow `on-ci-push-shell-script.yaml`:

```yaml
name: on-loop-changelog

on:
  schedule:
    - cron: "0 10 * * 5"
  workflow_dispatch: {}

concurrency:
  cancel-in-progress: false
  group: loop-state-main
  queue: max

permissions:
  actions: write
  contents: write
  copilot-requests: write # zizmor: ignore[excessive-permissions]
  pull-requests: write

jobs:
  loop:
    uses: ./.github/workflows/ci-loop-caller.yaml
    with:
      agent_implementer_max_turns: 5
      agent_implementer_model: cursor-grok-4.5-low
      agent_loop_max_attempts: 3
      agent_verifier_instructions: |
        ## Criteria for APPROVE
        ...
      agent_verifier_max_turns: 3
      agent_verifier_model: composer-2.5
      allowlist: CHANGELOG.md
      branch_match: main
      branch_state: main
      budget_max_runs_per_day: 1
      budget_max_tokens_per_day: 1000000
      detect_domain_env_json: >-
        {"CHANGELOG_FILE":"CHANGELOG.md","CHANGELOG_MERGE_COMMITS":"false"}
      detect_script: .agents/skills/changelog/scripts/detect_changelog_commits.sh
      engine: cursor
      delivery: open_pr
      may_edit: true
      write_target: fix
      infer_files_pattern: 'CHANGELOG\.md'
      level: L2
      loop_name: changelog
      max_targets_per_schedule: 3
      no_changes_verdict: REJECT
      pr_body: ""
      pr_title: "chore(changelog): update CHANGELOG.md (loop-changelog)"
      agent_implementer_instructions: |
        Update the target changelog file under `## [Unreleased]` ...
      pr_enabled: false
      agent_implementer_skill_name: changelog
    secrets:
      AGENT_TOKEN: ${{ secrets.AGENT_TOKEN }}
      BOT_APP_CLIENT_ID: ${{ secrets.MAINTENANCE_BOT_APP_CLIENT_ID }}
      BOT_APP_PRIVATE_KEY: ${{ secrets.MAINTENANCE_BOT_APP_PRIVATE_KEY }}
      # GH_TOKEN: ${{ secrets.SOME_PAT }}   # optional override; omit to use App → job GITHUB_TOKEN
```

**No workflow-level `env:` block.** Credentials use `secrets:` on the `loop` job (see [Loop Caller Inputs Reference — Credentials](workflows/loop-caller-inputs-reference.md#credentials-via-secrets)).

Cron and `workflow_dispatch` runs have no `github.event.inputs` — fixed literals in `with:` are correct (same as `on-cd-mkdocs.yaml` `pip_packages`).

### `workflow_run` trigger (ci-sweeper)

Canonical example: [Loop Caller Inputs Reference — Event keys](workflows/loop-caller-inputs-reference.md#ci-sweeper-ci-sweeper) (`detect_domain_env_json` with `CI_SWEEPER_*` uppercase keys).

Enable `workflow_run` on the caller only; reusable workflow stays trigger-agnostic.

## `ci-loop-caller.yaml` Specification

### Jobs

| Job           | `needs`  | `if`                                                                 | Calls / behavior              |
| ------------- | -------- | -------------------------------------------------------------------- | ----------------------------- |
| `detect`      | —        | always                                                               | `loop-detect`                 |
| `ack-trigger` | `detect` | `ack_trigger_comment` + `should_run` + comment webhook event         | Start ACK (see below)         |
| `execute`     | `detect`, `ack-trigger` | `should_run` and ack `success` or `skipped`            | `ci-loop-agent.yaml` (matrix) |
| `record-skip` | `detect` | success + `should_run == false` + skip reason budget/circuit_breaker | `loop-run-log`                |

`ack-trigger` depends on `detect` only. `execute` depends on `detect` and `ack-trigger` so start ACK finishes before the agent runs (skipped `ack-trigger` is treated as success for loops that leave `ack_trigger_comment` false).

#### `ack-trigger` (optional start ACK)

Human-triggered loops (today: `on-loop-github-pr-revise`) pass `ack_trigger_comment: true` so reviewers see that work started before the agent finishes.

| Stage        | Behavior                                                                                                                                                                                       |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| When         | `inputs.ack_trigger_comment` is true, detect emitted `should_run=true`, and the caller webhook is `issue_comment` or `pull_request_review_comment`                                             |
| Input        | `github.event.comment.id` as fallback; primary set from detect handoff `result.comments[]` (batched open `@mention` feedback)                                                                  |
| Action       | Download loop-handoff payloads when present; for each gathered `comment_id`, POST `eyes` reaction via `gh api` on the matching REST reactions endpoint (`issues/comments` vs `pulls/comments`) |
| Fallback     | If gather produced no comment ids, ACK only the webhook trigger `comment.id`                                                                                                                   |
| Failure      | `continue-on-error: true` — warnings only; never fails the workflow                                                                                                                            |
| Out of scope | Done-thread reply (`loop-notify-pr` in `finalize-l2`), auto-resolve, canceling other runs                                                                                                      |

Permissions for reactions are isolated in `ack-trigger` (`issues: write`, `pull-requests: write`) so the `detect` job can keep `pull-requests: read` for enumeration without granting write to every loop.

Caller UX detail: [PR Revise Workflow Design — Trigger UX](workflows/loop-github-pr-revise-workflow-design.md#trigger-ux-ack--thread-reply).

Caller workflows set workflow-level concurrency (`loop-state-main`); `ci-loop-caller` does not add job-level concurrency on `execute`.

### Input Groups

Keys are **alphabetically ordered** in the workflow file. Prefix `loop_` dropped on inputs where the name is already scoped to `ci-loop-caller` (e.g. `loop_name` not `LOOP_NAME`).

#### Agent and engine

| Input                         | Type   | Required | Default         | Maps to                                        |
| ----------------------------- | ------ | -------- | --------------- | ---------------------------------------------- |
| `agent_implementer_max_turns` | number | yes      | —               | `loop-detect`                                  |
| `agent_implementer_model`     | string | yes      | —               | `loop-detect`                                  |
| `agent_loop_max_attempts`     | number | yes      | —               | `loop-detect`                                  |
| `agent_verifier_instructions`     | string | yes      | —               | `loop-detect` (multiline markdown)             |
| `agent_verifier_max_turns`    | number | yes      | —               | `loop-detect`                                  |
| `agent_verifier_model`        | string | yes      | —               | `loop-detect`                                  |
| `engine`                      | string | yes      | —               | `loop-detect` / `ci-loop-agent`                |
| `level`                       | string | no       | `L2`            | `loop-detect`                                  |
| `agent_implementer_skill_name`                  | string | yes      | —               | `loop-detect`                                  |
| `agent_verifier_skill_name`         | string | no       | `loop-verifier` | `ci-loop-agent` → `loop-execute` checker skill |

#### Platform (branch, budget, finalize)

| Input                       | Type    | Required | Default                    | Maps to                                                 |
| --------------------------- | ------- | -------- | -------------------------- | ------------------------------------------------------- |
| `allowlist`                 | string  | yes      | —                          | `loop-detect` → execute                                 |
| `branch_match`              | string  | no       | `""`                       | `loop-detect` (`loop_integration_branches`)             |
| `branch_match_mode`         | string  | no       | `glob`                     | `loop-detect` (`loop_branch_match`)                     |
| `branch_state`              | string  | yes      | —                          | `loop-detect` (`base_branch`, `loop_state_push_branch`) |
| `budget_max_runs_per_day`   | number  | no       | omitted                    | `loop-detect`                                           |
| `budget_max_tokens_per_day` | number  | no       | omitted                    | `loop-detect`                                           |
| `denylist`                  | string  | no       | `""` (platform default in `loop-execute` when empty) | `ci-loop-agent` execute only                            |
| `detect_script`             | string  | yes      | —                          | `loop-detect`                                           |
| `delivery`                  | string  | no       | `open_pr`                  | `loop-detect`                                           |
| `may_edit`                  | boolean | yes      | —                          | `loop-detect` → `## Constraints`                        |
| `write_target`              | string  | yes      | —                          | `loop-detect` → `## Constraints`                        |
| `infer_files_pattern`       | string  | no       | `""`                       | detect → execute                                        |
| `loop_name`                 | string  | yes      | —                          | detect, execute, record-skip, concurrency group         |
| `max_targets_per_schedule`  | number  | no       | `3`                        | `loop-detect`                                           |
| `no_changes_verdict`        | string  | no       | `REJECT`                   | detect → execute                                        |
| `pr_body`                   | string  | no       | `""`                       | detect → execute finalize                               |
| `pr_exclude`                | string  | no       | `fork,draft,label:no-loop` | `loop-detect`                                           |
| `pr_include_bots`           | string  | no       | `""`                       | `loop-detect`                                           |
| `pr_title`                  | string  | no       | `""`                       | detect → execute                                        |
| `agent_implementer_instructions`       | string  | no       | `""`                       | `loop-detect`                                           |
| `pr_enabled`                | boolean | no       | `false`                    | `loop-detect` (`loop_pr_enabled`)                       |
| `state_file`                | string  | no       | `""`                       | `loop-detect`                                           |
| _(token via secrets)_       | —       | —        | —                          | Resolve in-job: App → `GH_TOKEN` → job `GITHUB_TOKEN`   |

#### Domain detect environment (`detect_domain_env_json`)

| Input                    | Required | Default | Maps to                                                  |
| ------------------------ | -------- | ------- | -------------------------------------------------------- |
| `detect_domain_env_json` | no       | `{}`    | Detect job step `env` (export step before `loop-detect`) |

**Decision:** `detect_domain_env_json` only — no per-domain top-level inputs (e.g. `changelog_file`). Per-loop JSON keys: [Domain detect environment index](workflows/loop-caller-inputs-reference.md#domain-detect-environment-detect_domain_env_json) → each workflow design doc.

Detect scripts read domain variables from the step environment. Caller passes:

```yaml
detect_domain_env_json: >-
  {"CHANGELOG_FILE":"CHANGELOG.md","CHANGELOG_MERGE_COMMITS":"false"}
```

Reusable `detect` job runs an export step before `loop-detect` (validates JSON object type, rejects newline values, then appends to `GITHUB_ENV`). See `.github/workflows/ci-loop-caller.yaml` — step `Export Detect Domain Env`.

Empty object `{}` is valid for loops with no domain env.

Export step must reject values containing newlines; prefer `jq` with `--arg` per key when values may contain `=` or special characters (see Risk Register).

#### Optional `loop-detect` passthrough

| Input          | Required | Default                    | Maps to `loop-detect` input |
| -------------- | -------- | -------------------------- | --------------------------- |
| `branch_match` | no       | `glob`                     | `loop_branch_match`         |
| `budget_file`  | no       | `.loop/loop-budget.json`   | `budget_file`               |
| `priority`     | no       | `integration,pull_request` | `loop_priority`             |
| `run_log_file` | no       | `.loop/loop-run-log.md`    | `run_log_file`              |
| `state_file`   | no       | `""`                       | `state_file`                |

Full mapping table: [Loop Caller Inputs Reference — `loop-detect` mapping](workflows/loop-caller-inputs-reference.md#loop-detect-input-mapping).

#### Caller UX (optional)

| Input                 | Required | Default | Used by                                      |
| --------------------- | -------- | ------- | -------------------------------------------- |
| `ack_trigger_comment` | no       | `false` | `ack-trigger` job (`if` + reaction ACK only) |
| `scoped_pr_number`    | no       | `""`    | `loop-detect` (`LOOP_SCOPED_PR_NUMBER`)      |

#### Execute-only (optional)

| Input                       | Required | Default | Used by                                      |
| --------------------------- | -------- | ------- | -------------------------------------------- |
| `additional_commit_paths`   | no       | `""`    | `ci-loop-agent` finalize (ci-sweeper ledger) |
| `domain_persistence_script` | no       | `""`    | `ci-loop-agent` finalize                     |

#### Detect permissions

All branch/PR loops use **`ci-loop-caller.yaml`**. The reusable `detect` job declares:

| Job           | Permissions                                                                         |
| ------------- | ----------------------------------------------------------------------------------- |
| `detect`      | `actions: write`, `contents: read`, `pull-requests: read`                           |
| `ack-trigger` | `issues: write`, `pull-requests: write` when `ack_trigger_comment` (pr-revise only) |
| `execute`     | execute baseline (`actions: read`, `contents: write`, `pull-requests: write`, …)    |
| `record-skip` | `contents: write`, `pull-requests: write`                                           |

Thin caller workflow `permissions` = **execute baseline** plus **`actions: write`** so the reusable `detect` job can upload handoff artifacts. Reusable workflows cannot escalate beyond the caller grant.

PR enumeration (`gh pr list`), open PR heads (`pr_enabled`), and Actions API scans (`gh run list` in ci-sweeper) all use the same detect token scope today. Split reusable profiles (`ci-loop-caller-pr-scan`, `ci-loop-caller-full-github`) were removed as duplicate YAML.

Template for PR-watch loops: [`example/on-loop-pr-scan.yaml`](https://github.com/y-miyazaki/config/blob/main/.github/workflows/example/on-loop-pr-scan.yaml) (copy only; not scheduled in this repo).

#### ci-monitor profile (not implemented)

Reserved for a future loop that needs **`actions: read` only** on detect (no `actions: write`). Would require a separate reusable workflow if that least-privilege split becomes necessary.

### Credentials (via `secrets:`)

| Secret (callee)       | Required | Role                                                                                          |
| --------------------- | -------- | --------------------------------------------------------------------------------------------- |
| `AGENT_TOKEN`         | yes      | Engine API key. Mapped internally per `engine` input.                                         |
| `BOT_APP_CLIENT_ID`   | no       | GitHub App client ID for ruleset-bypass / elevated API (preferred when configured).           |
| `BOT_APP_PRIVATE_KEY` | no       | GitHub App private key paired with `BOT_APP_CLIENT_ID`.                                       |
| `GH_TOKEN`            | no       | Optional explicit token override for resolution. Empty → job `GITHUB_TOKEN` (`github.token`). |

Caller maps repository secrets via explicit `secrets:` (e.g. `BOT_APP_CLIENT_ID: ${{ secrets.MAINTENANCE_BOT_APP_CLIENT_ID }}`). See [Loop Caller Inputs Reference — Credentials](workflows/loop-caller-inputs-reference.md#credentials-via-secrets).

Do **not** name a `workflow_call` secret `GITHUB_TOKEN` or `github_token` — those collide with system-reserved secret names and prevent the reusable workflow from loading.

### GitHub token resolution

Each job that talks to GitHub (detect, record-skip, agent-l1/l2, finalize) runs `loop-resolve-push-token` **inside that job** and uses only the same-job step output.

**Precedence** (see `.github/actions/loop-resolve-push-token`):

1. GitHub App installation token (when `BOT_APP_*` are set and mint succeeds)
2. Optional `secrets.GH_TOKEN`
3. Job automatic `GITHUB_TOKEN` / `github.token`

**Why not a shared `prepare` job that fans out a resolved token**

| Constraint                                                     | Implication                                                                                     |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Masked / secret values cannot cross jobs via `needs.*.outputs` | After `::add-mask::` (or App-token mint masking), job outputs are redacted/empty for dependents |
| App tokens are masked at mint time                             | A one-shot prepare → `outputs.github_token` → later jobs cannot receive the real value          |
| Official cross-job secret pattern                              | External secret store + handle — not used here                                                  |

So **credentials** (`BOT_APP_*`, optional `GH_TOKEN`) are what we share across jobs/workflows; the **resolved token string** is minted per job. Commonization is the resolve **action**, not a single minted value.

`ci-loop-caller` / `ci-loop-caller-entity` pass `BOT_APP_*` + `GH_TOKEN` into `ci-loop-agent`; the agent resolves again in `agent-l1` / `agent-l2` / `finalize`.

**Fallback and `permissions:`**

For the automatic job `GITHUB_TOKEN`, effective scopes **are** that job's `permissions:` (intersected with repository/org workflow defaults). It is not a separate full-power token that the job then “limits.”

| Job                     | Typical fallback need      | Job `permissions` (minimum for fallback)                                   |
| ----------------------- | -------------------------- | -------------------------------------------------------------------------- |
| `detect`                | PR / issue / Actions reads | read scopes (`contents` / `pull-requests` or `issues` as profile requires) |
| `record-skip`           | push run-log / state PR    | `contents: write`, `pull-requests: write`                                  |
| `agent-l2` / `finalize` | push, PR create/comment    | `contents: write`, `pull-requests: write`                                  |
| `agent-l1`              | issue side effects         | `issues: write` (+ `contents: read`)                                       |

App tokens and explicit PATs carry **their own** scopes; receiving-job `permissions:` do not reduce those passed tokens.

**Naming**

| Layer                  | Name           | Notes                                          |
| ---------------------- | -------------- | ---------------------------------------------- |
| `workflow_call` secret | `GH_TOKEN`     | Avoid reserved `GITHUB_TOKEN` / `github_token` |
| Composite action I/O   | `github_token` | `loop-*` actions                               |
| Shell / `gh` CLI env   | `GITHUB_TOKEN` | `gh` accepts `GITHUB_TOKEN` (and `GH_TOKEN`)   |

### Nesting

```text
on-loop-*  →  ci-loop-caller  →  ci-loop-agent
                              →  ack-trigger (optional; pr-revise start ACK)
```

Two levels of reusable workflows — well within GitHub Actions nesting limits.

## Extensibility: Adding a New Loop

1. Add `.apm/packages/<domain>/<name>/` (skill + `scripts/detect_*.sh`).
2. Add `docs/explanation/loop-engineering/workflows/loop-<name>-workflow-design.md`.
3. Copy thin caller from `on-loop-changelog.yaml`; set `on:`, `with:`, workflow `name:`.
4. For CI sweeper callers: list only repair-target workflows under `workflow_run.workflows` (omit `on-loop-*` / `ci-loop-*`).
5. Add mkdocs nav entry under **Loop Workflows**.
6. **Do not** copy `detect` / `execute` / `record-skip` jobs — only `with:` values change.

New domain env keys go into `detect_domain_env_json` without editing reusable job steps (when using approach B).

## Rejected Alternatives

| Alternative                                 | Why rejected                                                                                   |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Merge all loops into one `on-loop.yaml`     | Cannot have per-loop cron, workflow identity, or isolated concurrency/budget                   |
| Caller workflow-level `env:`                | Unnecessary after reusable extraction; inconsistent with other `on-*` callers                  |
| Composite action for full caller graph      | Cannot call `ci-loop-agent` reusable or define matrix over reusable workflows                  |
| Separate finalize job in caller             | Matrix output pairing breaks across reusable workflow cells                                    |
| Config file only (no `with:`)               | Hides tunables from workflow YAML; harder to review in PRs; optional later as additive pattern |
| Shared `prepare` job minting one token      | Masked App/secret tokens cannot fan out via job outputs; resolve per job instead               |
| `workflow_call` secret named `GITHUB_TOKEN` | Reserved name; reusable workflow fails to load                                                 |

## Implementation Checklist

### 1. Create reusable workflow

- [x] Add `.github/workflows/ci-loop-caller.yaml` with `workflow_call` inputs (alphabetical).
- [x] Implement `detect`, `execute` (matrix → `ci-loop-agent`), `record-skip` jobs.
- [x] Add `detect_domain_env_json` export step (or explicit domain inputs).
- [x] Mirror execute `with:` passthrough from current callers (including `auto_merge` guard).
- [x] Add `example/on-loop-*.yaml` mirrors.

### 2. Thin existing callers

- [x] Refactor `on-loop-changelog.yaml` to single `loop` job + `with:`.
- [x] Refactor `on-loop-docs-updater.yaml`.
- [x] Refactor `on-loop-ci-sweeper.yaml` (`ci-loop-caller-full-github.yaml` profile, execute-only inputs).
- [x] Update `.github/workflows/example/on-loop-*.yaml` mirrors.
- [x] Remove workflow-level `env:` from all loop callers.

### 3. Documentation

- [x] Add [Loop Caller Inputs Reference](workflows/loop-caller-inputs-reference.md) (specification; implementation pending).
- [x] Update [Loop Caller Workflows Design](loop-caller-workflows-design.md) (planned refactor note, Phase 0 status).
- [x] Remove legacy Loop Caller `env` Reference doc; link to inputs reference instead.
- [x] Update per-loop workflow design docs (`Environment variables` → `Caller inputs`).
- [x] Update [GitHub Workflows Design](../github-workflows-design.md) loop exception note.
- [x] Register nav in `mkdocs.yml`.

### 4. Validation

- [x] `actionlint .github/workflows/ci-loop-caller.yaml .github/workflows/on-loop-*.yaml`
- [x] `ghalint run`
- [x] `zizmor .github/workflows/`

### 5. Release maintainer (manual)

- [ ] Bump remote pins in `ci-loop-caller.yaml` / `ci-loop-agent.yaml` to release SHA containing merge-gated `pending`, `pending_pr` detect blocking, and `loop-state-promote`
- [ ] `workflow_dispatch` smoke per loop (optional)

## Risk Register

| Risk                                                   | Mitigation                                                                                                                                                              |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Long `with:` blocks in callers                         | Acceptable trade-off vs triple job duplication; per-loop design doc lists all keys                                                                                      |
| `detect_domain_env_json` typos                         | Document keys per loop; detect script fails fast on missing required env; validate JSON in export step                                                                  |
| Input drift between `loop-detect` and `ci-loop-caller` | Maintain mapping table in inputs reference; reusable maps `branch_match` → `loop_integration_branches`, `branch_state` → `base_branch` / `loop_state_push_branch`, etc. |
| Reusable change affects all loops                      | CI workflow lint on every PR; thin callers keep blast radius visible in review                                                                                          |
| Multiline `agent_verifier_instructions` in `with:`         | Supported by `workflow_call` string inputs; keep rubric in caller for readability                                                                                       |

## References

- [Loop Caller Workflows Design](loop-caller-workflows-design.md) — current job graph and invariants
- [Loop Caller Inputs Reference](workflows/loop-caller-inputs-reference.md) — caller `with:` keys
- [GitHub Workflows Design](../github-workflows-design.md) — `on-*` / `ci-*` naming and caller conventions
- [Multi-Branch Loops Design](multi-branch-loops-design.md) — platform `LOOP_*` semantics
- [Loop Engineering Design](loop-engineering-design.md) — L1/L2/L3 and finalize behavior
