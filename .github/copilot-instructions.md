# GitHub Copilot Instructions

Repository-wide instructions for GitHub Copilot.

## Instruction Priority

- Follow `AGENTS.md` as the primary cross-agent policy
- Follow `.github/instructions/*.instructions.md` for path-specific rules
- More specific `applyTo` rules take precedence

## Copilot-specific Notes

- Prefer workspace-relative paths
- Respect existing project structure and editor configuration
- Use minimal diffs unless broader refactor is explicitly required
- For work under `.apm/**`, treat `.apm/AGENTS.md` as the operational source of truth.
- For APM-managed assets, edit source files under `.apm/packages/**` and reflect to consumers via `apm install`.

## Repository Rules

### Naming Conventions

| Component           | Rule                                 | Example          |
| ------------------- | ------------------------------------ | ---------------- |
| Temporary artifacts | Use an ignored repository-local path | `tmp/report.txt` |

### Operational Rules

- Write temporary and generated artifacts under `tmp/` unless a more specific ignored path is defined.
- Keep generated files out of version control unless they are intentionally committed.
- Prefer repository-local paths and conventions when adding or updating artifacts.
- If a workflow generates files that must be committed, document the intent in the relevant change.

### Code Modification Guidelines

- Make the smallest safe change.
- Update the relevant instruction file when repository rules change.
- Re-run the applicable validation after changing instruction files.

### Anti-Patterns

- Do not place repository-specific operational rules in `AGENTS.md`.
- Do not rely on ignored paths for instructions that must be tracked.
- Do not duplicate the same rule in multiple instruction files unless there is a clear ownership split.

## Testing and Validation

```bash
apm install --update
apm audit --ci
markdownlint-cli2 ".github/instructions/*.instructions.md"
git diff --check
```

## Security Guidelines

- Do not store secrets, tokens, or credentials in instruction files.
- Do not make destructive operations the default in command examples.
- Keep operational guidance concise and reviewable.

## Hook Automation

When validation hooks detect failures (e.g., linting, link checking, formatting):

1. **Inspect the hook output** to understand what failed and why
2. **Auto-fix when possible** — Apply standard corrections (formatting, link repairs, etc.)
3. **Re-run validation** to confirm the fix resolves the issue
4. **Stop on unresolvable errors** — Request user guidance if the issue requires judgment calls or domain knowledge

This pattern applies to all `.github/hooks/*.json` events. Prioritize minimal, targeted fixes that respect the repository's code style and conventions.

## References

- `AGENTS.md`
- `.github/instructions/*.instructions.md`
- `.apm/AGENTS.md`
