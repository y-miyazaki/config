# Document Types

Use this mapping to resolve `document_type` to the default target file under `docs/`.
If a user provides `target_file`, prioritize that explicit path after schema validation.

## Core Types

| document_type       | Default file               |
| ------------------- | -------------------------- |
| `specification`     | `docs/specification.md`    |
| `architecture`      | `docs/architecture.md`     |
| `design`            | `docs/design.md`           |
| `design_decisions`  | `docs/design_decisions.md` |
| `troubleshooting`   | `docs/troubleshooting.md`  |
| `general`           | no fixed file (ask user)   |

## Extension Types

| document_type        | Default file                 |
| -------------------- | ---------------------------- |
| `module_catalog`     | `docs/module_catalog.md`     |
| `monitoring`         | `docs/monitoring.md`         |
| `performance`        | `docs/performance.md`        |
| `security_coverage`  | `docs/security_coverage.md`  |
| `maintenance_notes`  | `docs/maintenance_notes.md`  |
| `improvements`       | `docs/improvements.md`       |
