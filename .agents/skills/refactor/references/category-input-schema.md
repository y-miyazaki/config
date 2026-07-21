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
