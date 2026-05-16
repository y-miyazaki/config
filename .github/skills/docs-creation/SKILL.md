---
name: docs-creation
description: >-
  Create or update docs files with deterministic matching and templates.
  Use for specification, architecture, design, troubleshooting, and maintenance docs.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.8.4"
---

## Input

- Topic/purpose (required)
- Optional target file under `docs/` and baseline mode (`initial-only` or `always`)

## Output Specification

Create or update markdown files under `docs/`, then return a report using [references/common-output-format.md](references/common-output-format.md).

File rules:

- lowercase underscore `.md` filename
- no YAML frontmatter
- H1 title, purpose paragraph, H2 sections

## Execution Scope

- Ensure baseline docs by mode.
- Resolve update/create deterministically and apply templates.
- Add valid docs links and conditionally update README docs index.
- Do not rename/delete files, add YAML frontmatter, or run markdown linting.

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [templates](references/category-templates.md)
- [go-templates](references/category-templates-go.md)
- [tf-templates](references/category-templates-terraform.md)

## Workflow

1. List markdown files in `docs/`; resolve baseline mode (`initial-only` by default).
2. Apply baseline: `initial-only` creates missing core docs only when `docs/` has no markdown; `always` creates missing core docs every run.
3. Choose template by profile (`Terraform > Go > default`, fallback `general`).
4. Resolve target: explicit path; else canonical filename, normalized H1, weighted score (`f*3+h1*2+p*1`, min 2), then lexicographically smallest path.
5. Run case-insensitive duplicate check; duplicates must fail the run.
6. Create/update with naming/structure rules and valid relative links.
7. IF README has docs-index markers update inside markers; ELSE IF docs section has docs links append there; ELSE skip.
8. Return report using [references/common-output-format.md](references/common-output-format.md).

## Best Practices

- Run NC-01 duplicate checks before write actions.
- Keep H1 titles in `docs/`.
