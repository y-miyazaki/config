# Loop Checker Output

## Markdown

```markdown
## Verdict: APPROVE | REJECT

### Evidence

- Scope: (pass/fail + notes)
- Intent: (pass/fail + notes)
- Honesty / secrets: (pass/fail + notes)

### If REJECT

- Reasons: (numbered, specific)
- Suggested next step for maker
```

## Machine-readable (required)

End the response with a single fenced JSON block (no prose after it):

```json
{
  "verdict": "APPROVE",
  "reason": "one-line summary"
}
```

On REJECT:

```json
{
  "verdict": "REJECT",
  "files": ["path/to/file"],
  "issue": "what is factually wrong",
  "fix": "specific change the maker must make",
  "reason": "one-line summary for logs"
}
```

Rules:

- `verdict` must be `APPROVE` or `REJECT`
- On REJECT, `files` (array), `issue`, `fix`, and `reason` are required
- Use repo-relative paths in `files`
