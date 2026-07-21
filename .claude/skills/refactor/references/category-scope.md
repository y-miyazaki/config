## Path Scope

Allowlist and denylist may be supplied by the user, caller Instructions, or (future) loop env. Defaults below are safe dogfood baselines for this config repository; consumers should override.

### Allowlist (dogfood example)

`.apm/packages/**`, `scripts/**`, `docs/**/*.md`, `README.md`, `apm.yml`, `.github/workflows/**`

### Denylist

`**/.env`, `**/credentials*`, `**/secrets*`, `**/migration/*.sql`, `docs/report/**`, `node_modules/**`, `apm_modules/**`, `**/.git/**`

### Rules

- Edit only allowlist paths; never touch denylist paths
- One target per run — do not expand into a repo-wide cleanup
- Generated agent trees (`.agents/`, `.claude/`, `.cursor/`, …) are not edit targets in the config repo; edit `.apm/packages/` sources instead
