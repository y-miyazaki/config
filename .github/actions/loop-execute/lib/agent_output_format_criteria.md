## Agent report output format (loop fix skills)

Applies when the implementer ran a loop fix skill (`docs-updater`, `refactor`, `ci-sweeper`, `changelog`, `tech-debt`).

Canonical shapes: repository `docs/explanation/loop-engineering/common-loop-triage-format.md`.

Resolve mode from **`may_edit`** and **`write_target`** in `## Constraints` (automation) or from the skill's interactive resolution — not from caller `level` or `delivery` metadata alone.

### Apply mode — `write_target: report`

When `write_target` is `report`, `### Changes` must include the `report_file` path when the branch diff is non-empty. Persisted report content may differ from PR Summary shape per skill references.

### Survey mode (`may_edit: false`)

When branch diff is empty and output has no `### Changes`, `### Deferred`, or `### Skipped`:

1. Contains `## Overview` and `## Summary`
2. `## Summary` includes `### Candidates` when actionable rows exist
3. **MUST NOT** include `### Changes`, `### Deferred`, `### Skipped`, or `## Verification`
4. Overview names dominant categories, files, or failure types — not counts alone

### Apply mode (`may_edit: true`)

When branch diff is non-empty or output includes `### Changes`, `### Deferred`, or `### Skipped`:

ALL of the following must be true:

1. Contains `## Overview`, `## Summary`, and `## Verification`
2. `## Summary` includes `### Changes` when files were modified
3. Deferred-style subsection when items were not fixed:
   - `docs-updater`, `refactor`, `ci-sweeper`, `tech-debt`: `### Deferred` (omit when empty)
   - `changelog`: `### Skipped` (omit when empty)
4. **Changes / Deferred consistency:** every path in the branch diff appears under `### Changes` and **no** deferred/skipped path appears in the branch diff
5. Overview names what was fixed or recorded — not counts alone
6. Verification lists checks the agent ran with pass/fail/skip/blocked
7. Branch diff MUST be empty for survey mode; non-empty diff requires apply mode

### Criteria for REJECT

ANY of the following triggers REJECT:

- Missing required headings for the resolved mode (survey vs apply)
- Survey output with non-empty branch diff, `## Verification`, `### Changes`, `### Deferred`, or `### Skipped`
- Apply output with `### Candidates` in final report
- Missing `### Changes` when files were modified
- Legacy sections: `### Fixes Applied`, `**Outcome:**`, `### Suggested next action`, top-level `## Changes`
- A path listed under Deferred/Skipped still appears in the branch diff
- A path in the branch diff is missing from the Changes table
- Internal-only jargon: bare `O1`/`O2`, `duplication_block` without plain-language explanation
- Overview is automation boilerplate or counts-only without naming substance
