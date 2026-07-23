# docs-updater Loop Checklist

## Classification

- Stale reference or missing required docs → `### Candidates` at L1; `### Changes` at L2+
- Minor drift or needs human judgment → `### Watch` or `### Deferred`
- Out of allowlist or >3 sections in one file → omit or defer

## Scope Guards

- On loop path, respect caller `allowlist` / `denylist` per `category-scope.md`
- > 3 sections affected in one doc → defer that file as Watch
- > 20 findings → fix first 10 High-Priority items at L2+; note truncation in Overview

## Output

- Emit survey or apply shape per [common-output-format-loop.md](common-output-format-loop.md)
- At `L1`, survey shape only — do not edit files
- At `L2`/`L3`, apply shape; reconcile **Changes** / **Deferred** with `git diff --name-only`
- **Deferred** paths MUST NOT remain in git diff — revert stray edits before synthesis

## Error Handling

- `skip` true or no actionable findings → survey no-op; stop
- File outside allowlist → classify as Watch; do not edit
- No findings → survey no-op

## Examples

- Stale workflow reference in a docs table row → High-Priority candidate
- Slightly outdated version number → Watch item
- Test-only change with no doc impact → omit from Candidates
