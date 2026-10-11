# Detect JSON schema

The skill detect script (`scripts/detect_test_gap.sh`) emits:

```json
{
  "status": "ok",
  "scope": "range",
  "since": "<ref>",
  "commit_range": "<ref>..HEAD",
  "skip": false,
  "hotspots": [{ "path": "src/a.sh", "kind": "churn", "count": 7, "window": "90.days" }],
  "ledger": {
    "file": ".loop/state-test-gap-ledger.json",
    "processed": [{ "path": "test/bats/foo.bats", "attempts": 1, "outcome": "pr-created", "processed_at": "2026-10-11T10:00:00Z" }]
  },
  "warnings": []
}
```

- `skip` is always `false`. Detect never states that tests are missing.
- `hotspots[]` lists frequently edited paths. They are hints, not findings.
- `ledger.processed[]` lists recently processed test paths. Do not select a target whose test path is listed unless you can state a new reason.
- `warnings[]` lists recoverable sensor problems (for example an invalid `since` ref).
- `status: "error"` is fatal: stop and report the error text.
