## Path Scope

Allowlist and denylist are configured by the caller workflow (`LOOP_ALLOWLIST`, `LOOP_DENYLIST` / verifier denylist). Defaults below match this repository's dogfood caller.

### Allowlist (dogfood example)

`.github/**`, `.apm/packages/**`, `scripts/**`, `apm.yml`, `mise.toml`, `renovate/**`, `docs/**/*.md`, `README.md`, `mkdocs.yml`

### Denylist

`**/.env`, `**/credentials*`, `**/secrets*`, `**/migration/*.sql`, `**/infrastructure/**`

Edit only allowlist paths. Never touch denylist paths.
