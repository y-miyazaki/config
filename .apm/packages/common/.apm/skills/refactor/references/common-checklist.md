# Refactor Checklist

## Intent classification

- Classify **structural** (default) or **architecture-improvement** before edits ([category-operations.md](category-operations.md))
- Architecture triggers: architecture improvement, redesign, module boundary, deep module, responsibility split, testability at seams
- When ambiguous → **structural**
- Architecture intent without user-approved slice → Phase A proposal only; Outcome `proposal`; no apply
- Architecture Phase B → user names **one** approved slice; apply as O2 cap only
- Do not require users to pass `max_tier: O3` or bare O3 labels

## Target selection

- Exactly **one** target (path or symbol) per run
- Prefer structure-driven evidence (duplication, oversized unit, user-named symbol) — not lint/SAST smell scores
- If the user mission is lint/style-only (shellcheck rename/quote, gofmt-only) or feature/API change → Watch / no-op; do not apply
- Do not require or read `docs/report/report-tech-debt/**`

## Operations

- Pick **one** technique from [category-techniques.md](category-techniques.md) before editing; record it in session report **Technique**
- Treat `duplication_block` as **logic duplication** — dedupe executable/shared logic (extract helper, consolidate calls), not documentation or comment-only templates
- If overlapping text is comments or doc blocks only, Outcome `no-op` / Watch — not an apply target
- When deduplicating logic, preserve file headers and symbol documentation unless consolidating documented behavior in the same edit
- Do not invent a dedicated SubAgent product; reuse platform Implementer/Verifier and existing validation skills via caller `## Instructions` (A')
- Stay in closed depth tiers O1/O2 for apply ([category-operations.md](category-operations.md)): **O1** = local structure same behavior; **O2** = plus shallow same-package move
- No public API semantics changes; no feature behavior changes
- No one-shot cross-boundary apply or GoF introduction — architecture path is propose → approve → one O2 slice
- Loop L2: structural intent only; no architecture Phase A/B

## Verification

- Establish characterization / stack gate before or with the edit ([category-verification.md](category-verification.md))
- Architecture Phase A: skip apply and stack validation — proposal only
- If a same-package move (O2) lacks an adequate gate → downgrade to local-only (O1) or Watch (V4)
- Unsupported language → Watch / skip — do not invent tests for an unknown stack
- Lint tools may run as part of a stack gate; lint-only findings must not expand the target

## Output

- Emit all session report sections per [common-output-format.md](common-output-format.md)
- Record **Intent** in session report (`structural` or `architecture-improvement`)
- Tier fields use plain-language depth labels (`O1 local structure`, `O2 same-package move`, `none`) — not bare `O1`/`O2`
- Architecture Phase A: fill **Architecture Proposal** section; Outcome `proposal`
- Do not claim validation passed when commands failed or were not run

## Error handling

- Nothing actionable → Outcome `no-op`, empty Applied Change, stop
- Validation fails after one in-scope repair → revert or leave Watch; record failure
- Missing validation tooling named in Instructions → note in Session Metrics; Watch unless a single safe local (O1) clarification remains gated by existing tests

