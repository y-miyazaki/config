# Loop Caller Inputs Reference

`workflow_call` inputs for the two loop caller reusable workflows, passed from thin `on-loop-*.yaml` callers via `with:`.

| Reusable workflow            | Detect action        | Callers                                                                                                                   |
| ---------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `ci-loop-caller.yaml`        | `loop-detect`        | Branch / PR-head loops (changelog, ci-sweeper, docs-updater, refactor, tech-debt, github-issue-autofix, github-pr-revise) |
| `ci-loop-caller-entity.yaml` | `loop-entity-detect` | Entity-event loops bound to one Issue / PR (github-issue-triage)                                                          |

Both share `ci-loop-agent.yaml` for execute and finalize. Inputs below apply to `ci-loop-caller.yaml`; the [entity caller](#entity-caller-ci-loop-caller-entityyaml) section lists how `ci-loop-caller-entity.yaml` differs.

**Status:** Implemented. Callers pass configuration via `with:` on `ci-loop-caller.yaml`.

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
      detect      → loop-detect (+ detect_domain_env_json export)
      ack-trigger → gh api reactions (only when ack_trigger_comment)
      execute     → ci-loop-agent.yaml (matrix)
      record-skip → loop-run-log

on-loop-*.yaml (with:)            # entity-event loops
  → ci-loop-caller-entity.yaml
      detect      → loop-entity-detect (+ dispatch_hook_script)
      execute     → ci-loop-agent.yaml (matrix)
      record-skip → loop-run-log
```

## Credentials (via `secrets:`)

Per [GitHub reusable workflow docs](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-inputs-and-secrets-in-a-reusable-workflow), credentials use the **`secrets:`** keyword — not `with:`. Do **not** use `secrets: inherit` (locks callee secret names to the caller's names).

| Secret (callee)       | Required | Role                                                                                |
| --------------------- | -------- | ----------------------------------------------------------------------------------- |
| `AGENT_TOKEN`         | yes      | Engine API key. Mapped internally per `engine` input.                               |
| `BOT_APP_CLIENT_ID`   | no       | GitHub App client ID for ruleset-bypass / elevated API (preferred when configured). |
| `BOT_APP_PRIVATE_KEY` | no       | GitHub App private key paired with `BOT_APP_CLIENT_ID`.                             |
| `GH_TOKEN`            | no       | Optional explicit token override. Empty → job `GITHUB_TOKEN` after App attempt.     |

Token minting is **per job** via `loop-resolve-push-token` (same-job step output only). Do not pass resolved tokens across jobs via `needs.*.outputs`. Design rationale: [GitHub token resolution](../loop-caller-reusable-design.md#github-token-resolution). Do not declare `workflow_call` secret `GITHUB_TOKEN` / `github_token` (reserved names).

Callers remap local names explicitly. Optional `with: environment:` lets reusable jobs bind an environment for environment-scoped secrets named like the callee expects (`BOT_APP_*`). Callers cannot set `environment:` on a job that `uses:` a reusable.

When App credentials live only in that environment, every job that mints a token (`detect`, `agent-l1`, `agent-l2`, `finalize`, `record-skip`) must set `environment:` so `BOT_APP_*` resolve. Without it, mint is skipped and attribution falls back to `github-actions[bot]`. Remapping `MAINTENANCE_BOT_*` from the caller job cannot read environment-scoped values.

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

Platform semantics (target model, checker baseline): [Multi-Branch Loops Design](../multi-branch-loops-design.md#branch-roles-and-fix-direction).

### Scope: `scoped_pr_number`

Optional. When set, `loop-detect` fetches that open PR via `gh pr view` (does not list up to 50 PRs), drops integration watch targets, and keeps only that PR. Empty = no-op. Dogfood: [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md#domain-detect-environment-detect_domain_env_json).

### Watch: `branch_match` + `branch_match_mode`

`loop-detect` resolves `branch_match` into concrete branch names using `branch_match_mode`:

| `branch_match_mode` | `branch_match` meaning               | Example                                                      |
| ------------------- | ------------------------------------ | ------------------------------------------------------------ |
| `list`              | Exact branch names (comma-separated) | `main,develop` → scan those two only                         |
| `glob` (default)    | Patterns matched against `origin/*`  | `main` → `main`; `release/*` → all matching release branches |
| `regex`             | Extended regex per pattern           | `^release/.*`                                                |

When `branch_match` is **empty**, detect scans **`branch_state` only** (single-branch fallback).

`pr_enabled: true` adds a second watch path: open PR **head** branches (see [Fix direction](#fix-direction-integration-vs-pull_request) below). Does not change where state is stored.

### State: `branch_state` + `state_file`

| Input          | Role                                                                                                                                                                                                                                                                                                                                |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `branch_state` | Branch for **all** `.loop/*` persistence commits — `state-<loop_name>.json`, budget file, run-log. Also used for **state migration** (legacy flat `last_sha` → `targets["integration:<branch_state>"]`) and as the **fallback watch target** when `branch_match` is empty. Stays on `main` even when fixing `develop` or a PR head. |
| `state_file`   | Optional override for the state JSON path (default `.loop/state-<loop_name>.json`). Does not change which branch receives commits — only the file path.                                                                                                                                                                             |

Dogfood sets `branch_match: main` and `branch_state: main`. That matches the usual model: **watch `main` (and optionally other integration branches / PR heads); keep loop metadata on `main`.**

### Level × finalize matrix

Dogfood loops use **`delivery: open_pr`** only — git landing (`open_pr` / `push` / `push_head`) is derived inside `loop-detect` from `delivery`. Advanced overrides: optional `git_landing_integration` / `git_landing_pull_request` on `ci-loop-caller` (forwarded to `loop-detect`).

| Mode           | `target.finalize` (derived from `delivery`) | L2                                    | L3                                                    |
| -------------- | ------------------------------------------- | ------------------------------------- | ----------------------------------------------------- |
| `integration`  | `open_pr`                                   | Bot fix PR → `to.branch`; human merge | Bot fix PR → `to.branch`; **auto-merge**              |
| `pull_request` | `open_pr`                                   | Bot fix PR → PR head; notify human PR | Bot fix PR → PR head; **auto-merge**; notify human PR |

L3 **auto-merge** is [GitHub PR auto-merge](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request) on the **bot fix PR** — not direct push to the branch. The human's open PR is not auto-merged.

Platform exception paths (`push`, `push_head`) are advanced `git_landing_*` overrides when `delivery: open_pr`; dogfood does not set them. See [Finalize strategy matrix](../loop-engineering-design.md#finalize-strategy-matrix).

### Fix direction: integration vs `pull_request`

Detect builds one `target_json` per watch context. **Execute** checks out `from.branch` / `from.ref`. **Finalize** opens a bot fix PR targeting `to.branch` (watched integration branch or PR head), not `branch_state`.

```text
integration mode (changelog, docs-updater, ci-sweeper on main)
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
  checker diff baseline: base.branch (PR base, e.g. main)
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
| `pr_enabled`        | boolean | Watch open PR heads                                                   | `false`                               | `loop_pr_enabled`                       |
| `state_file`        | string  | Override state JSON path                                              | `""` (`.loop/state-<loop_name>.json`) | `state_file`                            |

Related but not branch-scoped: `max_targets_per_schedule` (fan-out cap after watch), `pr_exclude` / `pr_include_bots` (PR watch filters).

## Agent and engine

| Input                        | Type   | Description                                                                                                                                                                                                                                                                                                                                             | Default (dogfood)      |
| ---------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| `agent_maker_max_turns`      | number | Max maker agent turns per loop attempt                                                                                                                                                                                                                                                                                                                  | `100` (all loops)      |
| `agent_maker_model`          | string | Maker model ID. Empty = engine default                                                                                                                                                                                                                                                                                                                  | `claude-sonnet-5`      |
| `agent_maker_effort`         | string | Maker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                                                                                                                                                            | `medium`               |
| `agent_loop_max_attempts`    | number | Max Agent→Verify retry cycles before finalize records failure                                                                                                                                                                                                                                                                                           | `3`                    |
| `agent_checker_instructions` | string | Caller-owned markdown rubric (`## Criteria for APPROVE` / `REJECT`)                                                                                                                                                                                                                                                                                     | Domain-specific        |
| `agent_checker_max_turns`    | number | Max checker agent turns per verification                                                                                                                                                                                                                                                                                                                | `100` (all loops)      |
| `agent_checker_model`        | string | Checker model ID                                                                                                                                                                                                                                                                                                                                        | `claude-opus-5`        |
| `agent_checker_effort`       | string | Checker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                                                                                                                                                          | `medium`               |
| `engine`                     | string | AI engine: `claude` \| `copilot` \| `codex` \| `cursor`                                                                                                                                                                                                                                                                                                 | `claude`               |
| `level`                      | string | Autonomy: `L1` \| `L2` \| `L3`                                                                                                                                                                                                                                                                                                                          | `L2`                   |
| `agent_maker_skill_name`     | string | Maker skill (e.g. `changelog`). Must match `.agents/skills/<name>/`                                                                                                                                                                                                                                                                                     | Per loop               |
| `agent_checker_skill_name`   | string | Checker skill slash-loaded by `loop-execute` (not the maker)                                                                                                                                                                                                                                                                                            | `loop-verifier`        |
| `agent_allowed_tools`        | string | Newline-separated permission rules the skill needs, in the engine's own syntax (claude: `Bash(gh issue edit:*)`). Added on top of the host repository's `.claude/settings.json`; empty grants nothing beyond it. Only `claude` applies these rules — other engines warn and ignore them (see [Engine permission surfaces](#engine-permission-surfaces)) | Per loop (often empty) |

### Engine permission surfaces

Permission rule syntax does not translate between engines, so `loop-execute` never mistranslates `agent_allowed_tools`. What each engine actually enforces differs:

| Engine    | Host repository config applied                                                | Blanket flag passed  |
| --------- | ----------------------------------------------------------------------------- | -------------------- |
| `claude`  | `.claude/settings.json` (`allow` / `deny` / `ask`) plus `agent_allowed_tools` | none                 |
| `cursor`  | `.cursor/cli.json` deny rules; `--force` short-circuits its allow rules       | `--trust`, `--force` |
| `copilot` | none                                                                          | `--allow-all-tools`  |
| `codex`   | none — the CLI has no per-tool allowlist                                      | `--auto-approve`     |

`claude` is the only engine that enforces the repository's permission policy. Its `allow` rules need workspace trust, which `loop-execute` grants for `GITHUB_WORKSPACE` before the session starts; without that step Claude Code silently ignores `permissions.allow` and only `agent_allowed_tools` takes effect.

## Platform inputs

Canonical branch/finalize/PR semantics: [Multi-Branch canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Input                       | Type    | Description                                                                                                                                                                                                                                                                                                                                        | Default (dogfood)                                            |
| --------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `ack_trigger_comment`       | boolean | Run the `ack-trigger` job after detect proceeds: posts an `eyes` reaction on each gathered comment (fallback: the trigger comment). Comment webhooks only                                                                                                                                                                                          | `false` (pr-revise: `true`)                                  |
| `allowlist`                 | string  | Comma-separated globs the maker may modify                                                                                                                                                                                                                                                                                                         | Per loop                                                     |
| `branch_match`              | string  | Comma-separated branch patterns to watch                                                                                                                                                                                                                                                                                                           | `main`                                                       |
| `branch_match_mode`         | string  | How to interpret `branch_match`: `list`, `glob`, or `regex`                                                                                                                                                                                                                                                                                        | `glob`                                                       |
| `branch_state`              | string  | Branch for `.loop/*` persistence, state migration, and watch fallback                                                                                                                                                                                                                                                                              | `main`                                                       |
| `budget_max_runs_per_day`   | number  | Daily run cap keyed by `loop_name` (each matrix cell counts). `.loop/loop-budget.json` overrides when present (ci-sweeper budget file: `50`)                                                                                                                                                                                                       | `1`–`20` (caller; budget file may be higher)                 |
| `budget_max_tokens_per_day` | number  | Daily aggregated token cap                                                                                                                                                                                                                                                                                                                         | `1000000` (all loops)                                        |
| `denylist`                  | string  | Comma-separated globs the maker must not touch. Empty applies the platform default (`DEFAULT_EXECUTE_DENYLIST` in `loop-execute/lib/paths.sh`: `**/.env,**/credentials*,**/secrets*`), so every loop keeps a secret-file guard. A value replaces that default rather than merging with it, so repeat the secret globs when adding repository paths | Empty (platform default); tech-debt adds `src/**,.github/**` |
| `delivery`                  | string  | Platform delivery after APPROVE: `log` \| `issue` \| `notion` \| `open_pr` \| `none` (not passed to skills). Drives `target.finalize` inside `loop-detect`.                                                                                                                                                                                        | `open_pr`                                                    |
| `detect_script`             | string  | Path to domain `detect_*.sh` under the skill package (e.g. `.agents/skills/docs-updater/scripts/detect_changes.sh`)                                                                                                                                                                                                                                | Per loop                                                     |
| `environment`               | string  | GitHub environment bound by every reusable job that mints a token, so environment-scoped `BOT_APP_*` resolve (see [Credentials](#credentials-via-secrets))                                                                                                                                                                                         | `default`                                                    |
| `infer_files_pattern`       | string  | Extended regex to infer file paths from checker text                                                                                                                                                                                                                                                                                               | Per loop                                                     |
| `loop_name`                 | string  | Loop identifier: `.loop/state-<loop_name>.json`, budget key, run-log tag. Align caller filename: `on-loop-<loop_name>.yaml`                                                                                                                                                                                                                        | Per loop                                                     |
| `max_targets_per_schedule`  | number  | Max targets per cron tick after priority filters                                                                                                                                                                                                                                                                                                   | `3`                                                          |
| `may_edit`                  | boolean | Agent worktree edit gate: `true` \| `false` (required; injected into `## Constraints`)                                                                                                                                                                                                                                                             | Per loop (explicit in dogfood callers)                       |
| `no_changes_verdict`        | string  | `APPROVE` \| `REJECT` when maker produces no file diff                                                                                                                                                                                                                                                                                             | `REJECT`                                                     |
| `pr_body`                   | string  | Optional static prefix (dogfood: `""`). `loop-finalize` composes the PR body: agent `## Overview` + `## Summary`, mechanical `## Failure context` / `## Changes` / `## Run Metadata`, and automation disclaimer. See [Loop PR Body Readable Design](../../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md).                        | `""`                                                         |
| `pr_draft`                  | boolean | Open the finalize PR as a draft when `delivery: open_pr`                                                                                                                                                                                                                                                                                           | `false` (issue-autofix: dispatch input)                      |
| `pr_exclude`                | string  | PR exclusion tokens: `fork`, `draft`, `label:<name>`, `wip_title`                                                                                                                                                                                                                                                                                  | ci-sweeper                                                   |
| `pr_include_bots`           | string  | Comma-separated bot logins to include when scanning PRs. Empty = exclude all bots                                                                                                                                                                                                                                                                  | `""`                                                         |
| `pr_title`                  | string  | PR title when finalize strategy is `open_pr`                                                                                                                                                                                                                                                                                                       | Per loop                                                     |
| `agent_maker_instructions`  | string  | Domain-specific maker instructions appended during `loop-detect` prompt assembly                                                                                                                                                                                                                                                                   | Per loop                                                     |
| `pr_enabled`                | boolean | Watch open PR heads for detect                                                                                                                                                                                                                                                                                                                     | `false` except ci-sweeper                                    |
| `state_file`                | string  | Override state JSON path                                                                                                                                                                                                                                                                                                                           | `.loop/state-<loop_name>.json`                               |
| `write_target`              | string  | Agent artifact when `may_edit` is `true`: `fix` \| `report` (required; injected into `## Constraints`)                                                                                                                                                                                                                                             | Per loop (`fix` except tech-debt `report`)                   |

**Four-plane contract:** See [Loop write target & delivery design](../../../superpowers/specs/2026-07-23-loop-write-target-delivery-design.md). `level` controls autonomy only; `may_edit` + `write_target` + `report_file` control agent edits; `delivery` controls platform finalize (skills do not see `delivery`).

**Readable PR body:** Dogfood callers set `pr_body: ""`; narrative is agent-owned (`## Overview`, `## Summary` tables). See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

### Optional platform inputs (supported by `loop-detect`)

| Input          | Description                                  | Default                    |
| -------------- | -------------------------------------------- | -------------------------- |
| `budget_file`  | Path to loop budget JSON                     | `.loop/loop-budget.json`   |
| `priority`     | Target mode priority order (comma-separated) | `integration,pull_request` |
| `run_log_file` | JSONL run log path for budget aggregation    | `.loop/loop-run-log.md`    |

## `loop-detect` input mapping

`ci-loop-caller` inputs map to `loop-detect` action `with:` as follows. Names without a `loop_` prefix on the caller side expand when passed to the action.

| `ci-loop-caller` input               | `loop-detect` input                       |
| ------------------------------------ | ----------------------------------------- |
| `agent_maker_max_turns`              | `agent_maker_max_turns`                   |
| `agent_maker_model`                  | `agent_maker_model`                       |
| `agent_loop_max_attempts`            | `agent_loop_max_attempts`                 |
| `agent_checker_instructions`         | `agent_checker_instructions`              |
| `agent_checker_max_turns`            | `agent_checker_max_turns`                 |
| `agent_checker_model`                | `agent_checker_model`                     |
| `allowlist`                          | `allowlist`                               |
| `branch_match`                       | `loop_integration_branches`               |
| `branch_match_mode`                  | `loop_branch_match`                       |
| `branch_state`                       | `base_branch`, `loop_state_push_branch`   |
| `budget_file`                        | `budget_file`                             |
| `budget_max_runs_per_day`            | `budget_max_runs_per_day`                 |
| `budget_max_tokens_per_day`          | `budget_max_tokens_per_day`               |
| `delivery`                           | `delivery`                                |
| `detect_script`                      | `detect_script`                           |
| `engine`                             | `engine`                                  |
| `git_landing_integration`            | `git_landing_integration`                 |
| `git_landing_pull_request`           | `git_landing_pull_request`                |
| `infer_files_pattern`                | `infer_files_pattern`                     |
| `level`                              | `level`                                   |
| `loop_name`                          | `loop_name`                               |
| `max_targets_per_schedule`           | `loop_max_targets_per_schedule`           |
| `may_edit`                           | `may_edit`                                |
| `no_changes_verdict`                 | `no_changes_verdict`                      |
| `pr_body`                            | `pr_body`                                 |
| `pr_exclude`                         | `loop_pr_exclude`                         |
| `pr_include_bots`                    | `loop_pr_include_bots`                    |
| `priority`                           | `loop_priority`                           |
| `agent_maker_instructions`           | `agent_maker_instructions`                |
| `pr_enabled`                         | `loop_pr_enabled`                         |
| `scoped_pr_number`                   | `loop_scoped_pr_number`                   |
| `run_log_file`                       | `run_log_file`                            |
| `agent_maker_skill_name`             | `agent_maker_skill_name`                  |
| `agent_checker_skill_name`           | `agent_checker_skill_name` (execute only) |
| `state_file`                         | `state_file`                              |
| _(via `secrets.GH_TOKEN` + resolve)_ | `github_token` (action; resolved in-job)  |
| `write_target`                       | `write_target`                            |

Domain-specific detect script variables use `detect_domain_env_json` keys (not `loop-detect` inputs).

## Prompt inputs (caller-facing)

Thin `on-loop-*.yaml` callers configure prompts with **two multiline strings** on `ci-loop-caller.yaml`:

| Input                        | Role                                            | Assembled by                                                                                    |
| ---------------------------- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `agent_maker_instructions`   | Domain maker task                               | `loop-detect` → `build_prompt_text` → `matrix.target.prompt` → `ci-loop-agent` `prompt_text`    |
| `agent_checker_instructions` | Domain APPROVE/REJECT rubric                    | Passed through to `loop-execute` `## Task` section                                              |
| `agent_checker_skill_name`   | Generic checker skill (default `loop-verifier`) | `loop-execute` slash-loads skill; INITIAL/REGRESSION scaffolding is **not** caller-configurable |

Do **not** configure `prompt_verifier_*`, `prompt_implementer_feedback`, or `prompt_file` on callers — those are `loop-execute` internals (not exposed on `ci-loop-agent`).

## Execute-only inputs

Passed through `ci-loop-caller` to `ci-loop-agent.yaml` when non-empty. Per-loop dogfood values: [CI Sweeper Workflow Design — Execute-only inputs](loop-ci-sweeper-workflow-design.md#execute-only-inputs).

| Input                       | Description                                        |
| --------------------------- | -------------------------------------------------- |
| `additional_commit_paths`   | Extra paths included in finalize commit            |
| `domain_persistence_script` | Bash script for `loop-finalize` domain persistence |

## Detect permissions

See [Loop Caller Reusable Workflow Design — Detect permissions](../loop-caller-reusable-design.md#detect-permissions). Branch/PR thin callers `uses:` **`ci-loop-caller.yaml`**; entity-event callers `uses:` **`ci-loop-caller-entity.yaml`**.

| Job / scope                      | Permissions                                               |
| -------------------------------- | --------------------------------------------------------- |
| `ci-loop-caller` `detect`        | `actions: write`, `contents: read`, `pull-requests: read` |
| `ci-loop-caller-entity` `detect` | `actions: write`, `contents: read`, `issues: read`        |
| Thin caller workflow             | execute baseline + `actions: write`                       |

Loop behavior (git-only vs `pr_enabled` vs `gh run list`) is selected by caller `with:` (`detect_script`, `pr_enabled`, `detect_domain_env_json`) — not by choosing a different reusable workflow file.

## Entity caller (`ci-loop-caller-entity.yaml`)

Binds one GitHub entity event (Issue / PR) via `loop-entity-detect` instead of scanning branches, then reuses `ci-loop-agent.yaml` for execute and finalize. Used by `on-loop-github-issue-triage.yaml`.

### Inputs it does not accept

Branch-watch and PR-scan inputs have no meaning when detect is bound to a single entity:

`ack_trigger_comment`, `additional_commit_paths`, `branch_match`, `branch_match_mode`, `domain_persistence_script`, `git_landing_integration`, `git_landing_pull_request`, `max_targets_per_schedule`, `pr_enabled`, `pr_exclude`, `pr_include_bots`, `priority`, `scoped_pr_number`

### Inputs only it accepts

| Input                  | Type   | Description                                                                                                    | Default |
| ---------------------- | ------ | -------------------------------------------------------------------------------------------------------------- | ------- |
| `dispatch_hook_script` | string | Trusted post-detect hook run by `loop-entity-detect` (e.g. fire `repository_dispatch` to hand off to autofix). | `""`    |
| `dispatch_hook_token`  | string | Token for the dispatch hook. Empty falls back to the detect job's resolved token.                              | `""`    |

### Defaults that differ

The entity caller targets read-only L1 triage, so several inputs are optional here and default to the report-mode values:

| Input                | `ci-loop-caller` | `ci-loop-caller-entity` |
| -------------------- | ---------------- | ----------------------- |
| `allowlist`          | required         | `""`                    |
| `delivery`           | `open_pr`        | `none`                  |
| `level`              | `L2`             | `L1`                    |
| `may_edit`           | required         | `false`                 |
| `no_changes_verdict` | `REJECT`         | `APPROVE`               |
| `write_target`       | required         | `report`                |

`no_changes_verdict` differs by design: a `write_target: fix` loop that produced no diff did not do its job (`REJECT`), while a `write_target: report` loop that edited nothing is behaving correctly (`APPROVE`).

## Domain detect environment (`detect_domain_env_json`)

JSON object string exported to the detect job environment before `loop-detect` runs. Keys use **detect-script env names** (for example `CHANGELOG_*`, `CI_SWEEPER_*`). Empty object `{}` when no domain env is required.

Each detect script normalizes these keys at startup via `configure_detect_environment` (defaults, `./` stripping). Detect CLI stays `--scope` / `--since` only so `loop-detect` can invoke every domain script uniformly.

`GH_TOKEN` is **not** passed via `detect_domain_env_json` — pass optional `secrets.GH_TOKEN` on the reusable; each job resolves App → `GH_TOKEN` → job `GITHUB_TOKEN` via `loop-resolve-push-token`.

**Per-loop keys and dogfood values** are documented under `### Domain detect environment` in each workflow design doc (not duplicated here).

| Loop                 | Domain env section                                                                                                                         |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| changelog            | [Changelog — Domain detect environment](loop-changelog-workflow-design.md#domain-detect-environment-detect_domain_env_json)                |
| ci-sweeper           | [CI Sweeper — Domain detect environment](loop-ci-sweeper-workflow-design.md#domain-detect-environment-detect_domain_env_json)              |
| docs-updater         | [Docs Updater — Domain detect environment](loop-docs-updater-workflow-design.md#domain-detect-environment-detect_domain_env_json)          |
| refactor             | [Refactor — Domain detect environment](loop-refactor-workflow-design.md#domain-detect-environment-detect_domain_env_json)                  |
| tech-debt            | [Report Tech Debt — Domain detect environment](loop-tech-debt-workflow-design.md#domain-detect-environment-detect_domain_env_json)         |
| github-issue-triage  | [Issue Triage — Domain detect environment](loop-github-issue-triage-workflow-design.md#domain-detect-environment-detect_domain_env_json)   |
| github-issue-autofix | [Issue Autofix — Domain detect environment](loop-github-issue-autofix-workflow-design.md#domain-detect-environment-detect_domain_env_json) |
| github-pr-revise     | [PR Revise — Domain detect environment](loop-github-pr-revise-workflow-design.md#domain-detect-environment-detect_domain_env_json)         |

## Legacy `env` name mapping

| Legacy caller `env`                                                                             | `ci-loop-caller` input                                                  |
| ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `AGENT_*`, `DEFAULT_ENGINE`, `DEFAULT_LEVEL`, `AGENT_MAKER_SKILL_NAME`                          | Same name (lowercase `engine`, `level` for engine/level)                |
| `DEFAULT_BASE_BRANCH`, `LOOP_STATE_PUSH_BRANCH`                                                 | `branch_state`                                                          |
| `LOOP_ALLOWLIST`                                                                                | `allowlist`                                                             |
| `LOOP_BUDGET_MAX_RUNS_PER_DAY`                                                                  | `budget_max_runs_per_day`                                               |
| `LOOP_BUDGET_MAX_TOKENS_PER_DAY`                                                                | `budget_max_tokens_per_day`                                             |
| `LOOP_DENYLIST`                                                                                 | `denylist`                                                              |
| `LOOP_DETECT_SCRIPT`                                                                            | `detect_script`                                                         |
| `LOOP_INFER_FILES_PATTERN`                                                                      | `infer_files_pattern`                                                   |
| `LOOP_INTEGRATION_BRANCHES`                                                                     | `branch_match`                                                          |
| `LOOP_BRANCH_MATCH`                                                                             | `branch_match_mode`                                                     |
| `LOOP_MAX_TARGETS_PER_SCHEDULE`                                                                 | `max_targets_per_schedule`                                              |
| `LOOP_NAME`                                                                                     | `loop_name`                                                             |
| `LOOP_NO_CHANGES_VERDICT`                                                                       | `no_changes_verdict`                                                    |
| `LOOP_PR_*`, `LOOP_PROMPT_INSTRUCTIONS`, `LOOP_IMPLEMENTER_INSTRUCTIONS`, `LOOP_PULL_REQUESTS`  | `pr_*`, `agent_maker_instructions`, `pr_enabled`                        |
| `prompt_instructions` (deprecated workflow input)                                               | `agent_maker_instructions`                                              |
| `skill_name` (deprecated workflow input)                                                        | `agent_maker_skill_name`                                                |
| `verifier_skill_name` (deprecated workflow input)                                               | `agent_checker_skill_name`                                              |
| `CHANGELOG_*`, `CI_SWEEPER_*`, `DOCS_UPDATER_*`, `TECH_DEBT_*`, `REFACTOR_*`, `PR_*`, `ISSUE_*` | `detect_domain_env_json` keys (per-loop tables in workflow design docs) |
| `DOMAIN_PERSISTENCE_SCRIPT`                                                                     | `domain_persistence_script`                                             |

## Per-loop design docs

| Loop                 | Design doc                                                                    | Caller workflow                                    |
| -------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------- |
| changelog            | [Changelog Workflow Design](loop-changelog-workflow-design.md)                | `on-loop-changelog.yaml`                           |
| ci-sweeper           | [CI Sweeper Workflow Design](loop-ci-sweeper-workflow-design.md)              | `on-loop-ci-sweeper.yaml`                          |
| docs-updater         | [Docs Updater Workflow Design](loop-docs-updater-workflow-design.md)          | `on-loop-docs-updater.yaml`                        |
| refactor             | [Refactor Workflow Design](loop-refactor-workflow-design.md)                  | `on-loop-refactor.yaml`                            |
| tech-debt            | [Report Tech Debt Workflow Design](loop-tech-debt-workflow-design.md)         | `on-loop-tech-debt.yaml`                           |
| github-issue-triage  | [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md)   | `on-loop-github-issue-triage.yaml` (entity caller) |
| github-issue-autofix | [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md) | `on-loop-github-issue-autofix.yaml`                |
| github-pr-revise     | [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md)         | `on-loop-github-pr-revise.yaml`                    |

## References

- [Loop Caller Reusable Workflow Design](../loop-caller-reusable-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
