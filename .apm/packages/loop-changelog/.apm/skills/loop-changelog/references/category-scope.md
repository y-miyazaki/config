## Path Scope

Allowlist and denylist are configured by the caller workflow (`LOOP_ALLOWLIST`, `LOOP_DENYLIST`). The implementer prompt `## Constraints` section repeats the active allowlist.

This skill edits the changelog file only. Callers must keep `LOOP_ALLOWLIST` narrow (typically `CHANGELOG.md`).

### Allowlist (dogfood example)

`CHANGELOG.md`

### Denylist

`**/.env`, `**/credentials*`, `**/secrets*`, `src/**`, `docs/**`, `.github/**`

Edit only allowlist paths. Never touch denylist paths.
