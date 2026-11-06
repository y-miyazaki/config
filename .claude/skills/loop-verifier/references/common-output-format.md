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
- With several REJECT reasons, `files` is the union of affected paths; `issue` and `fix` are numbered lists in one string (`"1. … 2. …"`) in the same order as the Markdown Reasons; `reason` is a one-line summary
- Use repo-relative paths in `files`
- `files` may be `[]` when no changed file is at fault (diff unreadable, or the request is out of scope for the checker role); state the cause in `issue` and `reason`
