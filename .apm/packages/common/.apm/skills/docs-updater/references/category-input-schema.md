## Input Schema

Load on the automation path only. Field names and semantics are defined by the caller-assembled prompt — see repository automation docs when present.

Typical detect JSON shape:

```json
{
  "commit_range": "abc1234..def5678",
  "skip": false,
  "findings": [
    {
      "file": "docs/guide/overview.md",
      "reason": "references deleted path old-module.md",
      "source_commit": "def5678"
    }
  ]
}
```

| Field                      | Type    | Description                                 |
| -------------------------- | ------- | ------------------------------------------- |
| `commit_range`             | string  | Revision range that triggered detection     |
| `skip`                     | boolean | When true, no documentation impact detected |
| `findings`                 | array   | Documentation drift items (may be empty)    |
| `findings[].file`          | string  | Path to affected documentation file         |
| `findings[].reason`        | string  | Why the file is stale or needs update       |
| `findings[].source_commit` | string  | Revision that caused the drift              |

Edit permission and path scope are **not** JSON fields. Read them from `## Constraints` per [category-automation-envelope.md](category-automation-envelope.md) and [category-scope.md](category-scope.md).
