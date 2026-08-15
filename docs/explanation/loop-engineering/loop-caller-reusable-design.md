loop-caller-reusable-design.md 415L
# Loop Caller Reusable Workflow Design
Extract shared `detect` → `execute` → `record-skip` job graph from `on-loop-*.yaml` into a single reusable workflow (`ci-loop-caller.yaml`). Thin callers pass loop-specific configuration via `with:` — the same pattern as `on-ci-push-*.yaml` and `on-cd-*.yaml`.
... [lean-ctx: omitted 2 lines]
**Supersedes (partially):** caller-level `env:` blocks (see [Loop Caller Inputs Reference](workflows/loop-caller-inputs-reference.md)).
## Problem
Each `on-loop-<name>.yaml` previously duplicated ~150 lines of identical job wiring (resolved by `ci-loop-caller.yaml`; see [Implementation checklist](#implementation-checklist)).
... [lean-ctx: omitted 5 lines]
Loop-specific values (budget, allowlist, verifier rubric, detect script path) differ per file. Because `workflow_call` does not accept a shared job graph without duplication, configuration was placed in workflow-level `env:` and mapped into action `with:` inside each caller.
That `env:` pattern was a **workaround for copied jobs**, not a platform requirement. Other callers in this repository (`on-ci-push-markdown.yaml`, `on-ci-push-shell-script.yaml`, `on-cd-mkdocs.yaml`) already use **thin `on-*` + `with:` on a reusable workflow** with no `env:` block.
## Goal
| Objective           | Detail                                                                                |
... [lean-ctx: omitted 3 lines]
| No caller `env:`    | Configuration via `ci-loop-caller` `inputs` and caller `with:` literals               |
| Preserve invariants | Matrix fan-out, finalize inside `ci-loop-agent`, budget, shared workflow concurrency  |
| Extensibility       | New loops add caller `with:` + optional inputs; reusable jobs stay stable             |
## Target Architecture
```text
on-loop-changelog.yaml          on-loop-ci-sweeper.yaml
  on: schedule                     on: workflow_run (+ workflow_dispatch)
  concurrency / permissions         concurrency / permissions
  jobs:                             jobs:
    loop:                             loop:
      uses: ci-loop-caller.yaml         uses: ci-loop-caller.yaml
      with: { loop-specific }           with: { loop-specific }
      secrets: { … }                     secrets: { … }
                    \                   /
                     v                 v
                         ci-loop-caller.yaml
                detect   → loop-detect
                execute  → ci-loop-agent.yaml  (matrix)
                record-skip → loop-run-log
                              |
                              v
                        ci-loop-agent.yaml
                          agent-l* + finalize-l* (inside same reusable)
```
### File Responsibilities
| File                     | Role                                                                                |
... [lean-ctx: omitted 1 lines]
| `on-loop-<name>.yaml`    | Triggers, workflow identity, concurrency group, permissions, loop config in `with:` |
... [lean-ctx: omitted 1 lines]
| `ci-loop-agent.yaml`     | L1/L2/L3 agent execution + finalize (unchanged)                                     |
| `.github/actions/loop-*` | Phase implementations (unchanged)                                                   |
## Design Invariants (Must Not Break)
These constraints come from [Loop Caller Workflows Design](loop-caller-workflows-design.md) and [Multi-Branch Loops Design](multi-branch-loops-design.md). The refactor must preserve them.
... [lean-ctx: omitted 2 lines]
| **Separate `on-loop-*` per loop**   | Independent cron, workflow name, concurrency; CI sweeper `workflow_run.workflows` lists repair targets only                                                                                                                  |
| **Finalize inside `ci-loop-agent`** | Reusable-workflow matrix collapses outputs across cells; finalize must pair with execute in the same workflow instance                                                                                                       |
... [lean-ctx: omitted 1 lines]
| **`target_matrix` handoff**         | `detect` outputs slim JSON array + `handoff_artifact_name`; large `result` / `verifier_context` in loop-handoff artifact; `execute` matrix uses `fromJson(needs.detect.outputs.target_matrix)` and resolves by `handoff_key` |
... [lean-ctx: omitted 2 lines]
| **`target_budget` deferral**        | When fan-out cap defers targets, `should_run` stays `true` and execute runs; `skip_reason=target_budget` is informational only — not recorded by `record-skip` (by design)                                                   |
| **State push branch**               | `.loop/*` run-log/budget persistence uses `branch_state`. L2 `open_pr` loops use merge-gated `pending` on `branch_state` and `on-loop-state-promote`.                                                                        |
... [lean-ctx: omitted 1 lines]
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
      agent_verifier_criteria: |
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
      loop_name: changelog
      max_targets_per_schedule: 3
      no_changes_verdict: REJECT
      pr_body: ""
      pr_title: "chore(changelog): update CHANGELOG.md (loop-changelog)"
      prompt_instructions: |
        Update the target changelog file under `## [Unreleased]` ...
      pr_enabled: false
      skill_name: changelog
    secrets:
      AGENT_TOKEN: ${{ secrets.AGENT_TOKEN }}
      BOT_APP_CLIENT_ID: ${{ secrets.MAINTENANCE_BOT_APP_CLIENT_ID }}
      BOT_APP_PRIVATE_KEY: ${{ secrets.MAINTENANCE_BOT_APP_PRIVATE_KEY }}
      # GH_TOKEN: ${{ secrets.SOME_PAT }}   # optional override; omit to use App → job GITHUB_TOKEN
```
... [lean-ctx: omitted 2 lines]
### `workflow_run` trigger (ci-sweeper)
Canonical example: [Loop Caller Inputs Reference — Event keys](workflows/loop-caller-inputs-reference.md#ci-sweeper-ci-sweeper) (`detect_domain_env_json` with `CI_SWEEPER_*` uppercase keys).
Enable `workflow_run` on the caller only; reusable workflow stays trigger-agnostic.
## `ci-loop-caller.yaml` Specification
### Jobs
| Job           | `needs`  | `if`                                                                 | Calls                         |
... [lean-ctx: omitted 2 lines]
| `execute`     | `detect` | `needs.detect.outputs.should_run == 'true'`                          | `ci-loop-agent.yaml` (matrix) |
| `record-skip` | `detect` | success + `should_run == false` + skip reason budget/circuit_breaker | `loop-run-log`                |
Caller workflows set workflow-level concurrency (`loop-state-main`); `ci-loop-caller` does not add job-level concurrency on `execute`.
### Input Groups
Keys are **alphabetically ordered** in the workflow file. Prefix `loop_` dropped on inputs where the name is already scoped to `ci-loop-caller` (e.g. `loop_name` not `LOOP_NAME`).
#### Agent and engine
| Input                         | Type   | Required | Default         | Maps to                                        |
| ----------------------------- | ------ | -------- | --------------- | ---------------------------------------------- |
| `agent_implementer_max_turns` | number | yes      | —               | `loop-detect`                                  |
| `agent_implementer_model`     | string | yes      | —               | `loop-detect`                                  |
... [lean-ctx: omitted 1 lines]
| `agent_verifier_criteria`     | string | yes      | —               | `loop-detect` (multiline markdown)             |
... [lean-ctx: omitted 5 lines]
| `verifier_skill_name`         | string | no       | `loop-verifier` | `ci-loop-agent` → `loop-execute` checker skill |
#### Platform (branch, budget, finalize)
| Input                       | Type    | Required | Default                    | Maps to                                                 |
| --------------------------- | ------- | -------- | -------------------------- | ------------------------------------------------------- |
... [lean-ctx: omitted 2 lines]
| `branch_match_mode`         | string  | no       | `glob`                     | `loop-detect` (`loop_branch_match`)                     |
| `branch_state`              | string  | yes      | —                          | `loop-detect` (`base_branch`, `loop_state_push_branch`) |
... [lean-ctx: omitted 4 lines]
| `delivery`                  | string  | no       | `open_pr`                  | `loop-detect`                                           |
| `may_edit`                  | boolean | yes      | —                          | `loop-detect` → `## Constraints`                        |
| `write_target`              | string  | yes      | —                          | `loop-detect` → `## Constraints`                        |
... [lean-ctx: omitted 5 lines]
| `pr_exclude`                | string  | no       | `fork,draft,label:no-loop` | `loop-detect`                                           |
... [lean-ctx: omitted 3 lines]
| `pr_enabled`                | boolean | no       | `false`                    | `loop-detect` (`loop_pr_enabled`)                       |
... [lean-ctx: omitted 1 lines]
| _(token via secrets)_       | —       | —        | —                          | Resolve in-job: App → `GH_TOKEN` → job `GITHUB_TOKEN`   |
#### Domain detect environment (`detect_domain_env_json`)
| Input                    | Required | Default | Maps to                                                  |
... [lean-ctx: omitted 2 lines]
**Decision:** `detect_domain_env_json` only — no per-domain top-level inputs (e.g. `changelog_file`). Document JSON keys in [Loop Caller Inputs Reference](workflows/loop-caller-inputs-reference.md).
... [lean-ctx: omitted 1 lines]
```yaml
detect_domain_env_json: >-
  {"CHANGELOG_FILE":"CHANGELOG.md","CHANGELOG_MERGE_COMMITS":"false"}
```
Reusable `detect` job runs an export step before `loop-detect` (validates JSON object type, rejects newline values, then appends to `GITHUB_ENV`). See `.github/workflows/ci-loop-caller.yaml` — step `Export Detect Domain Env`.
... [lean-ctx: omitted 1 lines]
Export step must reject values containing newlines; prefer `jq` with `--arg` per key when values may contain `=` or special characters (see Risk Register).
#### Optional `loop-detect` passthrough
| Input          | Required | Default                    | Maps to `loop-detect` input |
... [lean-ctx: omitted 2 lines]
| `budget_file`  | no       | `.loop/loop-budget.json`   | `budget_file`               |
| `priority`     | no       | `integration,pull_request` | `loop_priority`             |
... [lean-ctx: omitted 2 lines]
Full mapping table: [Loop Caller Inputs Reference — `loop-detect` mapping](workflows/loop-caller-inputs-reference.md#loop-detect-input-mapping).
#### Execute-only (optional)
| Input                       | Required | Default | Used by                                      |
... [lean-ctx: omitted 1 lines]
| `additional_commit_paths`   | no       | `""`    | `ci-loop-agent` finalize (ci-sweeper ledger) |
| `domain_persistence_script` | no       | `""`    | `ci-loop-agent` finalize                     |
#### Detect permissions
All branch/PR loops use **`ci-loop-caller.yaml`**. The reusable `detect` job declares:
... [lean-ctx: omitted 2 lines]
| `detect`      | `actions: write`, `contents: read`, `pull-requests: read` |
| `ack-trigger` | `issues: write`, `pull-requests: write` when `ack_trigger_comment` (pr-revise only) |
... [lean-ctx: omitted 2 lines]
Thin caller workflow `permissions` = **execute baseline** plus **`actions: write`** so the reusable `detect` job can upload handoff artifacts. Reusable workflows cannot escalate beyond the caller grant.
PR enumeration (`gh pr list`), open PR heads (`pr_enabled`), and Actions API scans (`gh run list` in ci-sweeper) all use the same detect token scope today. Split reusable profiles (`ci-loop-caller-pr-scan`, `ci-loop-caller-full-github`) were removed as duplicate YAML.
Template for PR-watch loops: [`example/on-loop-pr-scan.yaml`](https://github.com/y-miyazaki/config/blob/main/.github/workflows/example/on-loop-pr-scan.yaml) (copy only; not scheduled in this repo).
#### ci-monitor profile (not implemented)
Reserved for a future loop that needs **`actions: read` only** on detect (no `actions: write`). Would require a separate reusable workflow if that least-privilege split becomes necessary.
### Credentials (via `secrets:`)
| Secret (callee)       | Required | Role                                                                                          |
... [lean-ctx: omitted 2 lines]
| `BOT_APP_CLIENT_ID`   | no       | GitHub App client ID for ruleset-bypass / elevated API (preferred when configured).           |
... [lean-ctx: omitted 1 lines]
| `GH_TOKEN`            | no       | Optional explicit token override for resolution. Empty → job `GITHUB_TOKEN` (`github.token`). |
Caller maps repository secrets via explicit `secrets:` (e.g. `BOT_APP_CLIENT_ID: ${{ secrets.MAINTENANCE_BOT_APP_CLIENT_ID }}`). See [Loop Caller Inputs Reference — Credentials](workflows/loop-caller-inputs-reference.md#credentials-via-secrets).
... [lean-ctx: omitted 1 lines]
### GitHub token resolution
Each job that talks to GitHub (detect, record-skip, agent-l1/l2, finalize) runs `loop-resolve-push-token` **inside that job** and uses only the same-job step output.
... [lean-ctx: omitted 1 lines]
1. GitHub App installation token (when `BOT_APP_*` are set and mint succeeds)
... [lean-ctx: omitted 5 lines]
| Masked / secret values cannot cross jobs via `needs.*.outputs` | After `::add-mask::` (or App-token mint masking), job outputs are redacted/empty for dependents |
... [lean-ctx: omitted 2 lines]
So **credentials** (`BOT_APP_*`, optional `GH_TOKEN`) are what we share across jobs/workflows; the **resolved token string** is minted per job. Commonization is the resolve **action**, not a single minted value.
`ci-loop-caller` / `ci-loop-caller-entity` pass `BOT_APP_*` + `GH_TOKEN` into `ci-loop-agent`; the agent resolves again in `agent-l1` / `agent-l2` / `finalize`.
... [lean-ctx: omitted 1 lines]
For the automatic job `GITHUB_TOKEN`, effective scopes **are** that job's `permissions:` (intersected with repository/org workflow defaults). It is not a separate full-power token that the job then “limits.”
... [lean-ctx: omitted 3 lines]
| `record-skip`           | push run-log / state PR    | `contents: write`, `pull-requests: write`                                  |
| `agent-l2` / `finalize` | push, PR create/comment    | `contents: write`, `pull-requests: write`                                  |
... [lean-ctx: omitted 5 lines]
| `workflow_call` secret | `GH_TOKEN`     | Avoid reserved `GITHUB_TOKEN` / `github_token` |
| Composite action I/O   | `github_token` | `loop-*` actions                               |
... [lean-ctx: omitted 1 lines]
### Nesting
```text
on-loop-*  →  ci-loop-caller  →  ci-loop-agent
```
... [lean-ctx: omitted 1 lines]
## Extensibility: Adding a New Loop
1. Add `.apm/packages/<domain>/<name>/` (skill + `scripts/detect_*.sh`).
... [lean-ctx: omitted 2 lines]
4. For CI sweeper callers: list only repair-target workflows under `workflow_run.workflows` (omit `on-loop-*` / `ci-loop-*`).
... [lean-ctx: omitted 2 lines]
New domain env keys go into `detect_domain_env_json` without editing reusable job steps (when using approach B).
## Rejected Alternatives
| Alternative                                 | Why rejected                                                                                   |
... [lean-ctx: omitted 1 lines]
| Merge all loops into one `on-loop.yaml`     | Cannot have per-loop cron, workflow identity, or isolated concurrency/budget                   |
| Caller workflow-level `env:`                | Unnecessary after reusable extraction; inconsistent with other `on-*` callers                  |
... [lean-ctx: omitted 2 lines]
| Config file only (no `with:`)               | Hides tunables from workflow YAML; harder to review in PRs; optional later as additive pattern |
... [lean-ctx: omitted 1 lines]
| `workflow_call` secret named `GITHUB_TOKEN` | Reserved name; reusable workflow fails to load                                                 |
## Implementation Checklist
### 1. Create reusable workflow
- [x] Add `.github/workflows/ci-loop-caller.yaml` with `workflow_call` inputs (alphabetical).
... [lean-ctx: omitted 2 lines]
- [x] Mirror execute `with:` passthrough from current callers (including `auto_merge` guard).
... [lean-ctx: omitted 1 lines]
### 2. Thin existing callers
- [x] Refactor `on-loop-changelog.yaml` to single `loop` job + `with:`.
- [x] Refactor `on-loop-docs-updater.yaml`.
- [x] Refactor `on-loop-ci-sweeper.yaml` (`ci-loop-caller-full-github.yaml` profile, execute-only inputs).
... [lean-ctx: omitted 2 lines]
### 3. Documentation
[… truncated at ~4149 of 4701 tokens — use ctx_read with lines= parameter to see specific sections]
