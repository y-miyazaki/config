## Input Schema

Interactive runs may pass free-form path/symbol in the user prompt. When structured JSON is present (interactive helper or future loop envelope), parse:

```json
{
  "target": "path/or/symbol",
  "hint": {
    "kind": "duplication_block",
    "path": "scripts/example.sh",
    "detail": "optional locator"
  },
  "allowlist": [".apm/packages/**", "scripts/**"],
  "denylist": ["docs/report/**"],
  "intent": "structural",
  "approved_slice": "optional — one slice from Phase A proposal for architecture Phase B",
  "constraints": {
    "max_tier": "O2"
  }
}
```

| Field                  | Type                           | Description                                                                                           |
| ---------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `target`               | string                         | Single path or symbol; required when no `hint.path`                                                   |
| `hint`                 | object                         | Optional structure hint (future detect H1 shapes)                                                     |
| `hint.kind`            | string                         | `duplication_block` or `oversized_unit` only                                                          |
| `hint.path`            | string                         | Path associated with the hint                                                                         |
| `hint.detail`          | string                         | Optional locator (range, symbol name)                                                                 |
| `allowlist`            | string[]                       | Optional path globs; intersect with defaults                                                          |
| `denylist`             | string[]                       | Optional path globs; union with defaults                                                              |
| `intent`               | `structural` \| `architecture` | Agent-classified from user language; default `structural`                                             |
| `approved_slice`       | string                         | One slice from Phase A proposal; required for architecture Phase B apply                              |
| `constraints.max_tier` | `O1` \| `O2`                   | Loop/tool depth cap only (`O1` local, `O2` same-package). Not the interactive O3 entry. Default `O2`. |

### Rules

- If neither actionable `target` nor `hint` → no-op
- `hint.kind` values outside the closed set → ignore hint; fall back to `target` or no-op
- Classify `intent` from user natural language ([category-operations.md](category-operations.md)); do not require users to pass `max_tier: O3`
- Architecture intent without `approved_slice` → Phase A proposal only; Outcome `proposal`
- Architecture Phase B requires `approved_slice` and runs structural apply (O2 cap) for that slice only
- Loop envelope: `intent` is always `structural`; `constraints.max_tier` is `O1` or `O2` only
- Do **not** accept tech-debt report file paths as required input fields in v1
- Stack skill names are **not** schema fields — they arrive under `## Instructions` (A')

## Loop envelope (caller JSON)

When `hints[]` is present (from `loop-prompt-generate` / `detect_refactor.sh`):

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
| `level`          | enum    | `L1` (report only), `L2` (edit + PR), `L3` (edit + auto-merge)                   |
| `skip`           | boolean | When true, no actionable hints                                                  |
| `hints`          | array   | Mechanical H1 hints from detect                                                 |
| `hints[].kind`   | enum    | `duplication_block` or `oversized_unit` only                                    |
| `hints[].path`   | string  | Primary file path for the hint                                                  |
| `hints[].detail` | string  | Locator (line range, peer path, line count)                                     |
| `hints[].lines`  | number  | Optional size metric                                                            |

### Operating levels

| Level | Agent behavior for refactor (loop path)                    |
| ----- | ---------------------------------------------------------- |
| `L1`  | Emit session report only — do not edit files               |
| `L2`  | Emit report and apply one structural hint within allowlist |
| `L3`  | Same edits as `L2`; caller may auto-merge the fix PR       |

### Loop rules

- Select **one** hint — first actionable entry in `hints[]`. Force `intent: structural`; `constraints.max_tier: O2`.
- Allowlist/denylist arrive in prompt `## Constraints` (`LOOP_ALLOWLIST`, `LOOP_DENYLIST`); fall back to [category-scope.md](category-scope.md) defaults when absent.
- Session report per [common-output-format-loop.md](common-output-format-loop.md).
- `level` defaults to `L2` when omitted.

