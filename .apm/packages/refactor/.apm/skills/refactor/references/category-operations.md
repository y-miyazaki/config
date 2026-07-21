## Allowed operations (depth tiers)

This skill uses short labels **O1 / O2 / O3** for how deep a change may go. They are **not** Big-O complexity and not industry-standard names — only this skill's depth tiers.

| Label  | Plain meaning                     | Typical edits                                                                                         |
| ------ | --------------------------------- | ----------------------------------------------------------------------------------------------------- |
| **O1** | Local structure, same behavior    | Deduplicate; clarify expression; extract/inline in place; remove dead code when equivalence is proven |
| **O2** | O1 + shallow same-package move    | Move within one package/module; fix imports/wiring for that move                                      |
| **O3** | Deep redesign (out of automation) | Cross-package splits, GoF/patterns, architecture/schema migration — Watch only                        |

Closed set: anything outside O1/O2 → Watch / stop.

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

### O3 — deep redesign (not this skill's automation path)

Deep-module redesign, GoF introduction, schema/architecture migration — interactive/human only; emit Watch, do not apply under loop L2 expectations.
