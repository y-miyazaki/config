## Path Scope

### Allowlist

`docs/**/*.md` (any depth under `docs/`, including `docs/index.md`), `README.md`, `mkdocs.yml` (nav only)

### Denylist

`**/.env`, `**/credentials*`, `**/secrets*`, `**/migration/*.sql`, `**/infrastructure/**`

Edit only allowlist paths. Never touch denylist paths.
