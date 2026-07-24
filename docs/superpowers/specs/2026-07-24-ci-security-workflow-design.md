# CI Security Workflow Design

Date: 2026-07-24

## Goal

Extract duplicated Trivy filesystem scanning and CycloneDX SBOM generation from language-specific CI workflows (`ci-go`, `ci-nodejs`, `ci-aws-terraform`) into a dedicated reusable workflow (`ci-security`) invoked by a repository-wide caller (`on-ci-security`).

## Architecture

```text
on-ci-security.yaml          schedule + path-filtered push/PR + workflow_dispatch
  └─ ci-security.yaml        Trivy fs scan + CycloneDX SBOM (repo-wide by default)

on-ci-push-go.yaml
  └─ ci-go.yaml              test / lint / govulncheck (language-specific)

ci-nodejs / ci-aws-terraform  language checks only; Trivy removed
```

## Files

| File | Type | Role |
| ---- | ---- | ---- |
| `ci-security.yaml` | Reusable (`workflow_call`) | Trivy vulnerability gate + SBOM artifact |
| `on-ci-security.yaml` | Caller (dogfood) | Triggers security CI in this repository |
| `example/on-ci-security.yaml` | Consumer template | Copy into consumer repositories |

## `ci-security.yaml` contract

### Inputs (alphabetical)

| Input | Default | Description |
| ----- | ------- | ----------- |
| `artifact_prefix` | `repo` | Prefix for SBOM artifact name (`sbom-{prefix}`) |
| `dependency_review_fail_on_severity` | `high` | `dependency-review` fail-on-severity (`low`, `moderate`, `high`, `critical`) |
| `scan_ref` | `.` | Trivy `scan-ref` (repository root or monorepo subdirectory) |
| `trivy_config` | `trivy.yaml` | Path to Trivy config file (vuln scan, gate, and SBOM) |
| `trivy_version` | `v0.72.0` | Trivy version |

### Behavior

1. Checkout repository.
2. Install Trivy once (`aquasecurity/setup-trivy` with cache).
3. Run filesystem scans in one step: SARIF (`exit-code: 0`), gate (`exit-code: 1`, `ignore-unfixed: false`), CycloneDX SBOM (`exit-code: 0`). All scans honor `trivy_config`.
4. Upload Trivy SARIF to GitHub Security.
5. Upload SBOM artifact (`retention-days: 30`).
6. On pull requests, run `dependency-review` (requires `fetch-depth: 0` checkout).
7. Post PR failure comment when the Trivy gate fails.
8. Write job summary via `summary` composite action.

Language-specific security remains in language workflows:

- `govulncheck` → `ci-go`
- `npm` / `pnpm audit` → `ci-nodejs`

## `on-ci-security.yaml` triggers

| Trigger | Purpose |
| ------- | ------- |
| `schedule` (`0 6 * * *`) | Daily CVE drift detection on unchanged lockfiles |
| `push` / `pull_request` (path filters) | Gate new vulnerabilities before merge |
| `workflow_dispatch` | Manual rerun |

### Path filters

Security-relevant paths only (dependencies, IaC, containers, application source, Trivy config, workflow definitions):

- `**/go.mod`, `**/go.sum`, `**/*.go`
- `**/*.js`, `**/*.jsx`, `**/*.ts`, `**/*.tsx` (and e.g. `nodejs/**` for Node monorepos)
- `**/package.json`, `**/package-lock.json`, `**/pnpm-lock.yaml`, `**/yarn.lock`
- `**/*.tf`, `**/*.tfvars`, `**/.tflint.hcl`
- `**/Dockerfile`, `**/Dockerfile.*`
- `trivy.yaml`, `.trivyignore`
- `nodejs/**` (Node monorepos)
- `.github/workflows/ci-security.yaml`, `.github/workflows/on-ci-security.yaml`

## Risk mitigations

### 1. Consumers must add `on-ci-security`

**Risk:** Removing Trivy from language CI leaves no scan until the caller is added.

**Mitigation:**

- Ship `example/on-ci-security.yaml` with remote SHA pin.
- Document migration steps below.
- Dogfood `on-ci-security.yaml` in this repository.

### 2. Monorepo workspace SBOM granularity

**Risk:** A single repo-root scan may be insufficient when teams want per-service SBOM artifacts.

**Mitigation:**

- `ci-security` exposes `scan_ref` and `artifact_prefix` inputs.
- Callers can define multiple jobs (or a matrix) with different `with:` values.

Example (consumer):

```yaml
jobs:
  security-api:
    uses: y-miyazaki/config/.github/workflows/ci-security.yaml@<sha> # vX.Y.Z
    with:
      artifact_prefix: api
      scan_ref: services/api
  security-web:
    uses: y-miyazaki/config/.github/workflows/ci-security.yaml@<sha> # vX.Y.Z
    with:
      artifact_prefix: web
      scan_ref: services/web
```

### 3. PR gate + cron coverage

**Risk:** Cron-only scanning does not block vulnerable PRs; path-only scanning misses overnight CVEs.

**Mitigation:** `on-ci-security` uses **both** `schedule` and path-filtered `push` / `pull_request`.

## Consumer migration

1. Copy `example/on-ci-security.yaml` to `.github/workflows/on-ci-security.yaml`.
2. Replace `<sha>` with the released `y-miyazaki/config` commit SHA.
3. Adjust `paths:` if the repository layout differs (add consumer-specific lockfile or IaC globs).
4. Remove `trivy.yaml` from language CI caller path filters (for example `on-ci-push-go.yaml`) so Trivy changes trigger security CI instead of Go CI only.
5. Upgrade pinned `ci-go`, `ci-nodejs`, and `ci-aws-terraform` refs to a release that no longer embeds Trivy.
6. Optional monorepo: add extra `ci-security` jobs with `scan_ref` / `artifact_prefix` per service.

## Out of scope

- Moving `govulncheck` into `ci-security` (stays in `ci-go`; Go reachability is a language concern)
- Container image scanning in `cd-go-releaser` (binary release only; use `cd-aws-go-registry` `trivy_image_scan`)

## Extensions (2026-07-24)

| Capability | Location | Gate |
| ---------- | -------- | ---- |
| `dependency-review` | `ci-security` (`dependency-review` job, PR only) | Blocks on `fail-on-severity: high` |
| Trivy SARIF | `ci-security` (`trivy` job) | Security tab + separate gate step (`ignore-unfixed: false`; blocks on HIGH/CRITICAL including unfixed) |
| CodeQL + Semgrep | `ci-sast` | Semgrep `--error`; CodeQL via GitHub defaults |
| Trivy image scan | `cd-aws-go-registry` after ECR push | Blocks on HIGH/CRITICAL fixable CVEs only (`ignore-unfixed: true`; base-image CVEs without a vendor fix do not block deploy) |

**Note:** Image scan runs after push to ECR; the job fails before downstream deploy callers proceed, but the image tag already exists in the registry. Use `trivy_image_scan: false` to disable for bootstrap repos.

## Verification

```bash
bash .agents/skills/github-actions-validation/scripts/validate.sh .github/workflows/
```
