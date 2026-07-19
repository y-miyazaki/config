## Input Schema

Provided via prompt context by the calling workflow (loop-prompt-generate action). Detect (`detect_tech_debt.sh`) scans the **full repository** by default (`scope=all`); git range is caller metadata only and does not narrow sensors.

```json
{
  "commit_range": "abc1234..def5678",
  "level": "L2",
  "report_file": "docs/report/tech-debt/2026-07-19.md",
  "previous_report": "docs/report/tech-debt/2026-07-12.md",
  "skip": false,
  "warnings": ["docs link sensor skipped: node not available"],
  "signals": [
    {
      "kind": "todo_comment",
      "path": "src/service.go",
      "line": 42,
      "snippet": "TODO: extract shared validator",
      "source": "git_grep",
      "hint": "code_quality"
    }
  ],
  "hotspots": [
    {
      "path": "scripts/deploy.sh",
      "metric": "churn",
      "value": 18,
      "window": "90d"
    }
  ]
}
```

| Field               | Type    | Description                                                                                                          |
| ------------------- | ------- | -------------------------------------------------------------------------------------------------------------------- |
| `commit_range`      | string  | SHA range that triggered detection                                                                                   |
| `level`             | enum    | Operating level: `L1` (report only), `L2` (write report + PR), `L3` (edit + auto-merge)                              |
| `report_file`       | string  | Repository-relative path for the persisted report (`docs/report/tech-debt/YYYY-MM-DD.md`)                            |
| `previous_report`   | string  | Optional path to the prior dated report (empty when none)                                                            |
| `skip`              | boolean | When true, no debt signals or hotspots detected                                                                      |
| `warnings`          | array   | Optional strings from detect (per-sensor recoverable failures, truncation, skipped sensors); caller may pass through |
| `signals`           | array   | Mechanical debt facts from detect (may be empty)                                                                     |
| `signals[].kind`    | enum    | Closed set — see table below                                                                                         |
| `signals[].path`    | string  | File path containing the signal                                                                                      |
| `signals[].line`    | number  | 1-based line number                                                                                                  |
| `signals[].snippet` | string  | Short evidence text from the source line                                                                             |
| `signals[].source`  | string  | Detection method (`git_grep`, `go_mod`, `package_json`, `markdown_link_check`, `git_log`, `mtime`)                   |
| `signals[].hint`    | string  | Optional detect hint toward a taxonomy category (agent still decides)                                                |
| `hotspots`          | array   | Aggregate churn candidates (may be empty)                                                                            |
| `hotspots[].path`   | string  | File path                                                                                                            |
| `hotspots[].metric` | string  | Metric name (`churn`)                                                                                                |
| `hotspots[].value`  | number  | Metric value                                                                                                         |
| `hotspots[].window` | string  | Observation window (e.g. `90d`)                                                                                      |

### Closed `signals[].kind` set

Detect emits only these kinds. Unexpected kinds → classify as Watch or Noise.

| Kind             | Sensor role | Typical `source`      |
| ---------------- | ----------- | --------------------- |
| `todo_comment`   | Secondary   | `git_grep`            |
| `fixme`          | Secondary   | `git_grep`            |
| `hack`           | Secondary   | `git_grep`            |
| `xxx`            | Secondary   | `git_grep`            |
| `pin_drift`      | Core        | `package_json`        |
| `version_range`  | Core        | `package_json`        |
| `eol_hint`       | Core        | `go_mod`              |
| `broken_doc_ref` | Core        | `markdown_link_check` |
| `stale_doc`      | Core        | `git_log` or `mtime`  |

**Marker kinds** (`todo_comment`, `fixme`, `hack`, `xxx`) are secondary enrichment — default toward Watch unless systemic. Core sensors cover dependency manifests, docs links/staleness, and churn hotspots.

`signals` and `hotspots` may be empty arrays. `level` defaults to `L2` when omitted by the workflow.

Path allowlist and denylist are not JSON fields. They are injected in the implementer prompt `## Constraints` section from the caller (`LOOP_ALLOWLIST`, `LOOP_DENYLIST`). See [category-scope.md](category-scope.md).
