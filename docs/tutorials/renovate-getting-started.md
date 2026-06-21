# Getting Started with Renovate Shared Policy

Enable shared Renovate dependency update policies in your repository. This tutorial takes approximately 2 minutes.

## Prerequisites

- A GitHub repository with [Renovate](https://docs.renovatebot.com/) app installed or self-hosted Renovate configured
- Permissions to create files in `.github/`

## Goal

After completing this tutorial you will have:

1. Renovate configured to extend the shared baseline policy from this repository

## Step 1: Create Renovate Configuration

Create `.github/renovate.json`:

```json
{
  "extends": ["github>y-miyazaki/config//renovate/default"]
}
```

## Step 2: Add Project-Specific Overrides (Optional)

Add overrides after the shared preset:

```json
{
  "extends": ["github>y-miyazaki/config//renovate/default"],
  "schedule": ["before 6am on Monday"]
}
```

Project-specific rules take precedence over the shared baseline.

## Verification

1. Push the configuration file to your default branch
2. Wait for Renovate to run (check the Renovate dashboard issue or logs)
3. Confirm Renovate opens dependency update PRs following the shared policy

**Expected Result:**

Renovate creates a "Dependency Dashboard" issue and begins opening PRs according to the shared schedule and grouping rules.

## Next Steps

- [Specification](../reference/specification.md) — For details on the shared Renovate policy rules.
