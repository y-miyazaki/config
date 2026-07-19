## Path Scope

Allowlist and denylist are configured by the caller workflow (`LOOP_ALLOWLIST`, `LOOP_DENYLIST` / verifier denylist). The implementer prompt `## Constraints` section repeats the active allowlist. Defaults below match this repository's dogfood caller.

This skill writes technical debt reports only. Callers must keep `LOOP_ALLOWLIST` narrow to report paths; do not widen it to application source or infrastructure paths for edits.

### Allowlist (dogfood example)

`docs/report/tech-debt/**/*.md`

### Denylist

`**/.env`, `**/credentials*`, `**/secrets*`, `**/migration/*.sql`, `**/infrastructure/**`, `src/**`, `.github/**`

Edit only allowlist paths. Never touch denylist paths.

Read source files outside the allowlist for evidence only. Do not modify them.
