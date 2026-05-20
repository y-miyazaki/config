<!-- omit in toc -->
# Troubleshooting

This document lists common issues when working with this repository and the recommended recovery steps.

<!-- omit in toc -->
## Table of Contents

- [APM Installation Issues](#apm-installation-issues)
  - [Symptom: `apm install --update` fails](#symptom-apm-install---update-fails)
- [Markdown and Instruction Validation](#markdown-and-instruction-validation)
  - [Symptom: markdownlint failures in docs or instructions](#symptom-markdownlint-failures-in-docs-or-instructions)
- [Terraform Linting](#terraform-linting)
  - [Symptom: `tflint` fails after template updates](#symptom-tflint-fails-after-template-updates)

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

### Symptom: markdownlint failures in docs or instructions

**Cause**: heading hierarchy issues, trailing newline issues, or inconsistent table formatting.

**Resolution**:

```sh
markdownlint docs/ .github/instructions/*.instructions.md
git diff --check
```

Apply minimal fixes and re-run the checks.

## Terraform Linting

### Symptom: `tflint` fails after template updates

**Cause**: rulesets not initialized, or linting is executed only in current directory without recursive scan.

**Resolution**:

```sh
tflint --init
tflint --recursive
```

If needed, run with explicit working directory:

```sh
tflint --chdir path/to/terraform --recursive
```
