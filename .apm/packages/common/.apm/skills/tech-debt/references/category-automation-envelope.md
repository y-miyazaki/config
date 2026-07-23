## Automation Envelope

For LE workflow-driven runs. Load on the automation path — see [SKILL.md](../SKILL.md) Reference Files Guide.

### Constraints

The caller injects `## Constraints` after detect JSON via `loop-prompt-generate`. The agent reads:

| Field           | Type    | Description                                                                                                                         |
| --------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `may_edit`      | boolean | `false` — survey shape only; do not write `report_file`. `true` — write `report_file`, apply closed-set fixes, and emit apply shape |
| `Allowed paths` | string  | Optional allowlist globs (`LOOP_ALLOWLIST`)                                                                                         |

`loop-prompt-generate` maps `level` to `may_edit` (`L1` → `false`; `L2`/`L3` → `true`). The skill branches on `may_edit` only — do not interpret `level`.

Denylist is enforced by the loop verifier — see [category-scope.md](category-scope.md).

Example:

```text
## Constraints
may_edit: false
Allowed paths: docs/report/tech-debt/**/*.md, docs/**/*.md
```

### PR body synthesis

Use [common-output-format.md](common-output-format.md) for report shape. At synthesis, load:

| `may_edit` | Template                            |
| ---------- | ----------------------------------- |
| `false`    | `assets/pr-body-template-survey.md` |
| `true`     | `assets/pr-body-template.md`        |

PR body rules:

- Top-level `## Overview`, `## Summary`, and `## Verification` (apply only) — match the apply/survey templates in `assets/`
- Under Summary use `### Candidates` or `### Changes`; use `### Deferred` for this skill (not `### Skipped`)
- **Overview contract:** 1–2 sentences (max ~280 characters) — trigger → substance → action; name signal kinds and report sections; omit level, SHAs, run URLs, and boilerplate
- **List vs table:** one item → bullet list; two or more rows or multiple columns → markdown table; omit empty `###` headings
- **Summary content to omit:** `**Outcome:**` one-liners, `### Suggested next action`, top-level `## Changes`, `### Validation` inside Summary (use `## Verification`)
- Reconcile `### Changes` and `### Deferred` with `git diff --name-only` before synthesis — a path MUST NOT appear in both; every path in `git diff` MUST appear in **Changes**; revert edits to deferred paths before synthesis

`loop-finalize` extracts Overview and Summary from the agent report.

### Session metrics (verifier / logs)

After survey or apply work, append:

```markdown
## Session Metrics

| Field | Value |
| may_edit | <true\|false> |
| Commit range | <commit_range> |
| Signals assessed | <count> |
| Hotspots assessed | <count> |
| Report file | <report_file or "None"> |
| Outcome | <one-line result> |
```

Optional caller metadata (`level`, run id) may be appended when supplied — do not branch behavior on it.
