# GitHub Copilot Instructions

Repository-wide instructions for GitHub Copilot.

## Instruction Priority

- Follow `AGENTS.md` as the primary cross-agent policy
- Follow `.github/instructions/*.instructions.md` for path-specific rules
- More specific `applyTo` rules take precedence

## Copilot-specific Notes

- Use this file for Copilot-specific guidance only.
- Prefer workspace-relative paths
- Respect existing project structure and editor configuration
- Use minimal diffs unless broader refactor is explicitly required
- Repository rules belong in `.github/instructions/*.instructions.md`
- For work under `.apm/**`, treat `.apm/AGENTS.md` as the operational source of truth.
- For APM-managed assets, edit source files under `.apm/packages/**` and reflect to consumers via `apm install`.

## References

- `AGENTS.md`
- `.github/instructions/*.instructions.md`
- `.apm/AGENTS.md`
