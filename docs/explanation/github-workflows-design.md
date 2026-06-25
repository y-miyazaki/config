# GitHub Workflows Design

Design principles for Reusable Workflows and Composite Actions distributed from this repository.

## Distribution Model

This repository serves as a **distribution source**. Consumer repositories reference components remotely:

| Component | Reference Method |
|---|---|
| Reusable Workflow | `uses: y-miyazaki/config/.github/workflows/<name>@<sha>` |
| Composite Action | `uses: y-miyazaki/config/.github/actions/<name>@<sha>` |
| APM Package (Skill) | `apm install` deploys to consumer's `.claude/skills/` etc. |
| Caller Workflow | Consumer creates their own, using `example/` as template |

## Design Principles

### Portability Rule

> If another repository can use it via remote reference without modification → put it in an action/workflow. If it depends on specific paths or scripts → inline it in the caller.

| Location | Rule |
|----------|------|
| Reusable Workflow | No domain-specific logic. Criteria passed via inputs from caller |
| Composite Action | No dependency on specific scripts or repository-specific paths |
| Caller Workflow (`example/`) | Domain-specific logic (detection scripts, criteria) lives here |

### Prohibited External Dependencies

Reusable Workflows and Composite Actions **must not**:

- Hardcode APM target paths (`.claude/`, `.agents/`, `.kiro/`)
- Directly reference consumer repository scripts (`scripts/`, `skills/`)
- Assume consumer directory structure

### Cross-Action References

When a Composite Action calls another Composite Action, use **remote reference** (full SHA). Local references (`uses: ./`) cannot be resolved in consumer repositories.

```yaml
# ✅ Correct
uses: y-miyazaki/config/.github/actions/loop-state-write@<sha> # v1.x.x

# ❌ Fails in consumer repositories
uses: ./.github/actions/loop-state-write
```

### Versioning

- Consumers reference via **full commit SHA** (ghalint policy compliance)
- Tags (`v1.4.6`) annotated in comments for readability
- Bump major version on breaking changes

## Secrets Design

### Unified Token Pattern

Instead of separate secrets per engine, use a single `AGENT_TOKEN`. The action internally maps it to the engine-specific environment variable:

```yaml
# Caller passes one secret
secrets:
  AGENT_TOKEN: ${{ secrets.AGENT_TOKEN }}
```

| Engine | Internal Mapping |
|--------|-----------------|
| claude | `ANTHROPIC_API_KEY` |
| copilot | `COPILOT_GITHUB_TOKEN` |
| codex | `OPENAI_API_KEY` |

### GitHub Token Usage

| Purpose | Token | Rationale |
|---------|-------|-----------|
| PR creation / state push | `github.token` | Least privilege. Sufficient when CI re-trigger is not needed |
| PR that should trigger CI | GitHub App Token / PAT | `GITHUB_TOKEN`-created PRs do not trigger other workflows |

Note: At L3, `loop-finalize` enables auto-merge (`gh pr merge --auto --squash`) after PR creation. This requires branch protection rules with required status checks configured on the target branch.

## Input Design

### Defaults via env

Caller workflow configuration values are defined in `env:`. Not placed in `workflow_dispatch` inputs (avoids the limitation where cron-triggered runs have no inputs context).

```yaml
env:
  AGENT_MODEL: ""
  DEFAULT_BASE_BRANCH: main
  DEFAULT_ENGINE: claude
  DEFAULT_LEVEL: L2
  VERIFIER_MODEL: ""
```

### Passing env to Reusable Workflow with

GitHub Actions does not allow `env` context in reusable workflow `with:`. Pass values via detect job outputs:

```yaml
outputs:
  engine: ${{ steps.config.outputs.engine }}
  level: ${{ steps.config.outputs.level }}
```

## Authentication Pattern

Use `http.extraheader` for git push authentication (same pattern as `actions/checkout`):

```bash
git config http.https://github.com/.extraheader \
  "AUTHORIZATION: basic $(printf 'x-access-token:%s' "${TOKEN}" | base64 -w0)"
```

**Prohibited**: `url.insteadOf` pattern (token persists in plaintext in `.git/config`)

## Error Handling

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
