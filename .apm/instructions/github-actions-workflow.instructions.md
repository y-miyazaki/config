---
applyTo: ".github/workflows/**/*.yaml,.github/workflows/**/*.yml"
description: "AI Assistant Instructions for GitHub Actions Workflows"
---

# AI Assistant Instructions for GitHub Actions

## Scope

- 対象は `.github/workflows/*.yml|yaml` の設計・修正・検証に限定する

## Standards

### Naming Conventions

| Component     | Rule       | Example              |
| ------------- | ---------- | -------------------- |
| Workflow file | kebab-case | ci-build-deploy.yaml |
| Job ID        | kebab-case | build-and-test       |
| Step ID       | kebab-case | setup-node           |
| Environment   | lowercase  | production, staging  |
| Secret        | UPPER_SNAKE_CASE | DEPLOY_TOKEN   |
| Variable      | UPPER_SNAKE_CASE | APP_VERSION    |
| Artifact name | kebab-case | build-output-linux   |

### Key Ordering（MUST）

- **G-05 (MUST)**: `inputs`, `env`, `permissions`, `with` 内のキーはアルファベット順（A-Z） — 順序不統一だと差分レビューでノイズが増え変更検出が困難になる

## Guidelines

### Best Practices (BP)
- BP-01 (SHOULD): Reusable Workflow Design
  - Check: Are common processes extracted into reusable workflows or composite actions?
- BP-02 (SHOULD): DRY Principle for Duplication Reduction
  - Check: Is there code duplication?
- BP-03 (SHOULD): Explicit Job Dependencies
  - Check: Are job dependencies explicitly defined with `needs`?
- BP-04 (SHOULD): Simplify Conditional Branches
  - Check: Are `if` expressions concise and understandable?
- BP-05 (SHOULD): Limit Environment Variable Scope
  - Check: Is `env` defined with minimal scope?

### Error Handling (ERR)
- ERR-01 (SHOULD): Careful Use of continue-on-error
  - Check: Is `continue-on-error` used only for non-critical steps with explicit justification?
- ERR-02 (SHOULD): Failure and Always Guards for Cleanup/Notify
  - Check: Are `if: failure()` and `if: always()` used appropriately for cleanup, artifact upload, and notifications?
- ERR-03 (SHOULD): Timeout Configuration
  - Check: Are `timeout-minutes` values set for jobs or long-running steps?
- ERR-04 (SHOULD): Retry Strategy for Flaky Integrations
  - Check: Is retry logic configured for transient external failures (network/service instability)?

### Global / Base (G)
- G-01 (SHOULD): Clear Workflow Naming
  - Check: Is the workflow name clear and expressive of its purpose?
- G-02 (SHOULD): Limit Triggers (on)
  - Check: Are triggers appropriately narrowed down?
- G-03 (SHOULD): Step Clarification and Order Guarantee
  - Check: Does each step have a `name` and logical order?
- G-04 (SHOULD): Explicit Environment and Approval Flow
  - Check: Do production jobs have `environment` configuration and approval?

### Performance (PERF)
- PERF-01 (SHOULD): Cache Strategy and Invalidation
  - Check: Are cache keys deterministic and invalidated by dependency changes?
- PERF-02 (SHOULD): Matrix/Parallel Execution Balance
  - Check: Is matrix or parallel execution used where beneficial without excessive runner cost?
- PERF-03 (SHOULD): Concurrency Control
  - Check: Is `concurrency` configured to cancel redundant in-progress runs on same branch/context?
- PERF-04 (SHOULD): Reduce Unnecessary Workload
  - Check: Are broad triggers, full-repo checkout, and repeated setup steps minimized?

### Security (SEC)
- SEC-01 (SHOULD): Explicit Top-Level Permissions
  - Check: Are top-level permissions explicitly set?
- SEC-02 (SHOULD): Safe Secret References
  - Check: Are secrets referenced only via `${{ secrets.NAME }}` and not directly output?
- SEC-03 (SHOULD): Careful Use of pull_request_target
  - Check: Are fork PR restrictions in place when using `pull_request_target`?
- SEC-04 (SHOULD): Log Masking for Sensitive Information
  - Check: Are sensitive values masked with `::add-mask::` or `core.setSecret()`?
- SEC-05 (SHOULD): Pin Third-Party Actions
  - Check: Are critical actions pinned to SHA?
- SEC-06 (SHOULD): Sanitize Environment Variables
  - Check: Are environment variable inputs validated and sanitized?
- SEC-07 (SHOULD): Guardrails for Public Repositories
  - Check: Do public repositories have conditional branches like `github.event.repository.private`?

### Tool Integration (TOOL)
- TOOL-01 (SHOULD): Reviewdog Integration for PR Feedback
  - Check: Is reviewdog integrated where lint results should be surfaced on pull requests?
- TOOL-02 (SHOULD): Codecov Coverage Upload Strategy
  - Check: Is Codecov usage configured appropriately for repository visibility and token requirements?
- TOOL-03 (SHOULD): Artifact Retention Configuration
  - Check: Are uploaded artifacts configured with explicit retention periods appropriate for use case?
- TOOL-04 (SHOULD): Cache Key and Restore Strategy
  - Check: Are cache keys based on lockfiles and restore-keys configured for safe fallback?

### Code Modification Guidelines

- 変更後は [github-actions-validation Skill](../skills/github-actions-validation/SKILL.md) の validate.sh 実行を優先
- 個別コマンドはデバッグ時のみ使用


## Testing and Validation

**エントリポイント（推奨）**:

```bash
bash skills/github-actions-validation/scripts/validate.sh
```

**個別実行（デバッグ時）**:

```bash
# syntax and best-practice validation
actionlint

# policy validation
ghalint run

# security scanning
zizmor .github/workflows/
```

**詳細ガイド**: [github-actions-validation Skill](../skills/github-actions-validation/SKILL.md) を参照

## Security Guidelines

- `permissions` は最小権限を維持し、不要な `write` 権限を付与しない
- Secret は `${{ secrets.* }}` 経由のみで参照し、ログ出力しない
- サードパーティ Action は commit SHA pin を優先し、例外時は理由をコメントに残す
