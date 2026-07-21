# loop-refactor Checklist

## Hint selection

- Process **one** hint per run — first actionable entry in `hints[]`
- Closed kinds only: `duplication_block`, `oversized_unit`
- Map hint to `refactor` structural path; force `intent: structural`
- Architecture-improvement language → Watch / no-op in this loop (use interactive `refactor` skill)

## Operations (O1/O2 only)

- Deduplicate, clarify, extract/inline, shallow same-package move
- No cross-package redesign, GoF introduction, or public API semantics changes
- No lint/style-only mission; lint may run as part of stack gate only
- Do not read `docs/report/report-tech-debt/**` as required input

## Scope guards

- Edit only paths in prompt `## Constraints` allowlist
- More than five files changed without clear necessity → Watch / defer remainder
- Unsupported stack → Watch — do not invent tests

## Verification

- Establish characterization / stack gate before or with edit (caller `## Instructions` / A')
- O2 without adequate gate → downgrade to O1 or Watch
- Run named validation skills from `## Instructions` after edit

## Output

- Emit all session report sections per `common-output-format.md`
- Record selected hint under **Target**
- Emit PR `## Overview` and `## Summary` after session report

## Error handling

- `skip` true or empty `hints` → Outcome `no-op`; stop
- Validation fails after one in-scope repair → revert or Watch
- Hint path outside allowlist → Watch / no-op
