# AGENTS.md

Behavioral rules for editing `.github/workflows/**` and `.github/actions/**` in this repository. Self-contained for workflow authors and agents.

---

## Scope

- Applies when creating or updating workflow YAML (`.github/workflows/`) and composite actions (`.github/actions/`).
- This repository is a **distribution source**: reusable workflows and composite actions are consumed remotely from other repositories.
- Deeper design context: [GitHub Workflows Design](../../docs/explanation/github-workflows-design.md). Functional contracts: [Specification](../../docs/reference/specification.md).

## Pin Policy

### MUST: full commit SHA

Reference **this repository's** reusable workflows and composite actions with a **full commit SHA**, not a branch or tag ref:

```yaml
# ✅ Consumer and ci-*/cd-* reusable workflows
uses: y-miyazaki/config/.github/workflows/ci-loop-caller.yaml@79d74d1dadea776a3a99178c3e082e7fe5d7db65 # v1.8.16
uses: y-miyazaki/config/.github/actions/loop-detect@79d74d1dadea776a3a99178c3e082e7fe5d7db65 # v1.8.16

# ❌ Unpinned or tag-only refs
uses: y-miyazaki/config/.github/actions/loop-detect@main
uses: y-miyazaki/config/.github/actions/loop-detect@v1.8.16
```

Add a `# vX.Y.Z` comment on the same line as the SHA so reviewers can map pins to releases.

### Third-party actions

Pin third-party actions (for example `actions/checkout`) with a **full commit SHA** as well. Annotate the upstream version in a comment when known.

### Where pins apply

| Caller context                                 | Reusable workflow                                                             | Composite action                                                            |
| ---------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `example/` (consumer template)                 | Remote SHA pin                                                                | Remote SHA pin                                                              |
| `ci-*`, `cd-*` reusable workflows in this repo | Remote SHA pin when calling other reusables                                   | Remote SHA pin                                                              |
| `on-*` callers in this repo (dogfood)          | `./.github/workflows/...` allowed while iterating on unreleased graph changes | `./.github/actions/...` allowed while iterating on unreleased action source |
| Consumer repositories                          | Remote SHA pin only                                                           | Remote SHA pin only                                                         |

**Rule of thumb:** anything another repository copies must use a remote SHA pin. Local `./.github/...` paths are for **this repository only** during development; they must not appear in `example/` or in composite action internals.

After releasing new actions or reusable workflows, bump SHA pins in `ci-*`, `cd-*`, and `example/` in the same change set (or follow the release checklist).

## Composite Actions: No Nesting

Loop **composite actions must not** call other composite actions from this repository via `uses:` — neither local nor remote:

```yaml
# ❌ Nested composite (fails or causes transitive pin drift in consumers)
uses: ./.github/actions/loop-run-log
uses: y-miyazaki/config/.github/actions/loop-run-log@<sha>
```

Parent composites invoke shared bash under `.github/actions/lib/` or sibling action `lib/` paths:

```yaml
# ✅ Shared loop library (preferred for cross-action logic)
run: bash -c 'source "${GITHUB_ACTION_PATH}/../lib/loop/handoff.sh"'

# ✅ Action-specific orchestration script inside the same composite
run: bash "${GITHUB_ACTION_PATH}/lib/write_state.sh"
```

Cross-action **library** code belongs under `.github/actions/lib/<domain>/` (for example `lib/loop/handoff.sh`). Do not source another composite's `lib/` for shared contracts — that couples actions by name.

Rationale: a single action SHA stays self-contained at release time without hidden transitive dependencies.

### `GITHUB_ACTION_PATH` vs caller workspace

`${GITHUB_ACTION_PATH}` (same as `${{ github.action_path }}`) is **not** the consumer repository's `GITHUB_WORKSPACE/.github/actions/`.

When a workflow pins a remote action:

```yaml
uses: y-miyazaki/config/.github/actions/loop-agent-once@<full-sha>
```

GitHub downloads the **config repository snapshot at that SHA** into the runner's `_actions/` cache. `GITHUB_ACTION_PATH` points to the downloaded action directory inside that snapshot, for example:

```text
.../_actions/y-miyazaki/config/<sha>/.github/actions/loop-agent-once   ← GITHUB_ACTION_PATH
.../_actions/y-miyazaki/config/<sha>/.github/actions/loop-install-cli   ← ../loop-install-cli
```

So this pattern inside a composite `run:` step resolves against the **pinned config repo tree**, not the caller's checkout:

```yaml
run: bash "${GITHUB_ACTION_PATH}/../loop-install-cli/lib/install.sh"
```

| Variable / path                                           | Resolves to                                                                   |
| --------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `GITHUB_WORKSPACE`                                        | Consumer repo checkout (caller workflow's repository)                         |
| `GITHUB_ACTION_PATH`                                      | Downloaded action directory for the **currently executing** composite action  |
| `uses: ./.github/actions/...` in a **workflow** step      | Relative to `GITHUB_WORKSPACE` (caller repo only)                             |
| `uses: ./.github/actions/...` inside a **composite** step | Relative to caller workspace — **broken for distributed actions**; do not use |

The shared `lib/` and sibling action patterns work because one SHA pin carries the whole `.github/actions/*` tree for that commit. It does **not** work in `uses:` (contexts are not expanded there); use `run:` + `GITHUB_ACTION_PATH` instead.

**Workflows are different:** job steps call leaf composite actions via `uses:` — never invoke `lib/run.sh` directly from a workflow.

```yaml
# ✅ Workflow step
uses: ./.github/actions/loop-state-promote
with:
  merged: ${{ github.event.pull_request.merged && 'true' || 'false' }}
  pr_number: ${{ github.event.pull_request.number }}
  state_push_branch: ""
  token: ${{ secrets.GH_TOKEN_PUSH || github.token }}

# ❌ Workflow bypasses the action interface (breaks consumer copies)
run: bash "${GITHUB_WORKSPACE}/.github/actions/loop-state-promote/lib/run.sh"
```

Consumer workflows pin the action:

```yaml
uses: y-miyazaki/config/.github/actions/loop-state-promote@<full-sha> # vX.Y.Z
```

## Calling Reusables and Actions

### Default pattern

1. **Reusable workflow** — `jobs.<id>.uses` with remote SHA pin (or `./.github/workflows/...` only for same-repo dogfood callers).
2. **Composite action** — step `uses` with remote SHA pin (or `./.github/actions/...` only for same-repo dogfood steps).
3. **Never** call `lib/run.sh` from workflow YAML.

### File roles

| Prefix         | Role                       | Typical `uses` target                                               |
| -------------- | -------------------------- | ------------------------------------------------------------------- |
| `ci-*`, `cd-*` | Reusable (`workflow_call`) | Pin remote actions/workflows at release SHA                         |
| `on-*`         | Event caller               | Pin remote reusable, or `./.github/workflows/ci-*.yaml` for dogfood |
| `example/`     | Consumer copy template     | Always remote SHA pin                                               |

### Workflow conventions

- Keys in `inputs`, `env`, `permissions`, and `with` are **alphabetically ordered** (A→Z).
- File names: `ci-*` (CI), `cd-*` (CD), `on-*` (event-triggered callers).
- Reusable workflows use `workflow_call`; callers pass configuration via `with:` (avoid caller-level `env:` blocks for loop callers).

### Secrets and credentials (GitHub Actions constraints)

Official docs: [Reuse workflows — inputs and secrets](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-inputs-and-secrets-in-a-reusable-workflow).

| Mechanism          | Reusable workflow (`workflow_call`)                                                                                                         | Composite action                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Non-secret config  | `with:` → `inputs.*`                                                                                                                        | `with:` → `inputs.*`                                                      |
| Credentials        | **`secrets:` only** → `secrets.*` (declare under `on.workflow_call.secrets`)                                                                | `with:` (actions have no `secrets:` pass-through; treat as string inputs) |
| `secrets: inherit` | **Do not use** — forces callee secret _names_ to match the caller repo/org names; blocks remapping (e.g. `MAINTENANCE_BOT_*` → `BOT_APP_*`) | N/A                                                                       |

**Reusable workflows — required pattern:**

1. Declare credentials under `on.workflow_call.secrets` with **stable callee names** (e.g. `BOT_APP_CLIENT_ID`, `BOT_APP_PRIVATE_KEY`, `AGENT_TOKEN`, `GH_TOKEN_PUSH`).
2. Callers pass **explicit** `secrets:` maps so local names can differ:

   ```yaml
   secrets:
     AGENT_TOKEN: ${{ secrets.AGENT_TOKEN }}
     BOT_APP_CLIENT_ID: ${{ secrets.MAINTENANCE_BOT_APP_CLIENT_ID }}
     BOT_APP_PRIVATE_KEY: ${{ secrets.MAINTENANCE_BOT_APP_PRIVATE_KEY }}
   ```

3. Optional `with: environment:` — jobs inside the reusable that need environment-scoped secrets set `environment: ${{ inputs.environment }}`. Callers **cannot** set `environment:` on a job that `uses:` a reusable (platform restriction). Environment secrets are resolved **inside** the reusable job, not by the caller.
4. Do **not** pass tokens/app keys as `with:` string inputs on reusable workflows — that bypasses the `secrets` channel and is not the supported contract.
5. Do **not** use `secrets: inherit`.

**Composite actions:** pass tokens via `with:` (e.g. `token: ${{ secrets.BOT_APP_PRIVATE_KEY }}` from a job that already resolved secrets).

**Environment-secret caveat (docs):** if a reusable job sets `environment:`, environment secrets with the same names take precedence over secrets passed from the caller. Callers that rely on remapped repository secrets should leave `environment` empty unless the environment defines the expected names.

## Anti-Patterns

| Anti-pattern                                                                            | Why                                                  |
| --------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `uses: ...@main` or `uses: ...@v1.x` for config components                              | Unreproducible; ghalint policy violation             |
| `uses: ./.github/actions/...` inside a composite action                                 | Unresolvable in consumer repositories                |
| Nested `uses:` between config composite actions                                         | Transitive pin drift; use `lib/run.sh` sibling paths |
| `bash "${GITHUB_WORKSPACE}/.github/actions/.../lib/run.sh"` in workflows                | Consumers lack that path; bypasses pin boundary      |
| Hardcoded consumer paths (`scripts/`, `.agents/`, skill paths) inside reusables/actions | Breaks portability rule                              |
| `secrets: inherit` on reusable callers                                                  | Locks callee secret names; prevents remapping        |
| Passing credentials via `with:` on reusable workflows                                   | Unsupported channel; use `secrets:`                  |

## Verification

After workflow or action changes:

```bash
bash .agents/skills/github-actions-validation/scripts/validate.sh .github/workflows/ .github/actions/
```

When loop caller permissions change:

```bash
bash scripts/self/ci/validate_loop_caller_permissions.sh
```

## Security

- Reference secrets only via `${{ secrets.NAME }}` or `${{ github.token }}`; never echo tokens.
- Keep `permissions` at least privilege; document `zizmor: ignore[...]` only with justification.
- Do not place real tokens in workflow examples or comments.
