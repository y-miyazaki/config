# Loop Verifier Checklist

Generic checker gates. Domain callers append extra REJECT rules; they do not remove these.

## Gates

### SCOPE-01: Path scope

- **Check:** Changed files are relevant to the stated target. No denylist paths. No files outside an allowlist when one is set.
- **Why:** Drive-by edits and secret paths are unsafe in unattended loops.
- **Fix:** REJECT; tell the implementer which paths to revert.

### INTENT-01: Stated target

- **Check:** The diff addresses the stated issue, CI failure, or comment — not a different problem.
- **Why:** Silent problem substitution wastes retries.
- **Fix:** REJECT with the mismatch.

### HONEST-01: No cheated checks

- **Check:** The change does not disable tests, skip assertions, or comment out gates to go green.
- **Why:** Cheating is a hard safety fail.
- **Fix:** REJECT.

### SECRET-01: No sensitive data

- **Check:** No secrets, credentials, or sensitive values added or exposed.
- **Why:** Unattended merge risk.
- **Fix:** REJECT.

### RISK-01: Human review

- **Check:** For medium or higher risk, note human review even if other gates pass.
- **Why:** APPROVE is not a substitute for branch protection.
- **Fix:** APPROVE may still apply; put the risk in `reason`.
