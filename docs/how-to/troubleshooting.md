<!-- omit in toc -->
# Troubleshooting

This document lists common issues when working with this repository and the recommended recovery steps.

<!-- omit in toc -->
## Table of Contents

- [APM Installation Issues](#apm-installation-issues)
  - [Symptom: `apm install --update` fails](#symptom-apm-install---update-fails)
- [Markdown and Instruction Validation](#markdown-and-instruction-validation)
  - [Symptom: markdownlint-cli2 failures in docs or instructions](#symptom-markdownlint-cli2-failures-in-docs-or-instructions)
- [APM Audit CI](#apm-audit-ci)
  - [Symptom: `ci-apm-audit` workflow fails with audit errors](#symptom-ci-apm-audit-workflow-fails-with-audit-errors)

## APM Installation Issues

### Symptom: `apm install --update` fails

**Cause**: dependency resolution drift, invalid local package references, or lock mismatch.

**Resolution**:

```sh
apm install --update
apm audit --ci
```

If the error persists, verify package paths in root `apm.yml` and each package `apm.yml`.

## Markdown and Instruction Validation

### Symptom: markdownlint-cli2 failures in docs or instructions

**Cause**: heading hierarchy issues, trailing newline issues, or inconsistent table formatting.

**Resolution**:

```sh
markdownlint-cli2 "docs/**/*.md" ".github/instructions/*.instructions.md"
git diff --check
```

Apply minimal fixes and re-run the checks.

## APM Audit CI

### Symptom: `ci-apm-audit` workflow fails with audit errors

**Cause**: lock file drift, missing or renamed package paths, or policy violations.

**Resolution**:

```sh
apm install --update
apm audit --ci --no-drift --no-cache
```

If policy checks fail, verify the policy configuration:

```sh
apm audit --ci --no-cache --policy org
```

Check that all package paths in `apm.yml` and sub-package `apm.yml` files are valid and that `apm.lock.yaml` is committed and up to date.
