## Path Scope

Allowlist and denylist are configured by the caller workflow (`LOOP_ALLOWLIST`, `LOOP_DENYLIST` / verifier denylist). The implementer prompt `## Constraints` section repeats the active allowlist. Defaults below match this repository's dogfood caller.

This skill edits documentation only. Callers must align `LOOP_ALLOWLIST` with documentation paths; do not widen it to source or infrastructure paths.

### Allowlist (dogfood example)

`docs/**/*.md`, `README.md`, `mkdocs.yml` (nav only)

### Denylist

`**/.env`, `**/credentials*`, `**/secrets*`, `**/migration/*.sql`, `**/infrastructure/**`

Edit only allowlist paths. Never touch denylist paths.
