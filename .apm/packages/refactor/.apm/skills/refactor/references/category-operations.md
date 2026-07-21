## Allowed operations (depth tiers)

This skill uses short labels **O1 / O2 / O3** for how deep a change may go. They are **not** Big-O complexity and not industry-standard names — only this skill's depth tiers. Users do **not** pass `max_tier: O3`; classify **intent** from natural language first.

| Label  | Plain meaning                          | Typical edits                                                                                         |
| ------ | -------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| **O1** | Local structure, same behavior         | Deduplicate; clarify expression; extract/inline in place; remove dead code when equivalence is proven |
| **O2** | O1 + shallow same-package move         | Move within one package/module; fix imports/wiring for that move                                      |
| **O3** | Architecture improvement (interactive) | Phase A proposal; Phase B one approved O2 slice — not one-shot cross-boundary apply                   |

Closed set for apply: O1/O2 only. O3 is proposal-first, then O2 slices after user approval.

## Intent classification (before edits)

| Intent           | When to use                                                                                        | Path                                    |
| ---------------- | -------------------------------------------------------------------------------------------------- | --------------------------------------- |
| **structural**   | Dedupe, extract, clarify, shallow move; default when ambiguous                                     | O1/O2 apply workflow                    |
| **architecture** | User mission is module boundary, deep module, redesign, responsibility split, testability at seams | Phase A → approval → Phase B (O2 slice) |

### Architecture-improvement triggers (examples)

- EN: architecture improvement, redesign, module boundary, deep module, consolidate modules, improve testability at seams, responsibility split
- JA: アーキテクチャ改善, 設計見直し, モジュール整理, 境界の見直し, 責務分離, 深いモジュール化, テストしやすい構造に

When triggers are mixed with structural work, prefer **structural** unless architecture language is the primary mission.

### O1 — local structure (same behavior)

Allowed:

- Deduplicate repeated logic
- Clarify expression without API or behavior change
- Extract or inline function/module within existing boundaries
- Remove dead branch when behavior equivalence is proven

Forbidden:

- Feature changes
- Public API semantics changes
- Dependency upgrades / CVE-driven edits as the mission

### O2 — same-package move (plus O1)

Allowed:

- Everything in O1
- Shallow move within the **same** package/module boundary
- Import and wiring cleanup required by that move

Forbidden on L2 / automation path:

- Cross-package redesign
- New design patterns (GoF) or deep-module redesign (**O3**)
- Large boundary splits

### O3 — architecture improvement (interactive only)

**Phase A (default for architecture intent):**

- Explore the target area; emit a deepening proposal in the session report
- Include: problem, candidate slices, phased plan, risks, suggested verification
- Outcome `proposal` — no cross-boundary apply; no multi-file redesign in one run

**Phase B (after explicit user approval of one slice):**

- User names **one** approved slice from the proposal
- Run the structural path for that slice only — **O2 cap**
- Same verification and validation gates as structural intent

**Never on loop L2:** loop callers and detect hints stay structural (O1/O2) only.
