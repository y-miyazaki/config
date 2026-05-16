---
name: github-pr-body
description: >-
  Update PR body content with deterministic baseline sections and optional full-body completion.
  Use when creating PRs or regenerating template-driven summaries.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

## Input

- PR number and `owner/repo` (required)
- Existing PR template/body context (required)
- Authenticated `gh` environment (required)

## Output Specification

Structured PR output:

- Baseline mode: update `## Overview` and `## Changes`.
- Full-body mode: apply complete body via `--body-file`.
- `## Changes` must classify files (Config/Docs/Feature/Test/Other) with line counts.

See [references/common-output-format.md](references/common-output-format.md) for detailed format specification.

## Execution Scope

- **Always use `scripts/pr_body.sh` or `scripts/pr_fetch.sh`**. Do not run individual `gh` commands.
- `pr_body.sh` is deterministic and idempotent.
- Semantic completion belongs to Step 3, not shell scripts.
- **Do not use GitKraken MCP** unless explicitly requested

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [troubleshooting](references/common-troubleshooting.md)
- [classification](references/category-change-classification.md)
- [guidelines](references/category-pr-body-guidelines.md)
- [workflows](references/category-agent-workflows.md)
- [implementation](references/category-implementation-details.md)

## Workflow

1. Run `pr_fetch.sh` to collect PR metadata.
2. Run `pr_body.sh` to build deterministic baseline (`## Overview`, `## Changes`).
3. For full-body output, generate template-aligned content for remaining sections.
4. Apply full body with `pr_body.sh --body-file <FILE>`.

## Best Practices

- Always start with `pr_fetch.sh`, then `pr_body.sh`
- Avoid individual `gh` commands unless debugging.
