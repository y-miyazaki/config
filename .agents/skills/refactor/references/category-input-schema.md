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
  "constraints": {
    "max_tier": "O2"
  }
}
```

| Field                  | Type         | Description                                                        |
| ---------------------- | ------------ | ------------------------------------------------------------------ |
| `target`               | string       | Single path or symbol; required when no `hint.path`                |
| `hint`                 | object       | Optional structure hint (future detect H1 shapes)                  |
| `hint.kind`            | string       | `duplication_block` or `oversized_unit` only                       |
| `hint.path`            | string       | Path associated with the hint                                      |
| `hint.detail`          | string       | Optional locator (range, symbol name)                              |
| `allowlist`            | string[]     | Optional path globs; intersect with defaults                       |
| `denylist`             | string[]     | Optional path globs; union with defaults                           |
| `constraints.max_tier` | `O1` \| `O2` | Cap depth: O1=local structure, O2=same-package move (default `O2`) |

### Rules

- If neither actionable `target` nor `hint` → no-op
- `hint.kind` values outside the closed set → ignore hint; fall back to `target` or no-op
- Do **not** accept tech-debt report file paths as required input fields in v1
- Stack skill names are **not** schema fields — they arrive under `## Instructions` (A')
