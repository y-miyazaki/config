## Agent report output format (loop fix skills)

Applies when the implementer ran a loop fix skill (`docs-updater`, `refactor`, `ci-sweeper`, `changelog`, `report-tech-debt`).

### Criteria for APPROVE (report sections)

ALL of the following must be true in the implementer's final `agent-output.txt`:

1. Contains `## Overview`, `## Summary`, and `## Verification` headings
2. `## Summary` includes the skill's primary fix subsection:
   - `docs-updater`, `refactor`, `ci-sweeper`: `### Changes`
   - `changelog`: `### Changes`
   - `report-tech-debt`: `### Report`
3. Deferred-style subsection when items were not fixed:
   - `docs-updater`, `refactor`, `ci-sweeper`: `### Deferred` (omit when empty)
   - `changelog`: `### Skipped` (omit when empty)
   - `report-tech-debt`: `### Watch` (omit when empty)
4. **Changes / Deferred consistency:** every path in the branch diff appears under `### Changes` (or `### Report` for tech-debt) and **no** deferred/skipped/watch path appears in the branch diff
5. Overview is 1–2 sentences of plain language (trigger → problem → action), not automation boilerplate
6. Verification lists checks the agent ran with pass/fail/skip/blocked — not instructions for the human to run later

### Criteria for REJECT (report sections)

ANY of the following triggers REJECT:

- Missing `## Overview`, `## Summary`, or `## Verification`
- Missing required `### Changes` / `### Report` when files were modified
- Legacy or redundant sections: `### Fixes Applied`, `**Outcome:**`, `### Suggested next action`, top-level `## Changes` in agent output
- A path listed under Deferred/Skipped/Watch still appears in the branch diff
- A path in the branch diff is missing from the Changes/Report table
- Internal-only jargon in user-facing tables: bare `O1`/`O2`, `duplication_block` without plain-language explanation
