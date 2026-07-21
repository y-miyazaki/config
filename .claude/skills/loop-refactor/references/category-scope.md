## Path Scope

Allowlist and denylist are configured by the caller workflow (`LOOP_ALLOWLIST`, `LOOP_DENYLIST`). The implementer prompt `## Constraints` section repeats the active allowlist. Defaults below match this repository's dogfood caller.

### Allowlist (dogfood example)

`.apm/packages/**`, `scripts/**`

### Denylist

`**/.env`, `**/credentials*`, `**/secrets*`, `**/migration/*.sql`, `docs/report/**`, `node_modules/**`, `apm_modules/**`, `**/.git/**`

Generated agent trees (`.agents/`, `.claude/`, `.cursor/`, …) are not edit targets in the config repo; edit `.apm/packages/` sources instead.

### Rules

- Edit only allowlist paths; never touch denylist paths
- One hint → one target per run — do not expand into repo-wide cleanup
- O2 cap: shallow same-package moves only; no cross-package or GoF changes
