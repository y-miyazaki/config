# Getting Started with Reusable GitHub Actions Workflows

Integrate shared reusable workflows into your repository's CI pipeline. This tutorial takes approximately 3 minutes.

## Prerequisites

- A GitHub repository with Actions enabled
- Permissions to create workflow files in `.github/workflows/`

## Goal

After completing this tutorial you will have:

1. A reusable workflow called from your repository
2. CI running shared lint/validation checks on pull requests

## Step 1: Create a Workflow Caller

Create `.github/workflows/ci-markdown.yaml`:

```yaml
name: CI Markdown
on:
  pull_request:
    paths:
      - "**/*.md"

jobs:
  markdown:
    uses: y-miyazaki/config/.github/workflows/ci-markdown.yaml@main
```

## Step 2: Pin to a Commit SHA

For production usage, replace `@main` with a specific commit SHA:

```yaml
jobs:
  markdown:
    uses: y-miyazaki/config/.github/workflows/ci-markdown.yaml@<commit-sha>
```

This prevents unexpected changes from upstream.

## Verification

1. Push the workflow file to a branch
2. Open a pull request that modifies a `.md` file
3. Confirm the workflow triggers and completes successfully in the Actions tab

**Expected Result:**

The `CI Markdown` workflow appears in the pull request checks and passes.

## Next Steps

- Reference: Specification (`docs/reference/specification.md`) — For the full list of available reusable workflows.
- Explanation: Architecture (`docs/explanation/architecture.md`) — To understand workflow naming conventions and trigger patterns.
