## Input Schema

Provided via prompt context by the calling workflow (loop-prompt-generate action).

```json
{
  "commit_range": "abc1234..def5678",
  "level": "L2",
  "skip": false,
  "hints": [
    {
      "kind": "duplication_block",
      "path": "scripts/example.sh",
      "detail": "lines 10-17 duplicate scripts/other.sh:40-47",
      "lines": 8
    }
  ]
}
```

| Field            | Type    | Description                                                                     |
| ---------------- | ------- | ------------------------------------------------------------------------------- |
| `commit_range`   | string  | SHA range when detect scope is `range`                                          |
| `level`          | enum    | Operating level: `L1` (report only), `L2` (edit + PR), `L3` (edit + auto-merge) |
| `skip`           | boolean | When true, no actionable hints                                                  |
| `hints`          | array   | Mechanical H1 hints from detect (may be empty)                                  |
| `hints[].kind`   | enum    | `duplication_block` or `oversized_unit` only                                    |
| `hints[].path`   | string  | Primary file path for the hint                                                  |
| `hints[].detail` | string  | Locator (line range, peer path, line count)                                     |
| `hints[].lines`  | number  | Optional size metric (duplicate block lines or file lines)                      |

`hints` may be an empty array. `level` defaults to `L2` when omitted by the workflow.

### Detect → hints pipeline

1. **`detect_refactor.sh`** emits mechanical facts: `hints[]`, `commit_range`, `skip`. Closed `kind` values only.
2. **`loop-prompt-generate`** passes detect JSON into the implementer prompt.
3. **This skill** selects one hint, applies structural `refactor` contract, and emits the session report.

### Operating levels

| Level | Agent behavior for loop-refactor                          |
| ----- | --------------------------------------------------------- |
| `L1`  | Emit session report only — do not edit files              |
| `L2`  | Emit report and apply one O1/O2 refactor within allowlist |
| `L3`  | Same edits as `L2`; caller may auto-merge the fix PR      |

Path allowlist and denylist are not JSON fields. They are injected in the implementer prompt `## Constraints` section from the caller (`LOOP_ALLOWLIST`, `LOOP_DENYLIST`). See [category-scope.md](category-scope.md).

Loop runs always use **structural intent** — never architecture-improvement / O3.
