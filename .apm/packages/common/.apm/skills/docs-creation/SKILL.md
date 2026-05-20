---
name: docs-creation
description: >-
  Create or update docs files with deterministic matching and templates.
  Use when creating or updating documentation skills.
  Use for specification, architecture, design, troubleshooting, and maintenance docs.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.8.4"
---

## Input

- Natural language request describing the topic/purpose (required)
- Extracted document type (required, must match one of the Document Types listed below)
- Extracted profile: `default`, `go`, or `terraform` (required)
- Optional target file under `docs/` (if omitted, automatically matched using deterministic logic)

### Internal Structured Input Schema (JSON)

Use this schema to validate the structured fields extracted from the natural language request. Do not require the user to author JSON directly.

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

If extracted structured input does not satisfy this schema, stop before write actions and return the schema plus a valid minimal JSON example in the report.

## USE FOR:

- Creating or updating docs under `docs/`
- Applying templates to specification, architecture, design, troubleshooting, and maintenance docs
- Generating `docs/index.md` entries for changed docs

## DO NOT USE FOR:

- Source code comments or docstrings
- Non-markdown assets
- Markdown linting or link checking

## Routing

- **UTILITY SKILL** for documentation creation and updates
- Natural-language prompt in, structured fields out
- Writes only markdown files under `docs/`

## Examples

- "Create an architecture doc for this repository"
- "Update troubleshooting for Terraform validation issues"

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
Always regenerate `docs/index.md` with relative links and one-line descriptions.

File rules: see [NC-02](references/common-checklist.md) and [DC-02](references/common-checklist.md).

## Execution Scope

- Ensure core docs exist; create missing ones, update existing ones.
- Resolve update/create deterministically and apply templates.
- Add valid docs links and update README docs index when markers exist.
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
- [templates](references/category-templates.md) (Read when using the default documentation template set)
- [go-templates](references/category-templates-go.md) (Read when the profile is `go`)
- [tf-templates](references/category-templates-terraform.md) (Read when the profile is `terraform`)

## Workflow

1. List markdown files in `docs/`.
2. If no target file provided, resolve using exact filename match; if no match, ask user for an explicit target file path.
3. Select template by profile: if profile is `go`, use `references/category-templates-go.md`; if `terraform`, use `references/category-templates-terraform.md`; else use `references/category-templates.md`.
4. Run case-insensitive duplicate check; duplicates must fail the run.
5. Create/update with naming/structure rules from [common-checklist.md](references/common-checklist.md) and valid relative links.
6. IF README has docs-index markers, update inside markers; ELSE skip.
7. Regenerate `docs/index.md` with a list of all files in `docs/` with relative links and one-line descriptions. Format:

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
