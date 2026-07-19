# loop-tech-debt Checklist

## Classification

Read [category-debt-taxonomy.md](category-debt-taxonomy.md) first. For each signal/hotspot:

1. Assign one primary `category` using the decision order in the taxonomy
2. Assign severity → report section (Critical / High-Priority / Watch / Noise)
3. Add `nature` only when Fowler quadrant evidence is clear

## Detect vs lint

Classify detect facts only. Do not duplicate linter/SAST territory (complexity, style, unused, naming). Markers (`todo_comment`, `fixme`, `hack`, `xxx`) are secondary — default to Watch unless systemic.

## Out of scope

Report EOL/deprecation facts; do not recommend new-technology or tool migration playbooks.

## Scope Guards

- Write only paths in the prompt `## Constraints` allowlist; never touch denylist paths (see `category-scope.md`)
- Read source outside the allowlist for evidence only — never edit it
- Cap Critical + High-Priority persisted findings at 25; defer overflow to Watch with a truncation note
- Do not invent APIs, paths, metrics, ownership, or CVEs

## Evidence Rules

- Cite `path` + `line` (or hotspot metric) from detect facts
- Read ±30 lines around each signal before classifying
- Compare against `previous_report` when present: mark resolved, recurring, or new
- Prefer taxonomy source language in `Reason` (e.g. "maintainability / complexity", "version lock", "wrong Diátaxis form")

## Output

- Emit the session summary sections per `common-output-format.md`
- Include `Category` (and `Nature` when set) on every Critical / High-Priority / Watch item
- At `L2`/`L3`, also write the persisted report file per `common-output-format.md#persisted-report-file`

## Error Handling

| Condition                                                    | Severity    | Action                                                                                                     |
| ------------------------------------------------------------ | ----------- | ---------------------------------------------------------------------------------------------------------- |
| `skip` true, or both `signals` and `hotspots` empty          | recoverable | Emit full session summary; Outcome `No technical debt signals detected`; do not create `report_file`; stop |
| Evidence `path` missing or unreadable                        | recoverable | Classify as Watch with reason; continue other items                                                        |
| `previous_report` set but file missing                       | recoverable | Proceed without resolved/regression notes; note absence in Summary                                         |
| `report_file` outside allowlist or on denylist               | blocking    | Do not write any report file; note in Summary; still emit session summary                                  |
| Finding would require invented APIs, paths, metrics, or CVEs | fatal       | Omit the finding (or Noise / Ignore); never fabricate evidence                                             |

## Examples

| Signal                                                 | Category                         | Section                   |
| ------------------------------------------------------ | -------------------------------- | ------------------------- |
| `TODO: extract shared validator` with clear call sites | `code_quality`                   | High-Priority             |
| `go.mod` pin on EOL major blocking upgrades            | `dependency_version`             | High-Priority or Critical |
| README still points at deleted workflow                | `documentation`                  | High-Priority             |
| Hardcoded secret-like token in sample config           | `security`                       | Critical (report only)    |
| High churn file, no concrete defect                    | `code_quality` or `architecture` | Watch                     |
| `TODO: maybe later` with no actionable path            | —                                | Noise / Ignore            |
