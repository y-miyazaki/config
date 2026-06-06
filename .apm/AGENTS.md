# .apm/AGENTS.md

Project-scoped operating rules for files under `.apm/`.

## Scope

- Applies to `.apm/**` only.
- This directory is the source of packages distributed by `apm install`.

## Core Policy

- Manage agent assets through APM package sources under `.apm/packages/**`.
- Reflect changes to consumers by running `apm install`; do not rely on manual copy operations.

## Hook Policy

- Keep hook definitions and their runtime constraints with the package source under `.apm/packages/**`.
- Use POSIX sh-compatible command bodies in hook JSON so they work under `/bin/sh` as well as Bash-like launchers.
- Keep hook output unmodified when the purpose is validation, and return `exit 2` for validation failures.
- Use `.apm/AGENTS.md` for repository-wide policy, not for per-hook implementation details.

## Direct-Edit Restrictions

- Do not directly operate deployed target directories such as `.agents/`, `.github/hooks/`, .`.github/instructions` deployment paths in consumer repositories.
- Treat deployed files as generated artifacts from APM package installation.

## Command Reference

- Install full config package: `apm install --target copilot`
- Reproduce from lock file: `apm install --frozen`
- Refresh lock and dependencies when needed: `apm install --update`

## Change Workflow

1. Edit source files under `.apm/packages/**`.
2. Run the relevant `apm install ...` command.
3. Validate generated/deployed results in the target environment.
