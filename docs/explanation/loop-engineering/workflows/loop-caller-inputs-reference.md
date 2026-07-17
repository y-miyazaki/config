# Loop Caller Inputs Reference

`workflow_call` inputs for `.github/workflows/ci-loop-caller.yaml`, passed from thin `on-loop-*.yaml` callers via `with:`.

**Status:** Implemented. Callers pass configuration via `with:` on `ci-loop-caller.yaml`. Legacy workflow-level `env:` is documented in [Loop Caller `env` Reference](loop-caller-env-reference.md).

| Layer                              | Document                                                                                               |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Reusable workflow design           | [Loop Caller Reusable Workflow Design](../loop-caller-reusable-design.md)                              |
| Job graph and invariants           | [Loop Caller Workflows Design](../loop-caller-workflows-design.md)                                     |
| Platform branch/finalize semantics | [Multi-Branch Loops — canonical table](../multi-branch-loops-design.md#caller-configuration-canonical) |
| Per-loop behavior                  | [Workflow design docs](#per-loop-design-docs)                                                          |

Keys in `ci-loop-caller.yaml` `inputs` and caller `with:` blocks are **alphabetically ordered** (repository workflow convention).

## How inputs flow

```text
on-loop-*.yaml (with:)
  → ci-loop-caller.yaml
      detect   → loop-detect (+ detect_domain_env_json export)
      execute  → ci-loop-agent.yaml (matrix)
      record-skip → loop-run-log
```

## Credentials (via `secrets:`)

Per [GitHub reusable workflow docs](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-inputs-and-secrets-in-a-reusable-workflow), credentials use the **`secrets:`** keyword — not `with:`. Do **not** use `secrets: inherit` (locks callee secret names to the caller's names).

| Secret (callee)       | Required | Role                                                                          |
| --------------------- | -------- | ----------------------------------------------------------------------------- |
| `AGENT_TOKEN`         | yes      | Engine API key. Mapped internally per `engine` input.                         |
| `GH_TOKEN_PUSH`       | no       | Git push / PR creation for finalize. Defaults to `github.token` when omitted. |
| `BOT_APP_CLIENT_ID`   | no       | GitHub App client ID for ruleset-bypass `.loop/*` pushes.                     |
| `BOT_APP_PRIVATE_KEY` | no       | GitHub App private key for maintenance bot token.                             |

Callers remap local names explicitly. Optional `with: environment:` lets reusable jobs bind an environment for environment-scoped secrets named like the callee expects (`BOT_APP_*`). Callers cannot set `environment:` on a job that `uses:` a reusable.

Example caller mapping:

```yaml
jobs:
  loop:
    uses: org/repo/.github/workflows/ci-loop-caller.yaml@<sha>
    secrets:
      AGENT_TOKEN: ${{ secrets.AGENT_TOKEN }}
      BOT_APP_CLIENT_ID: ${{ secrets.MAINTENANCE_BOT_APP_CLIENT_ID }}
      BOT_APP_PRIVATE_KEY: ${{ secrets.MAINTENANCE_BOT_APP_PRIVATE_KEY }}
    with:
      environment: default
```

## Branch configuration

Branch-related caller inputs fall into **three roles**. Mixing them up is the most common configuration mistake.

| Role         | Question it answers                                       | `ci-loop-caller` inputs                           | Dogfood (typical)                            |
| ------------ | --------------------------------------------------------- | ------------------------------------------------- | -------------------------------------------- |
| **Watch**    | Which branches / PR heads does detect scan?               | `branch_match`, `branch_match_mode`, `pr_enabled` | `main`, `glob`, `false` (ci-sweeper: `true`) |
| **State**    | Where do `.loop/*` commits (state, budget, run-log) land? | `branch_state`, `state_file`                      | `main`, (default path)                       |
| **Autonomy** | Human review vs GitHub auto-merge on the **bot fix PR**   | `level`                                           | `L2`                                         |

Platform semantics (target model, verifier baseline): [Multi-Branch Loops Design](../multi-branch-loops-design.md#branch-roles-and-fix-direction).

### Watch: `branch_match` + `branch_match_mode`

`loop-detect` resolves `branch_match` into concrete branch names using `branch_match_mode`:

| `branch_match_mode` | `branch_match` meaning               | Example                                                      |
| ------------------- | ------------------------------------ | ------------------------------------------------------------ |
| `list`              | Exact branch names (comma-separated) | `main,develop` → scan those two only                         |
| `glob` (default)    | Patterns matched against `origin/*`  | `main` → `main`; `release/*` → all matching release branches |
| `regex`             | Extended regex per pattern           | `^release/.*`                                                |

When `branch_match` is **empty**, detect scans **`branch_state` only** (single-branch fallback).

`pr_enabled: true` adds a second watch path: open PR **head** branches (see [Fix direction](#fix-direction-integration-vs-pull_request) below). Does not change where state is stored.

**Wire name today:** `pull_requests` on `ci-loop-caller.yaml` (rename to `pr_enabled` planned).

### State: `branch_state` + `state_file`

| Input          | Role                                                                                                                                                                                                                                                                                                                                |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `branch_state` | Branch for **all** `.loop/*` persistence commits — `state-<loop_name>.json`, budget file, run-log. Also used for **state migration** (legacy flat `last_sha` → `targets["integration:<branch_state>"]`) and as the **fallback watch target** when `branch_match` is empty. Stays on `main` even when fixing `develop` or a PR head. |
| `state_file`   | Optional override for the state JSON path (default `.loop/state-<loop_name>.json`). Does not change which branch receives commits — only the file path.                                                                                                                                                                             |

Dogfood sets `branch_match: main` and `branch_state: main`. That matches the usual model: **watch `main` (and optionally other integration branches / PR heads); keep loop metadata on `main`.**

### Level × finalize matrix

Dogfood loops (changelog, docs-triage, ci-sweeper) use **`open_pr` for all modes**. Callers set **`level` only** — not `finalize_integration` / `finalize_pull_request`.

| Mode           | `target.finalize` (platform default) | L2                                    | L3                                                    |
| -------------- | ------------------------------------ | ------------------------------------- | ----------------------------------------------------- |
| `integration`  | `open_pr`                            | Bot fix PR → `to.branch`; human merge | Bot fix PR → `to.branch`; **auto-merge**              |
| `pull_request` | `open_pr`                            | Bot fix PR → PR head; notify human PR | Bot fix PR → PR head; **auto-merge**; notify human PR |

L3 **auto-merge** is [GitHub PR auto-merge](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request) on the **bot fix PR** — not direct push to the branch. The human's open PR is not auto-merged.

Platform exception paths (`push`, `push_head`) exist for advanced callers; dogfood does not use them. See [Finalize strategy matrix](../loop-engineering-design.md#finalize-strategy-matrix).

Optional overrides (not used in dogfood): `finalize_integration`, `finalize_pull_request` on `ci-loop-caller.yaml` → `loop-detect` env. Default when omitted: integration and pull_request both resolve to `open_pr`.

### Fix direction: integration vs `pull_request`

Detect builds one `target_json` per watch context. **Execute** checks out `from.branch` / `from.ref`. **Finalize** opens a bot fix PR targeting `to.branch` (watched integration branch or PR head), not `branch_state`.

```text
integration mode (changelog, docs-triage, ci-sweeper on main)
  watch:  branch_match → checkout main (or develop, release/*, …)
  worktree: from.branch == watched integration branch
  finalize: open_pr → bot fix PR to to.branch
  L2: human merges fix PR
  L3: auto-merge on fix PR
  state: branch_state (main) — separate from fix target

pull_request mode (ci-sweeper, pr_enabled: true)
  watch:  open PR head branch (e.g. hotfix/0001)
  worktree: from.branch == PR head
  finalize: open_pr → bot fix PR to to.branch (PR head, not main)
  loop-notify-pr: comment on human PR with fix PR link + summary
  L2: human merges bot fix PR into head branch; then merges human PR
  L3: auto-merge bot fix PR into head branch
  verifier diff baseline: base.branch (PR base, e.g. main)
  state: branch_state (main) — separate from fix target
```

| Mode           | Watched branch            | Bot fix PR targets | Human PR notify |
| -------------- | ------------------------- | ------------------ | --------------- |
| `integration`  | `integration:main` (etc.) | `to.branch`        | No              |
| `pull_request` | PR head (`feature/…`)     | PR head branch     | Yes             |

**Summary:** monitored branches and PR heads are **watch targets**; `branch_state` is **metadata only**; fixes and pushes always target the **branch that was watched** (`to.branch`), not `main`, unless `main` itself is the watch target.

### Branch-related inputs (complete)

| Input               | Type    | Role                                                                  | Default                               | Maps to `loop-detect`                   |
| ------------------- | ------- | --------------------------------------------------------------------- | ------------------------------------- | --------------------------------------- |
| `branch_match`      | string  | Comma-separated patterns / names to watch                             | `""` (→ `branch_state`)               | `loop_integration_branches`             |
| `branch_match_mode` | string  | How to interpret `branch_match` patterns                              | `glob`                                | `loop_branch_match`                     |
| `branch_state`      | string  | `.loop/*` persistence, state migration, empty `branch_match` fallback | (required)                            | `base_branch`, `loop_state_push_branch` |
| `level`             | string  | `L2` human merge on bot fix PR; `L3` GitHub auto-merge on bot fix PR  | `L2`                                  | `level`                                 |
| `priority`          | string  | Order when both integration and PR candidates exist                   | `integration,pull_request`            | `loop_priority`                         |
| `pr_enabled`        | boolean | Watch open PR heads (`pull_requests` wire name today)                 | `false`                               | `loop_pull_requests`                    |
| `state_file`        | string  | Override state JSON path                                              | `""` (`.loop/state-<loop_name>.json`) | `state_file`                            |

Related but not branch-scoped: `max_targets_per_schedule` (fan-out cap after watch), `pr_exclude` / `pr_include_bots` (PR watch filters).

Optional platform overrides (dogfood omit): `finalize_integration`, `finalize_pull_request` — default `open_pr` for both modes. See [Level × finalize matrix](#level--finalize-matrix).

## Agent and engine

| Input                         | Type   | Description                                                                | Default (dogfood)       |
| ----------------------------- | ------ | -------------------------------------------------------------------------- | ----------------------- |
| `agent_implementer_max_turns` | number | Max implementer agent turns per loop attempt                               | `5`–`8` (loop-specific) |
| `agent_implementer_model`     | string | Implementer model ID. Empty = engine default                               | `grok-4.5-medium`       |
| `agent_loop_max_attempts`     | number | Max Agent→Verify retry cycles before finalize records failure              | `3`                     |
| `agent_verifier_criteria`     | string | Caller-owned markdown rubric (`## Criteria for APPROVE` / `REJECT`)        | Domain-specific         |
| `agent_verifier_max_turns`    | number | Max verifier agent turns per verification                                  | `3`                     |
| `agent_verifier_model`        | string | Verifier model ID                                                          | `composer-2.5`          |
| `engine`                      | string | AI engine: `claude` \| `copilot` \| `codex` \| `cursor`                    | `cursor`                |
| `level`                       | string | Autonomy: `L1` \| `L2` \| `L3`                                             | `L2`                    |
| `skill_name`                  | string | Skill package (e.g. `loop-changelog`). Must match `.agents/skills/<name>/` | Per loop                |

## Platform inputs

Canonical branch/finalize/PR semantics: [Multi-Branch canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Input                       | Type    | Description                                                                                                                 | Default (dogfood)                              |
| --------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `allowlist`                 | string  | Comma-separated globs the implementer may modify                                                                            | Per loop                                       |
| `branch_match`              | string  | Comma-separated branch patterns to watch                                                                                    | `main`                                         |
| `branch_match_mode`         | string  | How to interpret `branch_match`: `list`, `glob`, or `regex`                                                                 | `glob`                                         |
| `branch_state`              | string  | Branch for `.loop/*` persistence, state migration, and watch fallback                                                       | `main`                                         |
| `budget_max_runs_per_day`   | number  | Daily run cap keyed by `loop_name` (each matrix cell counts)                                                                | `1`–`5`                                        |
| `budget_max_tokens_per_day` | number  | Daily aggregated token cap                                                                                                  | `500000`–`1000000`                             |
| `denylist`                  | string  | Comma-separated globs the implementer must not touch                                                                        | ci-sweeper only                                |
| `detect_script`             | string  | Path to domain `detect_*.sh` under loop skill package                                                                       | Per loop                                       |
| `finalize_integration`      | string  | **Optional override.** Default `open_pr`. Exception: `push` (direct write; not dogfood).                                    | Omit (platform default)                        |
| `finalize_pull_request`     | string  | **Optional override.** Default `open_pr`. Exception: `push_head` (not dogfood).                                             | Omit (platform default)                        |
| `infer_files_pattern`       | string  | Extended regex to infer file paths from verifier text                                                                       | Per loop                                       |
| `loop_name`                 | string  | Loop identifier: `.loop/state-<loop_name>.json`, budget key, run-log tag. Align caller filename: `on-loop-<loop_name>.yaml` | Per loop                                       |
| `max_targets_per_schedule`  | number  | Max targets per cron tick after priority/`acting_on` filters                                                                | `3`                                            |
| `no_changes_verdict`        | string  | `APPROVE` \| `REJECT` when implementer produces no file diff                                                                | `REJECT`                                       |
| `pr_body`                   | string  | Static markdown prefix for finalize PR body                                                                                 | Per loop                                       |
| `pr_exclude`                | string  | PR exclusion tokens: `fork`, `draft`, `label:<name>`, `wip_title`                                                           | ci-sweeper                                     |
| `pr_include_bots`           | string  | Comma-separated bot logins to include when scanning PRs. Empty = exclude all bots                                           | `""`                                           |
| `pr_title`                  | string  | PR title when finalize strategy is `open_pr`                                                                                | Per loop                                       |
| `prompt_instructions`       | string  | Domain-specific implementer instructions for `loop-prompt-generate`                                                         | Per loop                                       |
| `pr_enabled`                | boolean | Watch open PR heads for detect. **Wire name today:** `pull_requests`                                                        | `false` except ci-sweeper                      |
| `state_bundle_with_fix_pr`  | boolean | Commit loop state on the fix branch before `open_pr` (single reviewable PR)                                                 | `false` (changelog uses merge-gated `pending`) |
| `state_file`                | string  | Override state JSON path                                                                                                    | `.loop/state-<loop_name>.json`                 |

### Optional platform inputs (supported by `loop-detect`)

| Input          | Description                                        | Default                               |
| -------------- | -------------------------------------------------- | ------------------------------------- |
| `budget_file`  | Path to loop budget JSON                           | `.loop/loop-budget.json`              |
| `priority`     | Target mode priority order (comma-separated)       | `integration,pull_request`            |
| `run_log_file` | JSONL run log path for budget aggregation          | `.loop/loop-run-log.md`               |
| `token`        | GitHub token for PR enumeration and detect scripts | `""` (`github.token` inside reusable) |

## `loop-detect` input mapping

`ci-loop-caller` inputs map to `loop-detect` action `with:` as follows. Names without a `loop_` prefix on the caller side expand when passed to the action.

| `ci-loop-caller` input         | `loop-detect` input                     |
| ------------------------------ | --------------------------------------- |
| `agent_implementer_max_turns`  | `agent_implementer_max_turns`           |
| `agent_implementer_model`      | `agent_implementer_model`               |
| `agent_loop_max_attempts`      | `agent_loop_max_attempts`               |
| `agent_verifier_criteria`      | `agent_verifier_criteria`               |
| `agent_verifier_max_turns`     | `agent_verifier_max_turns`              |
| `agent_verifier_model`         | `agent_verifier_model`                  |
| `allowlist`                    | `allowlist`                             |
| `branch_match`                 | `loop_integration_branches`             |
| `branch_match_mode`            | `loop_branch_match`                     |
| `branch_state`                 | `base_branch`, `loop_state_push_branch` |
| `budget_file`                  | `budget_file`                           |
| `budget_max_runs_per_day`      | `budget_max_runs_per_day`               |
| `budget_max_tokens_per_day`    | `budget_max_tokens_per_day`             |
| `detect_script`                | `detect_script`                         |
| `engine`                       | `engine`                                |
| `finalize_integration`         | `loop_finalize_integration`             |
| `finalize_pull_request`        | `loop_finalize_pull_request`            |
| `infer_files_pattern`          | `infer_files_pattern`                   |
| `level`                        | `level`                                 |
| `loop_name`                    | `loop_name`                             |
| `max_targets_per_schedule`     | `loop_max_targets_per_schedule`         |
| `no_changes_verdict`           | `no_changes_verdict`                    |
| `pr_body`                      | `pr_body`                               |
| `pr_exclude`                   | `loop_pr_exclude`                       |
| `pr_include_bots`              | `loop_pr_include_bots`                  |
| `priority`                     | `loop_priority`                         |
| `prompt_instructions`          | `prompt_instructions`                   |
| `pr_enabled` / `pull_requests` | `loop_pull_requests`                    |
| `run_log_file`                 | `run_log_file`                          |
| `skill_name`                   | `skill_name`                            |
| `state_file`                   | `state_file`                            |
| `token`                        | `token`                                 |

Domain-specific detect script variables use `detect_domain_env_json` keys (not `loop-detect` inputs).

## Execute-only inputs

Passed through `ci-loop-caller` to `ci-loop-agent.yaml` when non-empty.

| Input                       | Description                                                | Default (dogfood)                                     |
| --------------------------- | ---------------------------------------------------------- | ----------------------------------------------------- |
| `additional_commit_paths`   | Extra paths included in finalize commit (e.g. ledger file) | `.loop/state-ci-sweeper-run-ledger.json` (ci-sweeper) |
| `domain_persistence_script` | Bash script for `loop-finalize` domain persistence         | ci-sweeper ledger script                              |
| `state_bundle_with_fix_pr`  | Commit loop state on fix branch before `open_pr`           | `false` (changelog uses merge-gated `pending`)        |

## Detect permissions

Profile registry: `.github/actions/validate-loop-caller-permissions/detect-permissions-profiles.yaml`. Caller workflow `permissions` must include the execute baseline plus any profile `caller_adds`. Select the profile by which reusable workflow the thin caller `uses:` (`ci-loop-caller.yaml` for default; `ci-loop-caller-full-github.yaml` for full-github).

### Profile summary

| Profile       | Reusable workflow                 | Detect job | Caller additions beyond execute baseline |
| ------------- | --------------------------------- | ---------- | ---------------------------------------- |
| `default`     | `ci-loop-caller.yaml`             | `detect`   | (none)                                   |
| `full-github` | `ci-loop-caller-full-github.yaml` | `detect`   | `actions: read`                          |

## Domain detect environment (`detect_domain_env_json`)

JSON object string. Exported to the detect job environment before `loop-detect` runs. Keys use **detect-script env names** (historically `CHANGELOG_*`, `CI_SWEEPER_*`, etc.). Empty object `{}` when no domain env is required.

```yaml
detect_domain_env_json: >-
  {"CHANGELOG_FILE":"CHANGELOG.md","CHANGELOG_MERGE_COMMITS":"false"}
```

### Changelog (`loop-changelog`)

| JSON key                  | Description                                                      | Dogfood value  |
| ------------------------- | ---------------------------------------------------------------- | -------------- |
| `CHANGELOG_FILE`          | Target changelog path                                            | `CHANGELOG.md` |
| `CHANGELOG_MERGE_COMMITS` | `"true"` includes merge commits; `"false"` applies `--no-merges` | `"false"`      |

### CI sweeper (`loop-ci-sweeper`)

| JSON key                         | Description                                     | Dogfood value                            |
| -------------------------------- | ----------------------------------------------- | ---------------------------------------- |
| `CI_SWEEPER_LEDGER_FILE`         | JSON ledger for `workflow_run_id` dedupe        | `.loop/state-ci-sweeper-run-ledger.json` |
| `CI_SWEEPER_REJECT_MAX_RETRIES`  | Max retries per run ID when policy is `limited` | `"3"`                                    |
| `CI_SWEEPER_REJECT_RETRY_POLICY` | `block`, `retry`, or `limited`                  | `block`                                  |

`GH_TOKEN` is **not** passed via `detect_domain_env_json` — use the `token` input on `ci-loop-caller` (maps to `loop-detect`). Reusable defaults to `github.token` when empty.

Event keys (embed in `detect_domain_env_json` when `workflow_run` trigger is enabled on the caller):

```yaml
detect_domain_env_json: ${{ format('{{"CI_SWEEPER_HEAD_SHA":"{0}","CI_SWEEPER_WORKFLOW_RUN_ID":"{1}","CI_SWEEPER_HEAD_BRANCH":"{2}"}}', github.event.workflow_run.head_sha || github.sha, github.event.workflow_run.id || '', github.event.workflow_run.head_branch || 'main') }}
```

| JSON key                     | Description                     |
| ---------------------------- | ------------------------------- |
| `CI_SWEEPER_HEAD_BRANCH`     | Failed run head branch          |
| `CI_SWEEPER_HEAD_SHA`        | Failed run head SHA             |
| `CI_SWEEPER_WORKFLOW_RUN_ID` | Failed run ID for ledger dedupe |
| `CI_SWEEPER_WORKFLOW_NAME`   | Failed workflow display name    |
| `CI_SWEEPER_RUN_URL`         | HTML URL of failed run          |

### Docs triage (`loop-docs-triage`)

| JSON key                  | Description                                          | Dogfood value            |
| ------------------------- | ---------------------------------------------------- | ------------------------ |
| `DOCS_TRIAGE_DOC_GLOBS`   | Comma-separated doc file globs for git-diff analysis | `docs/**/*.md,README.md` |
| `DOCS_TRIAGE_EXTRA_FILES` | Additional non-glob paths                            | `mkdocs.yml`             |

## Legacy `env` name mapping

| Legacy caller `env`                                           | `ci-loop-caller` input                                        |
| ------------------------------------------------------------- | ------------------------------------------------------------- |
| `AGENT_*`, `DEFAULT_ENGINE`, `DEFAULT_LEVEL`, `SKILL_NAME`    | Same name (lowercase `engine`, `level` for engine/level)      |
| `DEFAULT_BASE_BRANCH`, `LOOP_STATE_PUSH_BRANCH`               | `branch_state`                                                |
| `LOOP_ALLOWLIST`                                              | `allowlist`                                                   |
| `LOOP_BUDGET_MAX_RUNS_PER_DAY`                                | `budget_max_runs_per_day`                                     |
| `LOOP_BUDGET_MAX_TOKENS_PER_DAY`                              | `budget_max_tokens_per_day`                                   |
| `LOOP_DENYLIST`                                               | `denylist`                                                    |
| `LOOP_DETECT_SCRIPT`                                          | `detect_script`                                               |
| `LOOP_FINALIZE_INTEGRATION`                                   | `finalize_integration`                                        |
| `LOOP_FINALIZE_PULL_REQUEST`                                  | `finalize_pull_request`                                       |
| `LOOP_INFER_FILES_PATTERN`                                    | `infer_files_pattern`                                         |
| `LOOP_INTEGRATION_BRANCHES`                                   | `branch_match`                                                |
| `LOOP_BRANCH_MATCH`                                           | `branch_match_mode`                                           |
| `LOOP_MAX_TARGETS_PER_SCHEDULE`                               | `max_targets_per_schedule`                                    |
| `LOOP_NAME`                                                   | `loop_name`                                                   |
| `LOOP_NO_CHANGES_VERDICT`                                     | `no_changes_verdict`                                          |
| `LOOP_PR_*`, `LOOP_PROMPT_INSTRUCTIONS`, `LOOP_PULL_REQUESTS` | `pr_*`, `prompt_instructions`, `pr_enabled` / `pull_requests` |
| `CHANGELOG_*`, `CI_SWEEPER_*`, `DOCS_TRIAGE_*`                | `detect_domain_env_json` keys                                 |
| `DOMAIN_PERSISTENCE_SCRIPT`                                   | `domain_persistence_script`                                   |

## Per-loop design docs

| Loop        | Design doc                                                         | Caller workflow            |
| ----------- | ------------------------------------------------------------------ | -------------------------- |
| changelog   | [Changelog Workflow Design](loop-changelog-workflow-design.md)     | `on-loop-changelog.yaml`   |
| ci-sweeper  | [CI Sweeper Workflow Design](loop-ci-sweeper-workflow-design.md)   | `on-loop-ci-sweeper.yaml`  |
| docs-triage | [Docs Triage Workflow Design](loop-docs-triage-workflow-design.md) | `on-loop-docs-triage.yaml` |

## References

- [Loop Caller Reusable Workflow Design](../loop-caller-reusable-design.md)
- [Loop Caller `env` Reference](loop-caller-env-reference.md) (legacy)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
