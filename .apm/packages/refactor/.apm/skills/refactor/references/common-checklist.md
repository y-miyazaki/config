# Refactor Checklist

## Target selection

- Exactly **one** target (path or symbol) per run
- Prefer structure-driven evidence (duplication, oversized unit, user-named symbol) — not lint/SAST smell scores
- If the user mission is lint/style-only (shellcheck rename/quote, gofmt-only) or feature/API change → Watch / no-op; do not apply
- Do not require or read `docs/report/report-tech-debt/**`

## Operations

- Do not invent a dedicated SubAgent product; reuse platform Implementer/Verifier and existing validation skills via caller `## Instructions` (A')
- Stay in closed depth tiers O1/O2 ([category-operations.md](category-operations.md)): **O1** = local structure same behavior; **O2** = plus shallow same-package move
- No public API semantics changes; no feature behavior changes
- **O3** deep redesign / GoF / large boundary splits → Watch / stop — not this skill's automation path

## Verification

- Establish characterization / stack gate before or with the edit ([category-verification.md](category-verification.md))
- If a same-package move (O2) lacks an adequate gate → downgrade to local-only (O1) or Watch (V4)
- Unsupported language → Watch / skip — do not invent tests for an unknown stack
- Lint tools may run as part of a stack gate; lint-only findings must not expand the target

## Output

- Emit all session report sections per [common-output-format.md](common-output-format.md)
- Tier fields use plain-language depth labels (`O1 local structure`, `O2 same-package move`, `none`) — not bare `O1`/`O2`
- Do not claim validation passed when commands failed or were not run

## Error handling

- Nothing actionable → Outcome `no-op`, empty Applied Change, stop
- Validation fails after one in-scope repair → revert or leave Watch; record failure
- Missing validation tooling named in Instructions → note in Session Metrics; Watch unless a single safe local (O1) clarification remains gated by existing tests
