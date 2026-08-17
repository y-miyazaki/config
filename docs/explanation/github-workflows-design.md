# GitHub Workflows Design

Design principles for Reusable Workflows and Composite Actions distributed from this repository.

## Distribution Model

This repository serves as a **distribution source**. Consumer repositories reference components remotely:

| Component           | Reference Method                                           |
| ------------------- | ---------------------------------------------------------- |
| Reusable Workflow   | `uses: y-miyazaki/config/.github/workflows/<name>@<sha>`   |
| Composite Action    | `uses: y-miyazaki/config/.github/actions/<name>@<sha>`     |
| APM Package (Skill) | `apm install` deploys to consumer's `.claude/skills/` etc. |
| Caller Workflow     | Consumer creates their own, using `example/` as template   |

## Design Principles

### Portability Rule

> If another repository can use it via remote reference without modification → put it in an action/workflow. If it depends on specific paths or scripts → inline it in the caller.

| Location                     | Rule                                                             |
| ---------------------------- | ---------------------------------------------------------------- |
| Reusable Workflow            | No domain-specific logic. Criteria passed via inputs from caller |
| Composite Action             | No dependency on specific scripts or repository-specific paths   |
| Caller Workflow (`example/`) | Domain-specific logic (detection scripts, criteria) lives here   |

### Prohibited External Dependencies

Reusable Workflows and Composite Actions **must not**:

- Hardcode APM target paths (`.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.kiro/`)
- Directly reference consumer repository scripts (`scripts/`, `skills/`)
- Assume consumer directory structure

### Cross-Action References

Loop composites **must not** nest `uses:` between config actions. Shared logic belongs in `.github/actions/lib/`; see [.github/workflows/AGENTS.md](https://github.com/y-miyazaki/config/blob/main/.github/workflows/AGENTS.md#composition) (Composition, Path resolution).

Workflows call leaf composites via remote SHA pin:

```yaml
uses: y-miyazaki/config/.github/actions/loop-finalize@<sha> # v1.x.x
```

`uses: ./.github/actions/...` inside a composite step does not resolve in consumer repositories.

### Versioning

- Consumers reference via **full commit SHA** (ghalint policy compliance)
- Tags (`v1.4.6`) annotated in comments for readability
- Bump major version on breaking changes
- `ci-*` / `cd-*` reusables **must not** use `uses: ./.github/actions/...` — only `on-*` dogfood may temporarily; release ships remote SHA bumps in the same changeset (see [.github/workflows/AGENTS.md](../../.github/workflows/AGENTS.md#pins))

## Secrets Design

### Unified Token Pattern

Instead of separate secrets per engine, use a single `AGENT_TOKEN`. The action internally maps it to the engine-specific environment variable:

```yaml
# Caller passes one secret
secrets:
  AGENT_TOKEN: ${{ secrets.AGENT_TOKEN }}
```

| Engine  | Internal Mapping       |
| ------- | ---------------------- |
| claude  | `ANTHROPIC_API_KEY`    |
| copilot | `COPILOT_GITHUB_TOKEN` |
| codex   | `OPENAI_API_KEY`       |

### GitHub Token Usage

| Purpose                   | Token                  | Rationale                                                    |
| ------------------------- | ---------------------- | ------------------------------------------------------------ |
| PR creation / state push  | `github.token`         | Least privilege. Sufficient when CI re-trigger is not needed |
| PR that should trigger CI | GitHub App Token / PAT | `GITHUB_TOKEN`-created PRs do not trigger other workflows    |

Note: At L3, `loop-finalize` enables auto-merge (`gh pr merge --auto --squash`) after PR creation. This requires branch protection rules with required status checks configured on the target branch.

### Composite action outputs vs GITHUB_ENV

| Channel                                  | Use for                                                           | Do not use for                                                                   |
| ---------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `GITHUB_OUTPUT` → `steps.<id>.outputs.*` | Wiring **between** composite actions and workflow `with:` / `if:` | Secrets (passwords, tokens) — use masked `GITHUB_ENV` for downstream `run:` only |
| `GITHUB_ENV`                             | Shell environment for subsequent **`run:`** steps in the same job | Implicit cross-step contracts — readers cannot see which step set `env.DB_HOST`  |

Rules:

1. Composite actions **MUST** declare every value consumed by another action in `outputs` on `action.yml`.
2. Workflows **MUST** pass action inputs via `steps.<id>.outputs.<name>`, not `env.<NAME>` set by a prior action.
3. `GITHUB_ENV` **MAY** remain when a `run:` script needs shell variables (especially masked credentials).
4. Prefer `env:` on the `run:` step sourced from `steps.*.outputs` for non-secret values instead of job-wide `GITHUB_ENV` side effects.

## Input Design

### Defaults via env

Most caller workflows define configuration in `env:` when jobs are inlined in the caller. Not placed in `workflow_dispatch` inputs (cron-triggered runs have no inputs context).

**Loop callers:** `on-loop-*.yaml` pass configuration via `with:` on `ci-loop-caller.yaml` (no caller `env:`), matching `on-ci-push-*.yaml`. See [Loop Caller Reusable Workflow Design](loop-engineering/loop-caller-reusable-design.md) and [Loop Caller Inputs Reference](loop-engineering/workflows/loop-caller-inputs-reference.md).

```yaml
env:
  AGENT_MODEL: ""
  DEFAULT_BASE_BRANCH: main
  DEFAULT_ENGINE: claude
  DEFAULT_LEVEL: L2
  AGENT_VERIFIER_MODEL: ""
```

### Passing configuration to reusable workflows

Thin callers pass fixed literals in `with:` (same pattern as `on-cd-mkdocs.yaml` and `on-loop-*.yaml` on `ci-loop-caller.yaml`).

Legacy loop pattern (pre-`ci-loop-caller`): map caller `env` → action `with:` inside inlined detect jobs. Detect job outputs passthrough to execute:

```yaml
outputs:
  engine: ${{ steps.config.outputs.engine }}
  level: ${{ steps.config.outputs.level }}
```

## Authentication Pattern

Use `http.extraheader` for git push authentication (same pattern as `actions/checkout`):

```bash
git config http.https://github.com/.extraheader \
  "AUTHORIZATION: basic [REDACTED:Authorization header] 'x-access-token:[REDACTED:API key param]' "${TOKEN}" | base64 -w0)"
```

**Prohibited**: `url.insteadOf` pattern (token persists in plaintext in `.git/config`)

## Error Handling

### Failure diagnostics (loop actions)

When loop composite steps record failure metadata for run logs or action outputs, use the shared libraries under `.github/actions/lib/loop/` — see [.github/workflows/AGENTS.md](https://github.com/y-miyazaki/config/blob/main/.github/workflows/AGENTS.md#failure-diagnostics) (Failure diagnostics):

| Library                  | Role                                                                      |
| ------------------------ | ------------------------------------------------------------------------- |
| `redact.sh`              | Redact secrets/tokens before persistence                                  |
| `failure_record.sh`      | Record latest `failure_stage` / `failure_message` (`loop_failure_record`) |
| `export_failure_diag.sh` | Export recorded diagnostics to `GITHUB_OUTPUT`                            |

`loop-execute` and `loop-finalize` expose `failure_stage` / `failure_message`; `ci-loop-agent` passes them into `loop-run-log` JSONL entries. Do not duplicate redaction patterns or per-action export helpers. Do not write raw `git push`, `gh`, or CLI stderr into committed logs without redaction.

### jq Parse Errors

When parsing external input (state files, detection script output) with `jq`, fall back on error:

```bash
VALUE=$(jq -r '.key // empty' file.json 2>/dev/null || true)
```

### Branch Name Validation

Always validate branch names received from external inputs:

```bash
if ! [[ "${BRANCH}" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
  echo "::error::Invalid branch name: ${BRANCH}"
  exit 1
fi
```

### Push Retry

State update pushes include retry for conflict resolution:

```bash
git push origin HEAD || {
  git pull --rebase origin HEAD
  git push origin HEAD
}
```

## CLI Engine Management

### Installation

Local install + `npx` execution (no global install required):

```bash
npm install "${PACKAGE}@${VERSION}" --no-save
npx copilot "${ARGS[@]}"
```

### Version Resolution

- `cli_version: latest` (default) → resolved via `npm view` to actual version
- Registry connection failure → step fails immediately (no fallback to stale value, ensures idempotency)
