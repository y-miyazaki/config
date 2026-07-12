# Loop Caller `env` Reference

Shared environment variables for `.github/workflows/on-loop-*.yaml` caller workflows.

**Scope:** every key in caller workflow-level `env:` blocks. Domain-prefixed keys (`CHANGELOG_*`, `CI_SWEEPER_*`, `DOCS_TRIAGE_*`) are listed in workflow `env:` for alphabetical grouping and forwarded to detect scripts on the detect job step.

| Layer                                            | Document                                                                                               |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| Platform `LOOP_*` (branch modes, finalize, caps) | [Multi-Branch Loops — canonical table](../multi-branch-loops-design.md#caller-configuration-canonical) |
| Job graph, triggers, concurrency                 | [Loop Caller Workflows Design](../loop-caller-workflows-design.md)                                     |
| Per-loop behavior                                | [Workflow design docs](#per-loop-design-docs)                                                          |

Keys in caller `env:` blocks are **alphabetically ordered** (repository workflow convention).

## How `env` flows

```text
on-loop-*.yaml (env)
  → detect job: loop-detect (with: maps env → action inputs)
  → execute job: ci-loop-agent.yaml (outputs from detect)
```

Cron and `workflow_dispatch` runs have no `inputs` context — tunables live in `env:`, not `workflow_dispatch` inputs. See [GitHub Workflows Design — Defaults via env](../github-workflows-design.md#defaults-via-env).

## Secrets

| Secret         | Role                                                                                                                                                               |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `AGENT_TOKEN`  | Engine API key. Required for `workflow_call` and schedule runs. Mapped internally per `DEFAULT_ENGINE` (`claude` → `ANTHROPIC_API_KEY`, `cursor` → Cursor API, …). |
| `GITHUB_TOKEN` | Used as `GH_TOKEN_PUSH` for git push / PR creation where the reusable workflow accepts it.                                                                         |

## Agent and engine

| Variable                      | Description                                                                                                                                   | Default (dogfood)                  |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `AGENT_IMPLEMENTER_MAX_TURNS` | Max implementer agent turns **per loop attempt** (one Agent→Verify cycle).                                                                    | `5`–`8` (loop-specific)            |
| `AGENT_IMPLEMENTER_MODEL`     | Implementer model ID (engine-specific). Cursor: run `agent --list-models`. Empty = engine default.                                            | `grok-4.5-medium`                  |
| `AGENT_LOOP_MAX_ATTEMPTS`     | Max Agent→Verify retry cycles before finalize records failure.                                                                                | `3`                                |
| `AGENT_VERIFIER_CRITERIA`     | Caller-owned markdown rubric (`## Criteria for APPROVE` / `REJECT`). Passed verbatim to verifier.                                             | Domain-specific (in workflow YAML) |
| `AGENT_VERIFIER_MAX_TURNS`    | Max verifier agent turns per verification.                                                                                                    | `3`                                |
| `AGENT_VERIFIER_MODEL`        | Verifier model ID. Cursor: run `agent --list-models`.                                                                                         | `composer-2.5`                     |
| `DEFAULT_ENGINE`              | AI engine: `claude` \| `copilot` \| `codex` \| `cursor`. Selects CLI and `AGENT_TOKEN` mapping.                                               | `cursor`                           |
| `DEFAULT_LEVEL`               | Autonomy: `L1` (read-only once) \| `L2` (review PR) \| `L3` (auto-merge when `finalize=open_pr`). Single switch per loop — not split by mode. | `L2`                               |
| `SKILL_NAME`                  | Skill package to invoke (e.g. `loop-changelog`). Must match `.agents/skills/<name>/`.                                                         | Per loop                           |

## Repository and branch defaults

| Variable              | Description                                                                                                                                                         | Default (dogfood) |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| `DEFAULT_BASE_BRANCH` | Default branch for state migration and when `LOOP_INTEGRATION_BRANCHES` is empty. Not a substitute for `LOOP_INTEGRATION_BRANCHES` when scanning multiple branches. | `main`            |

## Loop platform (`LOOP_*`)

Canonical branch/finalize/PR keys: [Multi-Branch canonical table](../multi-branch-loops-design.md#caller-configuration-canonical).

| Variable                         | Description                                                                                                                                    | Default (dogfood)              |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `LOOP_ALLOWLIST`                 | Comma-separated globs the implementer may modify. Enforced in `loop-execute`.                                                                  | Per loop                       |
| `LOOP_BUDGET_MAX_RUNS_PER_DAY`   | Daily run cap keyed by `LOOP_NAME` (each matrix cell counts). Exceeded → `skip_reason=budget`.                                                 | `1`–`5`                        |
| `LOOP_BUDGET_MAX_TOKENS_PER_DAY` | Daily aggregated token cap across loops.                                                                                                       | `500000`–`1000000`             |
| `LOOP_DENYLIST`                  | Comma-separated globs the implementer must not touch (ci-sweeper).                                                                             | ci-sweeper only                |
| `LOOP_DETECT_SCRIPT`             | Path to domain `detect_*.sh` (under loop skill package). Invoked once per scan context by `loop-detect` — never re-run in caller `run:` steps. | Per loop                       |
| `LOOP_FINALIZE_INTEGRATION`      | Finalize for integration targets: `open_pr` \| `push` (L3 direct push).                                                                        | `open_pr`                      |
| `LOOP_FINALIZE_PULL_REQUEST`     | Finalize for PR head targets. Currently `push_head` only.                                                                                      | `push_head` (ci-sweeper)       |
| `LOOP_INFER_FILES_PATTERN`       | Extended regex to infer file paths from verifier text for allowlist checks.                                                                    | Per loop                       |
| `LOOP_INTEGRATION_BRANCHES`      | Comma-separated branch patterns to watch (`glob` unless `LOOP_BRANCH_MATCH` set). Empty with `LOOP_PULL_REQUESTS=false` → no work.             | `main`                         |
| `LOOP_MAX_TARGETS_PER_SCHEDULE`  | Max targets per cron tick after priority/`acting_on` filters. Excess deferred → `target_budget`.                                               | `3`                            |
| `LOOP_NAME`                      | Loop identifier: state file `.loop/state-<LOOP_NAME>.json`, budget key, run-log tag. Align workflow filename: `on-loop-<LOOP_NAME>.yaml`.      | Per loop                       |
| `LOOP_NO_CHANGES_VERDICT`        | `APPROVE` \| `REJECT` when implementer produces no file diff. CI loops use `REJECT` for actionable failures.                                   | `REJECT` (all dogfood callers) |
| `LOOP_PR_BODY`                   | Static markdown prefix for finalize PR body (loop attribution, review notice).                                                                 | Per loop                       |
| `LOOP_PR_EXCLUDE`                | PR exclusion tokens: `fork`, `draft`, `label:<name>`, `wip_title`.                                                                             | ci-sweeper                     |
| `LOOP_PR_INCLUDE_BOTS`           | Comma-separated bot logins to include when scanning PRs. Empty = exclude all bots.                                                             | `""`                           |
| `LOOP_PR_TITLE`                  | PR title template when finalize strategy is `open_pr`.                                                                                         | Per loop                       |
| `LOOP_PROMPT_INSTRUCTIONS`       | Domain-specific implementer instructions appended by `loop-prompt-generate`.                                                                   | Per loop                       |
| `LOOP_PULL_REQUESTS`             | `"true"` \| `"false"` — enumerate open PR heads for detect.                                                                                    | `"false"` except ci-sweeper    |
| `LOOP_STATE_PUSH_BRANCH`         | Branch for `.loop/*` persistence commits (state, budget, run-log). Fix PRs may target other branches; metadata stays here.                     | `main`                         |

Optional keys not set in current dogfood callers but supported by `loop-detect`:

| Variable            | Description                                                                                           | Default                        |
| ------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------ |
| `LOOP_BRANCH_MATCH` | Branch pattern mode: `list`, `glob`, or `regex`.                                                      | `glob`                         |
| `LOOP_PRIORITY`     | Target mode priority order (comma-separated). Overridden by trigger-aware priority on `workflow_run`. | `integration,pull_request`     |
| `budget_file`       | Path to loop budget JSON (per-loop keys override `LOOP_BUDGET_*`).                                    | `.loop/loop-budget.json`       |
| `state_file`        | Override state JSON path.                                                                             | `.loop/state-<LOOP_NAME>.json` |
| `run_log_file`      | JSONL run log path for budget aggregation.                                                            | `.loop/loop-run-log.md`        |

## Domain-prefixed `env` (per loop)

### Changelog (`loop-changelog`)

| Variable                  | Description                                                                        | Dogfood value  |
| ------------------------- | ---------------------------------------------------------------------------------- | -------------- |
| `CHANGELOG_FILE`          | Target changelog path. YAML anchor may reuse value in `LOOP_ALLOWLIST`.            | `CHANGELOG.md` |
| `CHANGELOG_MERGE_COMMITS` | `"true"` includes merge commits; `"false"` applies `--no-merges` in detect script. | `"false"`      |

### CI sweeper (`loop-ci-sweeper`)

| Variable                         | Description                                                                   | Dogfood value                                                            |
| -------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `CI_SWEEPER_EXCLUDED_WORKFLOWS`  | Workflow names to ignore (prevents self-trigger / recursion).                 | `on-loop-changelog,on-loop-ci-sweeper,on-loop-docs-triage,ci-loop-agent` |
| `CI_SWEEPER_INCLUDED_WORKFLOWS`  | Workflow name allowlist. Empty = all non-excluded.                            | `""`                                                                     |
| `CI_SWEEPER_LEDGER_FILE`         | JSON ledger for `workflow_run_id` dedupe.                                     | `.loop/ci-sweeper-run-ledger.json`                                       |
| `CI_SWEEPER_REJECT_MAX_RETRIES`  | Max retries per run ID when policy is `limited`.                              | `"3"`                                                                    |
| `CI_SWEEPER_REJECT_RETRY_POLICY` | `block`, `retry`, or `limited` for prior `rejected` ledger entries.           | `block`                                                                  |
| `DOMAIN_PERSISTENCE_SCRIPT`      | Bash script for `loop-finalize` `domain_persistence_script` (ledger updates). | `.agents/skills/loop-ci-sweeper/scripts/update_run_ledger.sh`            |

Event vars (detect job only when `workflow_run` trigger enabled):

| Variable                     | Description                                              |
| ---------------------------- | -------------------------------------------------------- |
| `CI_SWEEPER_HEAD_BRANCH`     | Failed run head branch from `github.event.workflow_run`. |
| `CI_SWEEPER_HEAD_SHA`        | Failed run head SHA.                                     |
| `CI_SWEEPER_WORKFLOW_RUN_ID` | Failed run ID for ledger dedupe.                         |
| `CI_SWEEPER_WORKFLOW_NAME`   | Failed workflow display name.                            |
| `CI_SWEEPER_RUN_URL`         | HTML URL of failed run (verifier context).               |

### Docs triage (`loop-docs-triage`)

| Variable                  | Description                                           | Dogfood value            |
| ------------------------- | ----------------------------------------------------- | ------------------------ |
| `DOCS_TRIAGE_DOC_GLOBS`   | Comma-separated doc file globs for git-diff analysis. | `docs/**/*.md,README.md` |
| `DOCS_TRIAGE_EXTRA_FILES` | Additional non-glob paths (e.g. `mkdocs.yml`).        | `mkdocs.yml`             |

## Per-loop complete tables

Each workflow design doc lists **every** `env` key for that caller (including multiline values referenced as inline in YAML):

| Loop        | All `env` keys documented                                                                                        |
| ----------- | ---------------------------------------------------------------------------------------------------------------- |
| changelog   | [Changelog Workflow Design — Environment variables](loop-changelog-workflow-design.md#environment-variables)     |
| ci-sweeper  | [CI Sweeper Workflow Design — Environment variables](loop-ci-sweeper-workflow-design.md#environment-variables)   |
| docs-triage | [Docs Triage Workflow Design — Environment variables](loop-docs-triage-workflow-design.md#environment-variables) |

## Per-loop design docs

| Loop        | Design doc                                                         | Caller workflow            |
| ----------- | ------------------------------------------------------------------ | -------------------------- |
| changelog   | [Changelog Workflow Design](loop-changelog-workflow-design.md)     | `on-loop-changelog.yaml`   |
| ci-sweeper  | [CI Sweeper Workflow Design](loop-ci-sweeper-workflow-design.md)   | `on-loop-ci-sweeper.yaml`  |
| docs-triage | [Docs Triage Workflow Design](loop-docs-triage-workflow-design.md) | `on-loop-docs-triage.yaml` |

## References

- [Multi-Branch Loops Design](../multi-branch-loops-design.md)
- [Loop Caller Workflows Design](../loop-caller-workflows-design.md)
- [Loop Engineering Design](../loop-engineering-design.md)
- [Specification](../../reference/specification.md)
