## Input Schema

Provided via prompt context by the calling workflow (loop-prompt-generate action).

```json
{
  "commit_range": "abc1234..def5678",
  "level": "L2",
  "skip": false,
  "findings": [
    {
      "file": "docs/reference/specification.md",
      "reason": "references deleted workflow ci-build.yaml",
      "source_commit": "def5678"
    }
  ]
}
```

| Field                      | Type    | Description                                                                     |
| -------------------------- | ------- | ------------------------------------------------------------------------------- |
| `commit_range`             | string  | SHA range that triggered detection                                              |
| `level`                    | enum    | Operating level: `L1` (report only), `L2` (edit + PR), `L3` (edit + auto-merge) |
| `skip`                     | boolean | When true, no documentation impact detected                                     |
| `findings`                 | array   | Detected documentation drift items (may be empty)                               |
| `findings[].file`          | string  | Path to affected documentation file                                             |
| `findings[].reason`        | string  | Why the file is stale or needs update                                           |
| `findings[].source_commit` | string  | Commit that caused the drift                                                    |

`findings` may be an empty array. `level` defaults to `L2` when omitted by the workflow.
