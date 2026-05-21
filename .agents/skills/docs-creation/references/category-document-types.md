# `document_type` Mapping

Use this mapping to resolve `document_type` to the default target file under `docs/`.
If a user provides `target_file`, prioritize that explicit path after schema validation.

## Core Types

| document_type       | Default file               | Purpose                                           | Required (minimum sections)                                        |
| ------------------- | -------------------------- | ------------------------------------------------- | ------------------------------------------------------------------ |
| `specification`     | `docs/specification.md`    | Record behavioral requirements and expected flows | H1, feature/behavior sections, configuration defaults (if present) |
| `architecture`      | `docs/architecture.md`     | Explain system structure and boundaries           | H1, Overview, System/Component Structure, Key Design Decisions     |
| `design`            | `docs/design.md`           | Describe module-level implementation design       | H1, Design Scope, Data/Config Design, Implementation Details       |
| `design-decisions`  | `docs/design-decisions.md` | Track major decisions and rejected alternatives   | H1, Decision, Rationale, Alternatives Rejected                     |
| `troubleshooting`   | `docs/troubleshooting.md`  | Provide issue diagnostics and recovery steps      | H1, Symptoms, Root Cause, Resolution, Prevention (if applicable)   |
| `general`           | no fixed file (ask user)   | Capture documentation outside predefined types    | H1 and purpose-aligned sections based on selected template         |

## Extension Types

| document_type        | Default file                | Purpose                                            | Required (minimum sections)                                             |
| -------------------- | --------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------- |
| `module-catalog`     | `docs/module-catalog.md`    | Catalog modules with key inputs/outputs            | H1, Module Inventory, Inputs/Outputs, Notes                             |
| `monitoring`         | `docs/monitoring.md`        | Define alerts, dashboards, and operational runbook | H1, Monitoring Scope, Alerts, Dashboards, Runbook                       |
| `performance`        | `docs/performance.md`       | Record bottlenecks, benchmarks, and tuning actions | H1, Baseline, Findings, Optimization Plan                               |
| `security-coverage`  | `docs/security-coverage.md` | Summarize security control and service coverage    | H1, Coverage Matrix, Gaps/Out-of-Scope, Follow-up                       |
| `maintenance-notes`  | `docs/maintenance-notes.md` | Capture periodic operations and maintenance history| H1, Periodic Tasks, Known Quirks, Change Log                            |
| `improvements`       | `docs/improvements.md`      | Track planned and completed improvement work       | H1, Backlog/Planned Items, Completed Items, Next Actions                |
