# CLAUDE.md

Behavioral rules for `docs/report/**`. Directory-scoped maintainer rules, hand-authored and repo-owned.

Evaluation criteria for comparison documents: [tool-comparison-evaluation-rules](tool-comparison/tool-comparison-evaluation-rules.md) and [service-comparison-evaluation-rules](aws/service-comparison/service-comparison-evaluation-rules.md).

---

## History table (MUST)

Applies to every `## History` section in `docs/report/**`.

| Rule        | Requirement                                                                         |
| ----------- | ----------------------------------------------------------------------------------- |
| Columns     | `日付` (`YYYY-MM-DD`) and `内容`                                                    |
| Order       | Newest first. Insert a new row directly under the table header, never at the bottom |
| Same-day    | Put the row added later above the earlier row                                       |
| Initial row | The `初版作成` row stays at the bottom                                              |
| Content     | One row per update. State what changed and what was verified; mark unverified items |

## Guidelines template (MUST)

Applies to the `## Guidelines` section of every comparison document (`tool-comparison-matrix*.md`, `service-comparison-*.md`).

Include the following items:

- 選定方針: 「何を優先して選ぶか」
- 採用条件: 「どの条件なら採用するか」
- 不採用条件: 「どの条件なら採用しないか」
- 併用条件: 「単体でなく併用する条件」
- 更新条件: 「いつ再評価するか」
