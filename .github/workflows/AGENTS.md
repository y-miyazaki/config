# AGENTS.md

Behavioral rules for `.github/workflows/**` and `.github/actions/**`. This repository is a **distribution source** — consumers pin workflows and composites by commit SHA.

Design background: [GitHub Workflows Design](../../docs/explanation/github-workflows-design.md). Contracts: [Specification](../../docs/reference/specification.md).

---

## Pins

| Rule                                         | Requirement                                                                                                                                 |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Config components                            | **MUST** use a full commit SHA (`uses: org/repo/.github/...@<sha> # vX.Y.Z`). Tags and branches are forbidden.                              |
| Third-party actions                          | **MUST** pin by full SHA; annotate upstream version in a comment when known.                                                                |
| Consumer copies (`example/`, external repos) | **MUST** use remote SHA pins only.                                                                                                          |
| Dogfood (`on-*` workflow steps)              | **MAY** use `./.github/workflows/...` or `./.github/actions/...` while iterating unreleased graph changes.                                  |
| Composite internals                          | **MUST NOT** use `uses: ./.github/actions/...` — unresolvable in consumer repositories.                                                     |
| Release                                      | **MUST** bump SHA pins in `ci-*`, `cd-*`, and `example/` in the same change set as new action/workflow releases (or per release checklist). |

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

1. **MUST** declare stable callee secret names (`AGENT_TOKEN`, `BOT_APP_*`, `GH_TOKEN_PUSH`, …).
2. **MUST** require callers to pass an explicit `secrets:` map (enables name remapping).
3. **MUST NOT** use `secrets: inherit`.
4. **MUST NOT** pass tokens via `with:` on reusable workflows.
5. When a reusable job sets `environment:`, environment-scoped secrets override caller-passed secrets with the same name — callers relying on remapped repo secrets should leave `environment` empty unless the environment defines those names.

Loop callers pass configuration via `with:` on the reusable; avoid caller-level `env:` blocks for loop caller workflows.

File prefixes: `ci-*` / `cd-*` (reusable), `on-*` (event caller), `example/` (consumer template). Map key ordering: ORD-01 in companion `github-actions-workflow` rules.

---

## Failure diagnostics

When a loop step records failure metadata for run logs or action outputs:

1. **MUST** redact sensitive text before persistence (shared `lib/loop/redact.sh` — do not duplicate patterns).
2. **MUST** record via shared `lib/loop/failure_record.sh` (`loop_failure_record`).
3. **MUST** export to `GITHUB_OUTPUT` via shared `lib/loop/export_failure_diag.sh` — do not add per-action export duplicates.
4. **MUST NOT** write raw `git push`, `gh`, or CLI stderr to committed logs without redaction.

---

## Anti-patterns

| Anti-pattern                                                      | Why                                             |
| ----------------------------------------------------------------- | ----------------------------------------------- |
| `uses: ...@main` or `@v1.x` for config components                 | Unreproducible; policy violation                |
| `uses: ./.github/actions/...` inside a composite step             | Broken in consumer repos                        |
| Nested `uses:` between config composites                          | Transitive pin drift                            |
| `${GITHUB_WORKSPACE}/.github/actions/.../lib/run.sh` in workflows | Consumers lack that path                        |
| `${GITHUB_ACTION_PATH}/../../lib/...` from action `run:` steps    | Wrong depth — use `../lib/...` from action root |
| Shared logic in a composite's `lib/` instead of `actions/lib/`    | Couples actions; blocks reuse                   |
| Consumer-specific paths in reusables/actions                      | Breaks portability                              |
| `secrets: inherit` on reusable callers                            | Blocks secret name remapping                    |
| Credentials via `with:` on reusable workflows                     | Wrong channel                                   |

---

## Verification

```bash
bash .agents/skills/github-actions-validation/scripts/validate.sh .github/workflows/ .github/actions/
```

When loop caller permissions change:

```bash
bash scripts/self/ci/validate_loop_caller_permissions.sh
```

Paired Bats under `test/bats/.github/` when behavior changes (TEST-00).

---

## Security

- Reference secrets only via `${{ secrets.NAME }}` or `${{ github.token }}`; never echo tokens.
- Keep `permissions` least-privilege; document `zizmor: ignore[...]` only with justification.
- Do not place real tokens in workflow examples or comments.
- Mask or redact sensitive values in failure messages and logs before persistence.
