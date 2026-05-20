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
- Document type (required, must match one of the Document Types listed below)
- Profile: `default`, `go`, or `terraform` (required)
- Optional target file under `docs/` (if omitted, automatically matched using deterministic logic)

### Input Schema (JSON)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "topic": {
      "type": "string",
      "minLength": 3
    },
    "document_type": {
      "type": "string",
      "enum": ["specification", "architecture", "design", "design_decisions", "troubleshooting", "general", "module_catalog", "monitoring", "performance", "security_coverage", "maintenance_notes", "improvements"]
    },
    "profile": {
      "type": "string",
      "enum": ["default", "go", "terraform"]
    },
    "target_file": {
      "type": "string",
      "pattern": "^docs/[a-z0-9_]+\\.md$"
    }
  },
  "required": ["topic", "document_type", "profile"]
}
```

If input does not satisfy this schema, stop before write actions and return the schema plus a valid minimal JSON example in the report.

## Document Types

### Core Types

| Type               | File                       | Description                                                                      |
| ------------------ | -------------------------- | -------------------------------------------------------------------------------- |
| `specification`    | `docs/specification.md`    | Behavioral specifications present in implementation but not elsewhere documented |
| `architecture`     | `docs/architecture.md`     | System-wide structure, component relationships, and account layout               |
| `design`           | `docs/design.md`           | Module-level internal design, variable design, and naming conventions            |
| `design_decisions` | `docs/design_decisions.md` | Key decisions with rationale and rejected alternatives                           |
| `troubleshooting`  | `docs/troubleshooting.md`  | Common issues, root causes, and resolutions                                      |
| `general`          | (any)                      | Catch-all for documents that do not fit other types                              |

### Extension Types

| Type                | File                        | Description                                           |
| ------------------- | --------------------------- | ----------------------------------------------------- |
| `module_catalog`    | `docs/module_catalog.md`    | Index of modules with purpose, inputs, and outputs    |
| `monitoring`        | `docs/monitoring.md`        | Alerts, dashboards, and runbooks                      |
| `performance`       | `docs/performance.md`       | Benchmarks, bottlenecks, and tuning guidance          |
| `security_coverage` | `docs/security_coverage.md` | Security service coverage matrix                      |
| `maintenance_notes` | `docs/maintenance_notes.md` | Periodic tasks, known quirks, and maintenance history |
| `improvements`      | `docs/improvements.md`      | Planned and completed improvements                    |

## Output Specification

Create or update markdown files under `docs/`, then return a report using [references/common-output-format.md](references/common-output-format.md).
Report must include changed file paths and duplicate-check result.
Generate or update `docs/index.md` listing all generated files with relative links and one-line content descriptions.

File rules: see [NC-02](references/common-checklist.md) and [DC-02](references/common-checklist.md).

## Execution Scope

- Ensure core docs exist; create missing ones, update existing ones.
- Resolve update/create deterministically and apply templates.
- Add valid docs links and conditionally update README docs index.
- Do not rename/delete files, add YAML frontmatter, or run markdown linting.

### USE FOR:

- create new documentation files under `docs/`
- update existing docs with template-aligned structure
- maintain README docs index entries linked to `docs/`

### DO NOT USE FOR:

- edit inline code comments or source-code docstrings
- rewrite non-markdown assets
- run markdown lint or link checker as part of this skill

## Reference Files Guide

- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [templates](references/category-templates.md)
- [go-templates](references/category-templates-go.md)
- [tf-templates](references/category-templates-terraform.md)

## Workflow

1. List markdown files in `docs/`.
2. If no target file provided, resolve using exact filename match; if no match, fail and ask user to provide explicit target file path.
3. Select template by profile: if profile is `go`, use `references/category-templates-go.md`; if `terraform`, use `references/category-templates-terraform.md`; else use `references/category-templates.md`.
4. Run case-insensitive duplicate check; duplicates must fail the run.
5. Create/update with naming/structure rules from [common-checklist.md](references/common-checklist.md) and valid relative links.
6. IF README has docs-index markers, update inside markers; ELSE skip.
7. **Always** regenerate `docs/index.md` with a list of all files in `docs/` with relative links and one-line descriptions. Format:

```markdown
# Documentation Index

- [specification.md](specification.md) - Repository specification and structure
- [architecture.md](architecture.md) - System architecture overview
```

8. Return report using [references/common-output-format.md](references/common-output-format.md).

## Error Handling and Troubleshooting

- If input JSON schema validation fails, return `status: failed` and include the schema plus a valid minimal JSON example.
- If `docs/` does not exist, create `docs/` first and continue.
- If selected template file is missing, fall back to `general` template and record fallback in report.
- If duplicate check fails, return `status: failed` and stop before write actions.
- If README markers are malformed, skip marker update and report as deferred with reason.

## Best Practices

- Run NC-01 duplicate checks before write actions.
- Keep H1 titles in `docs/`.
