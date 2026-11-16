# CLAUDE.md

Behavioral rules for `.github/workflows/**` and `.github/actions/**`. This repository is a **distribution source** — consumers pin workflows and composites by commit SHA.

Design background: [GitHub Workflows Design](../../docs/explanation/github-workflows-design.md). Contracts: [Specification](../../docs/reference/specification.md).

---

## Docs sync (MUST)

Before changing code here, find the docs that describe it and update them in the same change (see Document sync in `AGENTS.md`).

| Changed code                                               | Docs to find and update                                                                                                                                                                                                                                          |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/*.yaml`                                 | Paths in the file's header `# References:`                                                                                                                                                                                                                       |
| `.github/actions/<name>/` (action.yml and its `lib/`)      | Paths in that `action.yml` header `# References:`                                                                                                                                                                                                                |
| `.github/actions/lib/loop/` (shared, no header of its own) | `docs/explanation/loop-engineering/loop-engineering-design.md`, `docs/explanation/loop-engineering/multi-branch-loops-design.md` (trusted ref, state snapshot) and the `References` of every `loop-*` action that sources it; rules: `.github/actions/CLAUDE.md` |

When a change alters what the header states (called-by workflows, design rules, dependencies, references), update the header in the same change.

---

## Pins

| Rule                                         | Requirement                                                                                                                                          |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Config components                            | **MUST** use a full commit SHA (`uses: org/repo/.github/...@<sha> # vX.Y.Z`). Tags and branches are forbidden.                                       |
| Third-party actions                          | **MUST** pin by full SHA; annotate upstream version in a comment when known.                                                                         |
| Consumer copies (`example/`, external repos) | **MUST** use remote SHA pins only.                                                                                                                   |
| Reusable workflows (`ci-*`, `cd-*`)          | **MUST NOT** use `uses: ./.github/actions/...` or `uses: ./.github/workflows/...`. Consumers fetch reusables remotely; local paths are not portable. |
| Dogfood (`on-*` workflow steps)              | **MAY** use `./.github/workflows/...` or `./.github/actions/...` while iterating unreleased graph changes — **not** in `ci-*` / `cd-*`.              |
| Composite internals                          | **MUST NOT** use `uses: ./.github/actions/...` — unresolvable in consumer repositories.                                                              |
| Release                                      | **MUST** bump SHA pins in `ci-*`, `cd-*`, and `example/` in the same change set as new action/workflow releases (or per release checklist).          |

---

## Header format

Every `.github/workflows/*.yaml`, `example/*.yaml`, and `.github/actions/*/action.yml` file **MUST** open with this comment block immediately before `name:`, in the same style as shell script headers. All five sections are required; write `None` on the next line when a section does not apply. Checked by `test/bats/github-actions/workflow-header.bats` (workflows) and `test/bats/github-actions/action-header.bats` (composite actions). For a composite action, Kind is `Composite action`, Usage is the `uses:` line plus a `Called by:` line, and every `References` path must exist.

```yaml
#######################################
# Description:
#   <Kind> workflow: <title>
#   <details, optional extra lines>
#
# Usage:
#   <how it is called or triggered>
#
# Design Rules:
#   - <constraint>  (or `#   None`)
#
# Dependencies:
#   - <secrets, labels, permissions>  (or `#   None`)
#
# References:
#   - <design doc or spec path>  (or `#   None`)
#######################################
name: ...
```

| Section      | Requirement                                                                                                                          |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Description  | **MUST**. First line is `<Kind> workflow: <title>` with Kind one of `Reusable`, `Loop`, `CI`, `CD`, `Manual`, `Platform`.            |
| Usage        | **MUST**. Reusable (`ci-*`, `cd-*`): the `uses:` line and the `with:` / `secrets:` contract. `on-*` and `example/`: `Runs on:` list. |
| Design Rules | **MUST**. Constraints a maintainer must not break (security model, concurrency, delivery contract).                                  |
| Dependencies | **MUST**. Required secrets, labels, permissions, external setup. List every `workflow_call` secret; `None` only when there are none. |
| References   | **MUST**. Design doc, spec, or inputs reference paths.                                                                               |

Sections appear in the order above, each `# Name:` heading followed by `#` indented lines (list items use `#   -`; `None` is plain text, not a list item). Keep one fact per line and no trailing prose outside a section.

---

## Composition

| Rule                          | Requirement                                                                                                                                                                                                    |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Composite → composite         | **MUST NOT** call another config composite via `uses:` (local or remote). One action pin must stay self-contained.                                                                                             |
| Workflow → composite          | **MUST** call leaf composites via `uses:` only.                                                                                                                                                                |
| Workflow → `lib/run.sh`       | **MUST NOT** invoke action `lib/run.sh` from workflow YAML — bypasses the pin boundary.                                                                                                                        |
| Cross-action shared logic     | **MUST** live under `.github/actions/lib/<domain>/` (for example `lib/loop/`).                                                                                                                                 |
| Action-specific orchestration | **MUST** stay in that composite's own `lib/`.                                                                                                                                                                  |
| Sibling action scripts        | **MAY** call `${GITHUB_ACTION_PATH}/../<sibling-action>/lib/...` only for that sibling's owned behavior (for example CLI install). **MUST NOT** treat another composite's `lib/` as a shared contract library. |
| Portability                   | **MUST NOT** hardcode consumer paths (`scripts/`, `.agents/`, skill trees, APM install targets) inside reusables or composites.                                                                                |

Invoke shared or sibling scripts with `run:` + `bash`/`source`. Contexts are not expanded in `uses:`.

---

## Path resolution

`${GITHUB_ACTION_PATH}` (same as `${{ github.action_path }}` in composite `run:` steps) points to the **pinned action directory** in the runner's `_actions/` cache — not the caller's `GITHUB_WORKSPACE`.

| Caller                             | Resolve shared lib as                                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Composite `action.yml` `run:` step | `${GITHUB_ACTION_PATH}/../lib/<domain>/...`                                                                  |
| Script under `<action>/lib/*.sh`   | `$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/<domain>" && pwd)/...`                                       |
| Prefer                             | `source` `.github/actions/lib/loop/_resolve.sh` and use `LOOP_ACTION_LIB_DIR` when multiple paths are needed |

**MUST NOT** use `${GITHUB_WORKSPACE}/.github/actions/...` in paths meant to work when the action is consumed remotely.

---

## Reusable workflows and secrets

| Surface                    | Non-secrets          | Credentials                                                |
| -------------------------- | -------------------- | ---------------------------------------------------------- |
| Reusable (`workflow_call`) | `with:` → `inputs.*` | `secrets:` only — declare under `on.workflow_call.secrets` |
| Composite action           | `with:` → `inputs.*` | `with:` string inputs (no `secrets:` pass-through)         |

Reusable workflow rules:

1. **MUST** declare stable callee secret names (`AGENT_TOKEN`, `BOT_APP_*`, `GITHUB_TOKEN`, …).
2. **MUST** require callers to pass an explicit `secrets:` map (enables name remapping).
3. **MUST NOT** use `secrets: inherit`.
4. **MUST NOT** pass tokens via `with:` on reusable workflows.
5. When a reusable job sets `environment:`, environment-scoped secrets override caller-passed secrets with the same name — callers relying on remapped repo secrets should leave `environment` empty unless the environment defines those names.

Loop callers pass configuration via `with:` on the reusable; avoid caller-level `env:` blocks for loop caller workflows.

### Input defaults and discovery (reusable portability)

Reusable workflows (`ci-*`, `cd-*`) are **distribution artifacts**. Their `inputs.*.default` values and embedded step logic **MUST** stay portable — do not bake in this repository's layout, agent install trees, or gitignore habits.

| Rule                     | Requirement                                                                                                                                                                                                            |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Path/glob/exclude inputs | **MUST** default to empty (`""`) or equivalent “no filter”. Callers (`on-*`, `example/`) pass repo-specific values via `with:`.                                                                                        |
| Consumer layout          | **MUST NOT** hardcode or default agent roots (`.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`), APM paths (`.apm/`, `apm_modules/`), `scripts/`, skill trees, or other consumer-only directories in reusables. |
| Gitignore assumptions    | **MUST NOT** default excludes for paths that are normally absent from checkout (`node_modules`, `vendor`, `.terraform`, …). If a caller checks them out, it configures exclusions explicitly.                          |
| Discovery/prune logic    | **MUST NOT** embed consumer-specific `find`/prune branches in reusable steps. Expose filters as inputs; keep step scripts generic.                                                                                     |
| Examples                 | **MAY** cite repo-specific examples in `description:` text only. **MUST NOT** encode those examples in `default:`.                                                                                                     |
| Allowed defaults         | Tool version pins, checksums, severity/level enums, and other **tool-contract** defaults that do not assume consumer directory layout.                                                                                 |

When reviewing or authoring a reusable workflow, ask: _“Would this default or branch surprise a consumer with a different repo layout?”_ If yes, move it to the caller.

File prefixes: `ci-*` / `cd-*` (reusable), `on-*` (event caller), `example/` (consumer template). Map key ordering: ORD-01 in companion `github-actions-workflow` rules.

---

## Failure diagnostics

When a loop step records failure metadata for run logs or action outputs:

1. **MUST** redact sensitive text before persistence (shared `lib/loop/redact.sh` — do not duplicate patterns).
2. **MUST** record via shared `lib/loop/failure_record.sh` (`failure_record_write`).
3. **MUST** export to `GITHUB_OUTPUT` via shared `lib/loop/export_failure_diag.sh` — do not add per-action export duplicates.
4. **MUST NOT** write raw `git push`, `gh`, or CLI stderr to committed logs without redaction.

---

## Anti-patterns

| Anti-pattern                                                      | Why                                                      |
| ----------------------------------------------------------------- | -------------------------------------------------------- |
| `uses: ...@main` or `@v1.x` for config components                 | Unreproducible; policy violation                         |
| `uses: ./.github/actions/...` inside a composite step             | Broken in consumer repos                                 |
| `uses: ./.github/actions/...` in `ci-*` / `cd-*` workflows        | Distribution break — use remote SHA; bump pin on release |
| Nested `uses:` between config composites                          | Transitive pin drift                                     |
| `${GITHUB_WORKSPACE}/.github/actions/.../lib/run.sh` in workflows | Consumers lack that path                                 |
| `${GITHUB_ACTION_PATH}/../../lib/...` from action `run:` steps    | Wrong depth — use `../lib/...` from action root          |
| Shared logic in a composite's `lib/` instead of `actions/lib/`    | Couples actions; blocks reuse                            |
| Consumer-specific paths in reusables/actions                      | Breaks portability                                       |
| Consumer-tuned `inputs.*.default` paths/globs/excludes in `ci-*`  | Couples distribution to one repo layout                  |
| Hardcoded discovery/prune lists in reusable `run:` steps          | Callers cannot override without forking                  |
| `secrets: inherit` on reusable callers                            | Blocks secret name remapping                             |
| Credentials via `with:` on reusable workflows                     | Wrong channel                                            |
| Action → action via `env.*` from prior action `GITHUB_ENV`        | Hidden contract — use `steps.<id>.outputs.*`             |
| Force-push over `to.branch` on `pr_push`                          | Drops commits from earlier serialized runs               |
| `cancel-in-progress: true` on pr-revise concurrency               | Kills in-flight work; use queue + merge landing          |
| Assigning a global inside a function called via `$(...)`          | The subshell drops the assignment                        |

---

## pr_push and PR-revise concurrency

Design background: [PR Revise Workflow Design](../../docs/explanation/loop-engineering/workflows/loop-github-pr-revise-workflow-design.md#concurrency-and-pr_push-landing).

| Rule                  | Requirement                                                                                                                                                                                                               |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Same-PR serialize     | `on-loop-github-pr-revise.yaml` **MUST** keep `concurrency.group` keyed by PR number with `cancel-in-progress: false` and `queue: max`                                                                                    |
| No last-run-only      | **MUST NOT** cancel in-flight revise runs or force-push agent tips over `to.branch` to keep only the newest run                                                                                                           |
| `pr_push` merge       | `loop-finalize` **MUST** land via merge of the agent branch into the latest `to.branch` (`lib/push_target.sh`); conflicts and non-fast-forward pushes **MUST** fail closed                                                |
| Full clone            | Jobs that finalize with `pr_push` **MUST** checkout with `fetch-depth: 0` so merge can reach the latest `origin/to.branch`                                                                                                |
| Pin release           | Changing `loop-finalize` `pr_push` behavior **MUST** ship with a SHA pin bump in `ci-loop-agent.yaml` (or temporary dogfood `./.github/actions/...` per Pins); merged action code alone does not change dogfood execution |
| Landing contract      | `push_target.sh` checks out `origin/to.branch`, merges `origin/agent` with `--no-ff`, pushes without force, with explicit auth, an agent≠to guard, and fail-closed errors                                                 |
| `pr_create` untouched | Changes to `pr_push` landing **MUST NOT** alter the `pr_create` create-PR path                                                                                                                                            |

## Loop judgements (MUST)

Changing what decides whether a loop run proceeds, is skipped, or how an outcome is counted follows [Loop judgements go through the gate](../actions/CLAUDE.md#loop-judgements-go-through-the-gate-must), which also owns the shared name validators and the state-branch read rule. Job `if` in `on-loop-*.yaml` holds only static, cheap self-retrigger filters; actor trust, mention and repository visibility checks belong to the gate.

## Cross-job values, landing commits, and trusted ref (MUST)

- A value that two jobs must agree on (artifact name, target key) is computed once and passed as a job output (`needs.<job>.outputs.*`). Do not recompute it in the second job: `GITHUB_RUN_ATTEMPT` changes when only failed jobs are re-run.
- A commit that lands on a PR head (`pr_push` merge commit) **MUST NOT** carry `[skip ci]`. Only state, ledger, and run-log commits on `state_branch` do.
- A step that is not critical (for example Enable Auto-Merge) and runs before `Write State` **MUST** handle its own failure (warn and continue). A failure there would skip `Write State` and lose the pending PR cursor.
- A job that holds a write token (`detect`, `record-skip`, `finalize-l1`, `finalize-l2`) **MUST** check out `inputs.state_branch` on `pull_request*` events (`ref: ${{ startsWith(github.event_name, 'pull_request') && inputs.state_branch || '' }}`), so PR-controlled code never runs with that token. The read-only agent jobs keep the event ref. `test/bats/github-actions/loop-caller-parity.bats` pins the list.
- Shared name validators and where state data is read from: see [Loop judgements go through the gate](../actions/CLAUDE.md#loop-judgements-go-through-the-gate-must). Do not restate them here.

## Verification

Paired Bats when behavior changes (TEST-00): workflow files under `test/bats/github-actions/`, action code under `test/bats/.github/actions/<action>/lib/` and `test/bats/.github/actions/lib/loop/` (mirroring the source path). `pr_push` landing changes **MUST** include `test/bats/.github/actions/loop-finalize/lib/push_target.bats`.

---

## Security

- Reference secrets only via `${{ secrets.NAME }}` or `${{ github.token }}`; never echo tokens.
- Keep `permissions` least-privilege; document `zizmor: ignore[...]` only with justification.
- Do not place real tokens in workflow examples or comments.
- Mask or redact sensitive values in failure messages and logs before persistence.
