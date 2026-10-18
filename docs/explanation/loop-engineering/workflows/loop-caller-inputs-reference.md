# Loop Caller Inputs Reference

`workflow_call` inputs for the two loop caller reusable workflows, passed from thin `on-loop-*.yaml` callers via `with:`.

| Reusable workflow            | Detect action        | Callers                                                                                                                             |
| ---------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `ci-loop-caller.yaml`        | `loop-detect`        | Branch / PR-head loops (changelog, ci-sweeper, docs-updater, refactor, tech-debt, test-gap, github-issue-autofix, github-pr-revise) |
| `ci-loop-caller-entity.yaml` | `loop-entity-detect` | Entity-event loops bound to one Issue / PR (github-issue-triage)                                                                    |

Both share `ci-loop-agent.yaml` for execute and finalize. Inputs below apply to `ci-loop-caller.yaml`; the [entity caller](#entity-caller-ci-loop-caller-entityyaml) section lists how `ci-loop-caller-entity.yaml` differs.

**Status:** Implemented. Callers pass configuration via `with:` on `ci-loop-caller.yaml`.

| Layer                              | Document                                                                                               |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Reusable workflow design           | [Loop Caller Reusable Workflow Design](../loop-caller-reusable-design.md)                              |
| Job graph and invariants           | [Loop Caller Workflows Design](../loop-caller-workflows-design.md)                                     |
| Platform branch/finalize semantics | [Multi-Branch Loops — canonical table](../multi-branch-loops-design.md#caller-configuration-canonical) |
| Per-loop behavior                  | [Workflow design docs](#per-loop-design-docs)                                                          |

Keys in `ci-loop-caller.yaml` `inputs` and caller `with:` blocks are **alphabetically ordered** (repository workflow convention).

**Naming rule:** input names are snake_case with the domain first and the attribute last. A prefix names the domain: `agent_` (maker and checker), `detect_` (what detect watches), `finalize_` (landing and post-processing), `pr_` (the PR that finalize creates), `state_` (`.loop/` persistence), `trigger_` (the event that started the run), plus the existing `budget_` and `run_log_`. Only `delivery`, `level`, `loop_name`, and `environment` have no prefix. The same name carries one value through caller inputs, `ci-loop-agent.yaml`, action inputs, prompt keys, and (uppercased) environment variables. Design: [Loop Delivery Plan Design](../../../superpowers/specs/2026-10-17-loop-delivery-plan-design.md).

## How inputs flow

```text
on-loop-*.yaml (with:)
  → ci-loop-caller.yaml
      detect      → loop-detect (+ detect_env_json export)
      ack-trigger → gh api reactions (only when trigger_comment_ack)
      execute     → ci-loop-agent.yaml (matrix)
      record-skip → loop-run-log

on-loop-*.yaml (with:)            # entity-event loops
  → ci-loop-caller-entity.yaml
      detect      → loop-entity-detect
      execute     → ci-loop-agent.yaml (matrix)
      record-skip → loop-run-log
```

## Credentials (via `secrets:`)

Per [GitHub reusable workflow docs](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-inputs-and-secrets-in-a-reusable-workflow), credentials use the **`secrets:`** keyword — not `with:`. Do **not** use `secrets: inherit` (locks callee secret names to the caller's names).

| Secret (callee)       | Required | Role                                                                                |
| --------------------- | -------- | ----------------------------------------------------------------------------------- |
| `AGENT_TOKEN`         | yes      | Engine API key. Mapped internally per `agent_engine` input.                         |
| `BOT_APP_CLIENT_ID`   | no       | GitHub App client ID for ruleset-bypass / elevated API (preferred when configured). |
| `BOT_APP_PRIVATE_KEY` | no       | GitHub App private key paired with `BOT_APP_CLIENT_ID`.                             |
| `GH_TOKEN`            | no       | Optional explicit token override. Empty → job `GITHUB_TOKEN` after App attempt.     |

Token minting is **per job** via `loop-resolve-push-token` (same-job step output only), and only in the detect, record-skip, and finalize jobs: the agent jobs use the read-only `github.token` and never see `BOT_APP_*` or `GH_TOKEN`. Do not pass resolved tokens across jobs via `needs.*.outputs`. Design rationale: [GitHub token resolution](../loop-caller-reusable-design.md#github-token-resolution). Do not declare `workflow_call` secret `GITHUB_TOKEN` / `github_token` (reserved names).

Callers remap local names explicitly. Optional `with: environment:` lets reusable jobs bind an environment for environment-scoped secrets named like the callee expects (`BOT_APP_*`). Callers cannot set `environment:` on a job that `uses:` a reusable.

When App credentials live only in that environment, every job that mints a token (`detect`, `finalize`, `record-skip`; the agent jobs use the read-only `github.token`) must set `environment:` so `BOT_APP_*` resolve. Without it, mint is skipped and attribution falls back to `github-actions[bot]`. Remapping `MAINTENANCE_BOT_*` from the caller job cannot read environment-scoped values.

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

| Role         | Question it answers                                       | `ci-loop-caller` inputs                                                                    | Dogfood (typical)                                                                |
| ------------ | --------------------------------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| **Watch**    | Which branches / PR heads does detect scan?               | `detect_branch_match`, `detect_branch_match_mode`, `detect_pr_enabled`, `detect_pr_number` | `main`, `glob`, `false` (ci-sweeper: `true`; pr-revise: `true` plus a PR number) |
| **State**    | Where do `.loop/*` commits (state, budget, run-log) land? | `state_branch`, `state_file`                                                               | `main`, (default path)                                                           |
| **Autonomy** | Human review vs GitHub auto-merge on the **bot fix PR**   | `level`                                                                                    | `L2`                                                                             |

Platform semantics (target model, checker baseline): [Multi-Branch Loops Design](../multi-branch-loops-design.md#branch-roles-and-fix-direction).

### Scope: `detect_pr_number`

Optional. When set, `loop-detect` fetches that open PR via `gh pr view` (does not list up to 50 PRs), drops integration watch targets, and keeps only that PR. Empty or `0` = unset. With `delivery: pr_push`, an unset value makes detect skip with `skip_reason` `pr_number_missing`; run-log records `skipped`. Dogfood: [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md#domain-detect-environment-detect_env_json).

### Watch: `detect_branch_match` + `detect_branch_match_mode`

`loop-detect` resolves `detect_branch_match` into concrete branch names using `detect_branch_match_mode`:

| `detect_branch_match_mode` | `detect_branch_match` meaning        | Example                                                      |
| -------------------------- | ------------------------------------ | ------------------------------------------------------------ |
| `list`                     | Exact branch names (comma-separated) | `main,develop` → scan those two only                         |
| `glob` (default)           | Patterns matched against `origin/*`  | `main` → `main`; `release/*` → all matching release branches |
| `regex`                    | Extended regex per pattern           | `^release/.*`                                                |

When `detect_branch_match` is **empty**, detect watches **no integration branch**; there is no fallback to `state_branch`. A branch caller needs `detect_branch_match`, `detect_pr_enabled: true`, or both; otherwise every run has zero targets.

`detect_pr_enabled: true` adds a second watch path: open PR **head** branches (see [Fix direction](#fix-direction-integration-vs-pull_request) below). Does not change where state is stored.

### State: `state_branch` + `state_file`

| Input          | Role                                                                                                                                                                                                                  |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `state_branch` | Branch for **all** `.loop/*` persistence commits — `state-<loop_name>.json`, budget file, run-log. Required. It stores state only and is not a watch target. Stays on `main` even when fixing `develop` or a PR head. |
| `state_file`   | Optional override for the state JSON path (default `.loop/state-<loop_name>.json`). Does not change which branch receives commits — only the file path.                                                               |

Dogfood sets `detect_branch_match: main` and `state_branch: main` (pr-revise sets `detect_pr_enabled: true` and `state_branch: main`). That matches the usual model: **watch `main` (and optionally other integration branches / PR heads); keep loop metadata on `main`.**

### Level × finalize matrix

`delivery` is required on every loop caller and has no default. It states where the agent output goes. The branch caller accepts these values:

| `delivery`      | Meaning                                                                                        | Usable targets                 | Dogfood                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------- |
| `pr_create`     | Create a new branch and PR (L3: enable auto-merge; draft via `pr_draft`)                       | `integration`, `pull_request`  | changelog, ci-sweeper, docs-updater, refactor, tech-debt, test-gap, github-issue-autofix |
| `pr_push`       | Merge the latest PR head, then push to the existing PR head branch; no new PR                  | `pull_request` only            | github-pr-revise (default; manual dispatch may pick `pr_create`)                         |
| `none`          | The platform delivers nothing                                                                  | all                            | —                                                                                        |
| `issue_comment` | Finalize posts one Issue comment from `message.md` and applies allowlisted labels (L1, L2, L3) | Issue entity (`kind == issue`) | github-issue-triage (L1)                                                                 |
| `pr_review`     | Finalize posts one `COMMENT` review from `review.json` (L2, L3)                                | PR entity (`kind == pr`)       | github-pr-review (L2)                                                                    |

`issue_create` is a reserved name. `lib/loop/delivery.sh` rejects it as not implemented. `log`, `issue`, `notion`, and `open_pr` are no longer accepted.

`loop-detect` and `loop-entity-detect` derive `pr_auto_merge` once (`level == L3` and `delivery == pr_create`) and export it next to `delivery`. `ci-loop-caller.yaml` passes both to `ci-loop-agent.yaml` unchanged; callers write no expression.

| Mode                         | L2                                    | L3                                                    |
| ---------------------------- | ------------------------------------- | ----------------------------------------------------- |
| `integration` (`pr_create`)  | Bot fix PR → `to.branch`; human merge | Bot fix PR → `to.branch`; **auto-merge**              |
| `pull_request` (`pr_create`) | Bot fix PR → PR head; notify human PR | Bot fix PR → PR head; **auto-merge**; notify human PR |
| `pull_request` (`pr_push`)   | Push to the PR head; no new PR        | Push to the PR head; no auto-merge                    |

L3 **auto-merge** is [GitHub PR auto-merge](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request) on the **bot fix PR** — not direct push to the branch. The human's open PR is not auto-merged.

`delivery: pr_push` has three extra rules, enforced in `lib/loop/delivery.sh`: it requires `detect_pr_enabled: true`, it rejects `detect_branch_match`, and it fails when an integration target appears. Without a PR number, detect skips with `pr_number_missing`.

`delivery: none` makes `loop-finalize` skip the push and PR creation, delete the agent branch after APPROVE, and deliver nothing. A `finalize_script` may still run. `loop-finalize` always runs at L2/L3; the former `finalize_enabled` flag is removed.

`delivery: issue_comment` and `delivery: pr_review` (entity loops such as [PR Review Workflow Design](loop-github-pr-review-workflow-design.md#finalize-with-delivery-pr_review) and [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md)) also skip the push and PR creation and delete the agent branch after delivery. Deliver Message in `loop-finalize` posts the message files once, with the loop marker, Meta and the footer. At L1 the agent writes `message.md` and `message_labels.json` to `LOOP_MESSAGE_DIR`, and the `message_json` job output carries them to `finalize-l1`. At L2/L3 `finalize_script` writes `message.md` or `review.json`. Validation rules:

- At L1, `delivery` is `none` or `issue_comment`, and `finalize_script` is rejected.
- At L2/L3, `issue_comment` and `pr_review` require `finalize_script`.
- `finalize_label_allowlist` is allowed only with `issue_comment` or `pr_review`.
- `loop-detect` (non-entity loops) rejects `issue_comment` and `pr_review`, because it emits only `integration` and `pull_request` targets.

`target_json` is required at every level including L1, because Deliver Message reads the Issue or PR number from `handoff_key`. An empty `target_json` fails `loop-finalize` Parse Target. External callers of `ci-loop-agent.yaml` at L1 must now pass it.

Direct push to an integration branch (the former `git_landing_integration: push`) and the `git_landing_*` inputs are removed. See [Finalize strategy matrix](../loop-engineering-design.md#finalize-strategy-matrix).

### Fix direction: integration vs `pull_request`

Detect builds one `target_json` per watch context. **Execute** checks out `from.branch` / `from.ref`. **Finalize** opens a bot fix PR (`pr_create`) or pushes to the PR head (`pr_push`) at `to.branch` (watched integration branch or PR head), not `state_branch`.

```text
integration mode (changelog, docs-updater, ci-sweeper on main)
  watch:  detect_branch_match → checkout main (or develop, release/*, …)
  worktree: from.branch == watched integration branch
  finalize: pr_create → bot fix PR to to.branch
  L2: human merges fix PR
  L3: auto-merge on fix PR
  state: state_branch (main) — separate from fix target

pull_request mode (ci-sweeper, detect_pr_enabled: true)
  watch:  open PR head branch (e.g. hotfix/0001)
  worktree: from.branch == PR head
  finalize: pr_create → bot fix PR to to.branch (PR head, not main)
            (pr_push → push directly to the PR head, no fix PR)
  loop-notify-pr: comment on human PR with fix PR link + summary
  L2: human merges bot fix PR into head branch; then merges human PR
  L3: auto-merge bot fix PR into head branch
  checker diff baseline: base.branch (PR base, e.g. main)
  state: state_branch (main) — separate from fix target
```

| Mode           | Watched branch            | Bot fix PR targets | Human PR notify |
| -------------- | ------------------------- | ------------------ | --------------- |
| `integration`  | `integration:main` (etc.) | `to.branch`        | No              |
| `pull_request` | PR head (`feature/…`)     | PR head branch     | Yes             |

**Summary:** monitored branches and PR heads are **watch targets**; `state_branch` is **metadata only**; fixes and pushes always target the **branch that was watched** (`to.branch`), not `main`, unless `main` itself is the watch target.

### Branch-related inputs (complete)

| Input                      | Type    | Role                                                                 | Default                               | Maps to `loop-detect`      |
| -------------------------- | ------- | -------------------------------------------------------------------- | ------------------------------------- | -------------------------- |
| `detect_branch_match`      | string  | Comma-separated patterns / names to watch                            | `""` (no integration watch)           | `detect_branch_match`      |
| `detect_branch_match_mode` | string  | How to interpret `detect_branch_match` patterns                      | `glob`                                | `detect_branch_match_mode` |
| `detect_pr_enabled`        | boolean | Watch open PR heads                                                  | `false`                               | `detect_pr_enabled`        |
| `detect_pr_number`         | number  | Fetch only this PR; drops integration targets                        | unset (`0`)                           | `detect_pr_number`         |
| `detect_priority`          | string  | Order when both integration and PR candidates exist                  | `integration,pull_request`            | `detect_priority`          |
| `level`                    | string  | `L2` human merge on bot fix PR; `L3` GitHub auto-merge on bot fix PR | (required)                            | `level`                    |
| `state_branch`             | string  | `.loop/*` persistence only                                           | (required)                            | `state_branch`             |
| `state_file`               | string  | Override state JSON path                                             | `""` (`.loop/state-<loop_name>.json`) | `state_file`               |

Related but not branch-scoped: `detect_max_targets` (fan-out cap after watch), `detect_pr_denylist` / `detect_pr_bot_allowlist` (PR watch filters).

## Agent and engine

| Input                        | Type   | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Default (dogfood)      |
| ---------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| `agent_maker_max_turns`      | number | Max maker agent turns per loop attempt                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `100` (all loops)      |
| `agent_maker_model`          | string | Maker model ID. Empty = engine default                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `claude-sonnet-5`      |
| `agent_maker_effort`         | string | Maker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `medium`               |
| `agent_loop_max_attempts`    | number | Max Agent→Verify retry cycles before finalize records failure                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | `3`                    |
| `agent_checker_instructions` | string | Caller-owned markdown rubric (`## Criteria for APPROVE` / `REJECT`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Domain-specific        |
| `agent_checker_max_turns`    | number | Max checker agent turns per verification                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | `100` (all loops)      |
| `agent_checker_model`        | string | Checker model ID                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | `claude-opus-5`        |
| `agent_checker_path_pattern` | string | Extended regex that picks file paths out of checker text                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Per loop               |
| `agent_checker_effort`       | string | Checker reasoning effort. Only engines with an effort flag (claude) consume it                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | `medium`               |
| `agent_engine`               | string | AI engine: `claude` \| `copilot` \| `codex` \| `cursor`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `claude` (required)    |
| `level`                      | string | Autonomy: `L1` \| `L2` \| `L3`. Required, no default                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Per loop               |
| `agent_maker_skill_name`     | string | Maker skill (e.g. `changelog`). Must match `.agents/skills/<name>/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Per loop               |
| `agent_checker_skill_name`   | string | Checker skill slash-loaded by `loop-execute` (not the maker)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `loop-verifier`        |
| `agent_tool_allowlist`       | string | Newline-separated permission rules the skill needs, in the engine's own syntax (claude: `Bash(gh issue view:*)`). Added after a fixed read-only git baseline (`git diff`, `git log`, `git show`, `git status`); the host repository's `.claude/settings.json` allow rules are not applied in CI. MCP tool calls, `WebFetch`, and `WebSearch` are no longer granted from the host settings — add them here (`mcp__<server>`, `WebFetch`) when a skill needs them. Only `claude` applies these rules — other engines warn and ignore them (see [Engine permission surfaces](#engine-permission-surfaces)) | Per loop (often empty) |

### Engine permission surfaces

Permission rule syntax does not translate between engines, so `loop-execute` never mistranslates `agent_tool_allowlist`. What each engine actually enforces differs:

| Engine    | Host repository config applied                                                                                                                                             | Blanket flag passed                                           |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `claude`  | `.claude/settings.json` `deny` / `ask` only (its `allow` stays inactive without workspace trust), plus the fixed baseline, the fixed deny list, and `agent_tool_allowlist` | `--permission-mode acceptEdits` (maker) / `dontAsk` (checker) |
| `cursor`  | `.cursor/cli.json` deny rules; `--force` short-circuits its allow rules                                                                                                    | `--trust`, `--force`                                          |
| `copilot` | none                                                                                                                                                                       | `--allow-all-tools`                                           |
| `codex`   | none — the CLI has no per-tool allowlist                                                                                                                                   | `--auto-approve`                                              |

`claude` does not get workspace trust from `loop-execute`, so `permissions.allow` and `additionalDirectories` from the host `.claude/settings.json` are not used and Claude Code prints a "this workspace has not been trusted" warning on stderr. The host's `deny` and `ask` rules, hooks, `env`, and `.mcp.json` still apply, and a skill's `allowed-tools` takes effect regardless of trust ([Claude Code skills documentation](https://code.claude.com/docs/en/skills)). What a session may run comes from the role's permission mode, the fixed read-only git baseline, `agent_tool_allowlist`, and a fixed deny list: GitHub writes (`gh issue`/`gh pr`/`gh release`/`gh label` mutations and `gh api` with a write method), `git push`, `curl` and `wget`, `printenv`, `sudo`, and `git diff --output`. The deny list is a guard against mistakes, not the enforcement boundary; the boundary is the agent job's read-only token. The other engines are unchanged.

### How agent configuration reaches execute

Caller inputs that `loop-detect` only echoed now go straight to `ci-loop-agent`. The detect job still owns the values it resolves or computes — `delivery`, `handoff_artifact_name`, `pr_auto_merge`, `run_started_at`, `should_run`, `skip_reason`, `state_file`, `target_matrix` — and nothing else passes through it.

| Value                                                                                                                                                                                                   | Path                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `agent_*`, `environment`, `finalize_commit_paths`, `finalize_script`, `finalize_outcome_override`, `level`, `loop_name`, `pr_body`, `pr_draft`, `pr_labels`, `pr_title`, `run_log_file`, `state_branch` | caller input → `ci-loop-agent`                                                                                                                                                                                                                                                                                                                                                                                |
| `delivery`, `handoff_artifact_name`, `pr_auto_merge`, `run_started_at`, `should_run`, `skip_reason`, `state_file`, `target_matrix`                                                                      | detect job → `needs.detect.outputs.*` → `ci-loop-agent`. `delivery` and `state_file` enter as caller inputs and come back resolved; `pr_auto_merge` is derived once from `level` and `delivery`; `handoff_artifact_name`, `should_run`, `skip_reason` and `target_matrix` are produced by the detect script; `run_started_at` comes from the detect job's own `Record Run Start` step, not from `loop-detect` |

A domain detect script can change only the second group. It cannot alter the model, effort, turn caps, skill names, or permission rules for the run.

## Platform inputs

Canonical branch/finalize/PR semantics: [Multi-Branch canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Input                       | Type    | Description                                                                                                                                                                                                                                                                                                                                                                                                                         | Default (dogfood)                                            |
| --------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `agent_edit_allowlist`      | string  | Comma-separated globs the maker may edit. Required at L2/L3 (empty is rejected; write `**` for unrestricted); must be empty at L1                                                                                                                                                                                                                                                                                                   | Per loop (`**` in the GitHub loops)                          |
| `agent_edit_denylist`       | string  | Comma-separated globs the maker must not touch. Optional at L2/L3; must be empty at L1. Empty applies the platform default (`DEFAULT_EXECUTE_DENYLIST` in `lib/loop/edit_paths.sh`: `**/.env,**/credentials*,**/secrets*`), so every loop keeps a secret-file guard. A value replaces that default rather than merging with it, so repeat the secret globs when adding repository paths                                             | Empty (platform default); tech-debt adds `src/**,.github/**` |
| `agent_edit_target`         | string  | Maker artifact: `fix` \| `report`. Required at L2/L3; must be empty at L1. Not derived from `delivery` (tech-debt uses `pr_create` with `report`)                                                                                                                                                                                                                                                                                   | Per loop (`fix` except tech-debt, pr-review `report`)        |
| `agent_unchanged_verdict`   | string  | `APPROVE` \| `REJECT` when the maker produces no file diff. Required at L2/L3; must be empty at L1. Applies in both places that observe an empty result: `loop.sh` after the maker, and the checker when the branch diff against the base is empty. Set `APPROVE` only for a loop whose success state is "no edit"                                                                                                                  | Per loop (`REJECT` in the dogfood L2 loops)                  |
| `budget_max_runs_per_day`   | number  | Daily run cap keyed by `loop_name` (each matrix cell counts). `.loop/loop-budget.json` overrides when present (ci-sweeper budget file: `50`)                                                                                                                                                                                                                                                                                        | `1`–`20` (caller; budget file may be higher)                 |
| `budget_max_tokens_per_day` | number  | Daily aggregated token cap                                                                                                                                                                                                                                                                                                                                                                                                          | `1000000` (all loops)                                        |
| `delivery`                  | string  | Required, no default. Where the agent output goes: `none` \| `pr_create` \| `pr_push` \| `issue_comment` \| `pr_review` (not passed to skills). Drives push, PR creation, state mode, and outcome in `loop-finalize`. See [Level × finalize matrix](#level--finalize-matrix)                                                                                                                                                        | Per loop                                                     |
| `detect_branch_match`       | string  | Comma-separated integration branch patterns to watch. Empty = no integration watch; rejected with `pr_push`                                                                                                                                                                                                                                                                                                                         | `main` (pr-revise: unset)                                    |
| `detect_branch_match_mode`  | string  | How to interpret `detect_branch_match`: `list`, `glob`, or `regex`                                                                                                                                                                                                                                                                                                                                                                  | `glob`                                                       |
| `detect_env_json`           | string  | JSON object of domain detect-script environment variables (see [Domain detect environment](#domain-detect-environment-detect_env_json))                                                                                                                                                                                                                                                                                             | `{}`                                                         |
| `detect_max_targets`        | number  | Max targets per cron tick after priority filters                                                                                                                                                                                                                                                                                                                                                                                    | `3`                                                          |
| `detect_pr_bot_allowlist`   | string  | Comma-separated bot logins to include when scanning PRs. Empty = exclude all bots. The bot-author heuristic is a scanning filter only: when `detect_pr_number` names a PR, author provenance never excludes it, while `detect_pr_denylist` tokens (`fork`, `draft`, `wip_title`, `label:*`) still apply                                                                                                                             | `""`                                                         |
| `detect_pr_denylist`        | string  | PR exclusion tokens: `fork`, `draft`, `label:<name>`, `wip_title`                                                                                                                                                                                                                                                                                                                                                                   | `fork,draft,label:no-loop` (pr-revise: `fork,label:no-loop`) |
| `detect_pr_enabled`         | boolean | Watch open PR heads for detect. Required `true` with `pr_push`                                                                                                                                                                                                                                                                                                                                                                      | `false` except ci-sweeper and pr-revise                      |
| `detect_pr_number`          | number  | Watch only this open PR; `0` = unset. With `pr_push`, unset skips with `pr_number_missing`                                                                                                                                                                                                                                                                                                                                          | pr-revise: from the event / dispatch                         |
| `detect_priority`           | string  | Target mode priority order (comma-separated)                                                                                                                                                                                                                                                                                                                                                                                        | `integration,pull_request`                                   |
| `detect_script`             | string  | Path to domain `detect_*.sh` under the skill package (e.g. `.agents/skills/docs-updater/scripts/detect_changes.sh`)                                                                                                                                                                                                                                                                                                                 | Per loop                                                     |
| `environment`               | string  | GitHub environment bound by every reusable job that mints a token, so environment-scoped `BOT_APP_*` resolve (see [Credentials](#credentials-via-secrets))                                                                                                                                                                                                                                                                          | `default`                                                    |
| `finalize_commit_paths`     | string  | Extra paths that `loop-finalize` may add to its commit; an allowlist for the files `finalize_script` writes                                                                                                                                                                                                                                                                                                                         | `""`                                                         |
| `finalize_script`           | string  | Bash script that `loop-finalize` runs once at L2/L3 regardless of `delivery` (for example a ledger or `render_review.sh`). It may update files under the repository root and write message files to `LOOP_MESSAGE_DIR`; it receives `GH_TOKEN` (read-only use), `GITHUB_REPOSITORY` and `LOOP_MESSAGE_DIR`, no Meta block, and not `detect_env_json` values. Required with `issue_comment` and `pr_review` at L2/L3, rejected at L1 | `""`                                                         |
| `finalize_label_allowlist`  | string  | Newline-separated labels that Deliver Message may add or remove from `message_labels.json`. Allowed only with `delivery: issue_comment` or `pr_review`; empty ignores `labels` with a warning, and labels outside the list are skipped with a warning                                                                                                                                                                               | `""` (triage: its eight triage labels)                       |
| `finalize_outcome_override` | string  | Explicit finalize outcome (for example `watch`)                                                                                                                                                                                                                                                                                                                                                                                     | `""`                                                         |
| `loop_name`                 | string  | Loop identifier: `.loop/state-<loop_name>.json`, budget key, run-log tag. Align caller filename: `on-loop-<loop_name>.yaml`                                                                                                                                                                                                                                                                                                         | Per loop                                                     |
| `pr_body`                   | string  | Optional static prefix (dogfood: unset). `loop-finalize` composes the PR body: agent `## Overview` + `## Summary`, mechanical `## Failure context` / `## Changes` / `## Run Metadata`, and automation disclaimer. See [Loop PR Body Readable Design](../../../superpowers/specs/2026-07-21-loop-pr-body-readable-design.md).                                                                                                        | `""`                                                         |
| `pr_draft`                  | boolean | Create the finalize PR as a draft when `delivery: pr_create`                                                                                                                                                                                                                                                                                                                                                                        | `false` (issue-autofix: dispatch input)                      |
| `pr_labels`                 | string  | Comma-separated labels for the created PR                                                                                                                                                                                                                                                                                                                                                                                           | `loop-automation`                                            |
| `pr_title`                  | string  | PR title when `delivery` is `pr_create`                                                                                                                                                                                                                                                                                                                                                                                             | Per loop                                                     |
| `state_branch`              | string  | Required. Branch for `.loop/*` persistence only; not a watch target                                                                                                                                                                                                                                                                                                                                                                 | `main`                                                       |
| `state_file`                | string  | Override state JSON path                                                                                                                                                                                                                                                                                                                                                                                                            | `.loop/state-<loop_name>.json`                               |
| `trigger_comment_ack`       | boolean | Run the `ack-trigger` job after detect proceeds: posts an `eyes` reaction on each gathered comment (fallback: the trigger comment). Comment webhooks only                                                                                                                                                                                                                                                                           | `false` (pr-revise: `true`)                                  |

The agent-prefixed inputs for the maker prompt and engine are in [Agent and engine](#agent-and-engine).

**Four-plane contract:** See [Loop write target & delivery design](../../../superpowers/specs/2026-07-23-loop-write-target-delivery-design.md) and [Loop Delivery Plan Design](../../../superpowers/specs/2026-10-17-loop-delivery-plan-design.md). `level` controls autonomy and whether the agent may edit (L1 never edits; the prompt key `agent_edit_allowed` is derived from it); `agent_edit_target`, `agent_edit_allowlist`, `agent_edit_denylist`, and `agent_unchanged_verdict` shape agent edits, and the prompt carries `agent_edit_target` and `agent_report_file`; `delivery` controls platform finalize (skills do not see `delivery`).

**Readable PR body:** Dogfood callers set `pr_body: ""`; narrative is agent-owned (`## Overview`, `## Summary` tables). See [Loop PR Body Skill Contract](../loop-pr-body-skill-contract.md).

### Optional file-path inputs (supported by `loop-detect`)

| Input          | Description                               | Default                  |
| -------------- | ----------------------------------------- | ------------------------ |
| `budget_file`  | Path to loop budget JSON                  | `.loop/loop-budget.json` |
| `run_log_file` | JSONL run log path for budget aggregation | `.loop/loop-run-log.md`  |

## `loop-detect` input mapping

`ci-loop-caller` inputs map to `loop-detect` action `with:` under the **same name**. The action takes only the inputs below; the other caller inputs go straight to `ci-loop-agent.yaml`.

| `ci-loop-caller` input               | `loop-detect` input                       |
| ------------------------------------ | ----------------------------------------- |
| `agent_checker_skill_name`           | `agent_checker_skill_name` (execute only) |
| `agent_edit_allowlist`               | `agent_edit_allowlist`                    |
| `agent_edit_denylist`                | `agent_edit_denylist`                     |
| `agent_edit_target`                  | `agent_edit_target`                       |
| `agent_maker_instructions`           | `agent_maker_instructions`                |
| `agent_maker_skill_name`             | `agent_maker_skill_name`                  |
| `agent_unchanged_verdict`            | `agent_unchanged_verdict`                 |
| `budget_file`                        | `budget_file`                             |
| `budget_max_runs_per_day`            | `budget_max_runs_per_day`                 |
| `budget_max_tokens_per_day`          | `budget_max_tokens_per_day`               |
| `delivery`                           | `delivery`                                |
| `detect_branch_match`                | `detect_branch_match`                     |
| `detect_branch_match_mode`           | `detect_branch_match_mode`                |
| `detect_max_targets`                 | `detect_max_targets`                      |
| `detect_pr_bot_allowlist`            | `detect_pr_bot_allowlist`                 |
| `detect_pr_denylist`                 | `detect_pr_denylist`                      |
| `detect_pr_enabled`                  | `detect_pr_enabled`                       |
| `detect_pr_number`                   | `detect_pr_number`                        |
| `detect_priority`                    | `detect_priority`                         |
| `detect_script`                      | `detect_script`                           |
| `level`                              | `level`                                   |
| `loop_name`                          | `loop_name`                               |
| `run_log_file`                       | `run_log_file`                            |
| `state_branch`                       | `state_branch`                            |
| `state_file`                         | `state_file`                              |
| _(via `secrets.GH_TOKEN` + resolve)_ | `github_token` (action; resolved in-job)  |

`agent_checker_skill_name` is also listed because the detect action records it for execute. The detect action validates the `level` / `delivery` / `agent_edit_*` / `agent_unchanged_verdict` combination.

Domain-specific detect script variables use `detect_env_json` keys (not `loop-detect` inputs). The state branch reaches the detect script as the environment variable `STATE_BRANCH`.

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

| Input                      | Description                              |
| -------------------------- | ---------------------------------------- |
| `finalize_commit_paths`    | Extra paths included in finalize commit  |
| `finalize_script`          | Bash script run once by `loop-finalize`  |
| `finalize_label_allowlist` | Labels Deliver Message may add or remove |

## Detect permissions

See [Loop Caller Reusable Workflow Design — Detect permissions](../loop-caller-reusable-design.md#detect-permissions). Branch/PR thin callers `uses:` **`ci-loop-caller.yaml`**; entity-event callers `uses:` **`ci-loop-caller-entity.yaml`**.

| Job / scope                      | Permissions                                               |
| -------------------------------- | --------------------------------------------------------- |
| `ci-loop-caller` `detect`        | `actions: write`, `contents: read`, `pull-requests: read` |
| `ci-loop-caller-entity` `detect` | `actions: write`, `contents: read`, `issues: read`        |
| Thin caller workflow             | execute baseline + `actions: write`                       |

Loop behavior (git-only vs `detect_pr_enabled` vs `gh run list`) is selected by caller `with:` (`detect_script`, `detect_pr_enabled`, `detect_env_json`) — not by choosing a different reusable workflow file.

## Entity caller (`ci-loop-caller-entity.yaml`)

Binds one GitHub entity event (Issue / PR) via `loop-entity-detect` instead of scanning branches, then reuses `ci-loop-agent.yaml` for execute and finalize. Used by `on-loop-github-issue-triage.yaml`.

### Inputs it does not accept

Branch-watch and PR-scan inputs have no meaning when detect is bound to a single entity:

`detect_branch_match`, `detect_branch_match_mode`, `detect_max_targets`, `detect_pr_bot_allowlist`, `detect_pr_denylist`, `detect_pr_enabled`, `detect_pr_number`, `detect_priority`, `trigger_comment_ack`

### Entity-specific behavior

The entity caller has no per-caller defaults for `delivery` or `level`; both are required, as on `ci-loop-caller`. The `agent_edit_*` and `agent_unchanged_verdict` inputs follow the same `level`-keyed rule: required at L2/L3, empty at L1.

| Loop                | `level` | `delivery`      | `agent_edit_*` / `agent_unchanged_verdict`                                                   |
| ------------------- | ------- | --------------- | -------------------------------------------------------------------------------------------- |
| github-issue-triage | `L1`    | `issue_comment` | none set                                                                                     |
| github-pr-review    | `L2`    | `pr_review`     | `agent_edit_allowlist: "**"`, `agent_edit_target: report`, `agent_unchanged_verdict: REJECT` |

An L1 loop that edited nothing is behaving correctly, so triage sets none of the edit inputs and L1 outcomes without a diff are `unchanged`.

## Domain detect environment (`detect_env_json`)

JSON object string exported to the detect job environment before `loop-detect` runs. Keys use **detect-script env names** (for example `CHANGELOG_*`, `CI_SWEEPER_*`). Empty object `{}` when no domain env is required.

Each detect script normalizes these keys at startup via `configure_detect_environment` (defaults, `./` stripping). Detect CLI stays `--scope` / `--since` only so `loop-detect` can invoke every domain script uniformly.

`GH_TOKEN` is **not** passed via `detect_env_json` — pass optional `secrets.GH_TOKEN` on the reusable; each job resolves App → `GH_TOKEN` → job `GITHUB_TOKEN` via `loop-resolve-push-token`.

**Per-loop keys and dogfood values** are documented under `### Domain detect environment` in each workflow design doc (not duplicated here).

| Loop                 | Domain env section                                                                                                                  |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| changelog            | [Changelog — Domain detect environment](loop-changelog-workflow-design.md#domain-detect-environment-detect_env_json)                |
| ci-sweeper           | [CI Sweeper — Domain detect environment](loop-ci-sweeper-workflow-design.md#domain-detect-environment-detect_env_json)              |
| docs-updater         | [Docs Updater — Domain detect environment](loop-docs-updater-workflow-design.md#domain-detect-environment-detect_env_json)          |
| refactor             | [Refactor — Domain detect environment](loop-refactor-workflow-design.md#domain-detect-environment-detect_env_json)                  |
| tech-debt            | [Report Tech Debt — Domain detect environment](loop-tech-debt-workflow-design.md#domain-detect-environment-detect_env_json)         |
| test-gap             | [Test Gap — Domain detect environment](loop-test-gap-workflow-design.md#domain-detect-environment-detect_env_json)                  |
| github-issue-triage  | [Issue Triage — Domain detect environment](loop-github-issue-triage-workflow-design.md#domain-detect-environment-detect_env_json)   |
| github-issue-autofix | [Issue Autofix — Domain detect environment](loop-github-issue-autofix-workflow-design.md#domain-detect-environment-detect_env_json) |
| github-pr-revise     | [PR Revise — Domain detect environment](loop-github-pr-revise-workflow-design.md#domain-detect-environment-detect_env_json)         |

## Legacy `env` name mapping

| Legacy caller `env`                                                                             | `ci-loop-caller` input                                           |
| ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `AGENT_*`, `DEFAULT_ENGINE`, `DEFAULT_LEVEL`, `AGENT_MAKER_SKILL_NAME`                          | `agent_*` (`agent_engine` for the engine, `level` for the level) |
| `DEFAULT_BASE_BRANCH`, `LOOP_STATE_PUSH_BRANCH`                                                 | `state_branch`                                                   |
| `LOOP_ALLOWLIST`                                                                                | `agent_edit_allowlist`                                           |
| `LOOP_BUDGET_MAX_RUNS_PER_DAY`                                                                  | `budget_max_runs_per_day`                                        |
| `LOOP_BUDGET_MAX_TOKENS_PER_DAY`                                                                | `budget_max_tokens_per_day`                                      |
| `LOOP_DENYLIST`                                                                                 | `agent_edit_denylist`                                            |
| `LOOP_DETECT_SCRIPT`                                                                            | `detect_script`                                                  |
| `LOOP_INFER_FILES_PATTERN`                                                                      | `agent_checker_path_pattern`                                     |
| `LOOP_INTEGRATION_BRANCHES`                                                                     | `detect_branch_match`                                            |
| `LOOP_BRANCH_MATCH`                                                                             | `detect_branch_match_mode`                                       |
| `LOOP_MAX_TARGETS_PER_SCHEDULE`                                                                 | `detect_max_targets`                                             |
| `LOOP_NAME`                                                                                     | `loop_name`                                                      |
| `LOOP_NO_CHANGES_VERDICT`                                                                       | `agent_unchanged_verdict`                                        |
| `LOOP_PR_*`, `LOOP_PROMPT_INSTRUCTIONS`, `LOOP_IMPLEMENTER_INSTRUCTIONS`, `LOOP_PULL_REQUESTS`  | `pr_*`, `agent_maker_instructions`, `detect_pr_enabled`          |
| `prompt_instructions` (deprecated workflow input)                                               | `agent_maker_instructions`                                       |
| `skill_name` (deprecated workflow input)                                                        | `agent_maker_skill_name`                                         |
| `verifier_skill_name` (deprecated workflow input)                                               | `agent_checker_skill_name`                                       |
| `CHANGELOG_*`, `CI_SWEEPER_*`, `DOCS_UPDATER_*`, `TECH_DEBT_*`, `REFACTOR_*`, `PR_*`, `ISSUE_*` | `detect_env_json` keys (per-loop tables in workflow design docs) |
| `DOMAIN_PERSISTENCE_SCRIPT`                                                                     | `finalize_script`                                                |

## Per-loop design docs

| Loop                 | Design doc                                                                    | Caller workflow                                    |
| -------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------- |
| changelog            | [Changelog Workflow Design](loop-changelog-workflow-design.md)                | `on-loop-changelog.yaml`                           |
| ci-sweeper           | [CI Sweeper Workflow Design](loop-ci-sweeper-workflow-design.md)              | `on-loop-ci-sweeper.yaml`                          |
| docs-updater         | [Docs Updater Workflow Design](loop-docs-updater-workflow-design.md)          | `on-loop-docs-updater.yaml`                        |
| refactor             | [Refactor Workflow Design](loop-refactor-workflow-design.md)                  | `on-loop-refactor.yaml`                            |
| tech-debt            | [Report Tech Debt Workflow Design](loop-tech-debt-workflow-design.md)         | `on-loop-tech-debt.yaml`                           |
| test-gap             | [Test Gap Workflow Design](loop-test-gap-workflow-design.md)                  | `on-loop-test-gap.yaml`                            |
| github-issue-triage  | [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md)   | `on-loop-github-issue-triage.yaml` (entity caller) |
| github-issue-autofix | [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md) | `on-loop-github-issue-autofix.yaml`                |
| github-pr-revise     | [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md)         | `on-loop-github-pr-revise.yaml`                    |
| github-pr-review     | [PR Review Workflow Design](loop-github-pr-review-workflow-design.md)         | `on-loop-github-pr-review.yaml` (entity caller)    |

## References

- [Loop Caller Reusable Workflow Design](../loop-caller-reusable-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Specification](../../../reference/specification.md)
