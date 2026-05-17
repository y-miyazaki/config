<!-- omit in toc -->
# Config Repository Functional Specification

This document defines the functional specification of this repository, including the intended structure and how shared configuration assets are organized.

Usage guidance is documented in [README.md](../README.md). This document is the specification source of truth under docs.

<!-- omit in toc -->
## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
  - [Root-Level Components](#root-level-components)
  - [APM-Related Components](#apm-related-components)
  - [Validation and Utility Components](#validation-and-utility-components)
- [APM](#apm)
  - [Distribution Behavior](#distribution-behavior)
  - [Scope](#scope)
- [GitHub Actions](#github-actions)
  - [Reusable Workflow Behavior](#reusable-workflow-behavior)
  - [Scope](#scope-1)
- [Renovate](#renovate)
  - [Shared Policy Behavior](#shared-policy-behavior)
  - [Scope](#scope-2)
- [Configuration Defaults](#configuration-defaults)
- [Testing and Validation](#testing-and-validation)
- [Troubleshooting](#troubleshooting)

## Overview

This repository provides shared configuration assets for AI-assisted development and platform operations.

The primary goals are:

- share AI agent settings as APM-distributed packages
- share reusable GitHub Actions workflows
- share Renovate update policy and defaults

## Prerequisites

- APM CLI for package-based distribution
- GitHub Actions for workflow execution and workflow reuse
- Renovate for dependency update automation

## Repository Structure

The repository structure is function-oriented.

### Root-Level Components

- `README.md`: usage and onboarding
- `docs/`: repository specifications and reference documents
- `apm.yml`: APM package metadata and dependency entry point
- `apm.lock.yaml`: lock file for deterministic APM resolution
- `renovate/`: Renovate shared policy definitions
- `.github/workflows/`: reusable and caller workflows

### APM-Related Components

- `.apm/skills/`: shared skill definitions
- `.apm/instructions/`: shared instruction definitions
- `.apm/packages/`: grouped package bundles for target environments
- `apm_modules/`: locally materialized module content

### Validation and Utility Components

- `scripts/`: execution helpers for validation, build, and deployment support
- `test/`: test assets and fixtures
- `env/`: container and environment helpers

## APM

This repository shares AI agent settings as APM-distributed packages.

### Distribution Behavior

The repository must be consumable as an APM dependency.

- consumers can install the shared package with `apm install`
- package resolution must be deterministic with `apm.lock.yaml`
- configuration assets are deployed to the appropriate target by APM

### Scope

- `.apm/skills/`: shared skill definitions
- `.apm/instructions/`: shared instruction definitions
- `.apm/packages/`: grouped package bundles for target environments
- `apm.yml` and `apm.lock.yaml`: package metadata and lock state

## GitHub Actions

This repository shares reusable GitHub Actions workflow definitions.

### Reusable Workflow Behavior

The repository must provide reusable workflows.

- workflows intended for reuse are defined with `workflow_call`
- caller workflows can reference reusable workflows within this repository
- external repositories can consume reusable workflows via `uses: <owner>/<repo>/.github/workflows/<workflow>.yaml@<ref>`

### Scope

- `.github/workflows/`: reusable workflows and caller workflows

## Renovate

This repository shares centrally managed Renovate policy presets.

### Shared Policy Behavior

The repository must provide centrally managed Renovate defaults.

- shared policy baseline is defined in `renovate/default.json`
- workflow tool-version updates are defined in `renovate/github-actions-tool-version.json`
- consumers can extend the baseline via `.github/renovate.json`

### Scope

- `renovate/default.json`: baseline policy
- `renovate/github-actions-tool-version.json`: workflow tool-version update rules
- `renovate/README.md`: policy details and operational notes

## Configuration Defaults

| Parameter                    | Default   | Notes                                              |
| ---------------------------- | --------- | -------------------------------------------------- |
| `target` in `apm.yml`        | `copilot` | Default deployment target for APM install          |
| `includes` in `apm.yml`      | `auto`    | Automatic include behavior for package composition |
| Renovate minimum release age | `7 days`  | Global baseline in shared Renovate policy          |

## Testing and Validation

Use repository validation workflows and scripts for changed assets:

- Markdown checks for documentation changes
- GitHub Actions workflow checks for workflow changes
- domain-specific checks for Go, shell script, and Terraform assets

## Troubleshooting

- If APM install results differ across environments, verify [apm.lock.yaml](../apm.lock.yaml) is committed and up to date.
- If reusable workflows fail to resolve, verify repository visibility and workflow reference format.
- If Renovate behavior differs from expectation, verify extends and rule precedence against [renovate/default.json](../renovate/default.json).
