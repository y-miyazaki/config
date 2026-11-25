# CLAUDE.md

Behavioral rules for `scripts/**` and the root installers (`install_go.sh`, `install_terraform.sh`). Generic shell rules live in the companion Shell Script rules (`.claude/rules/shell-script.md`); this file holds only what is specific to this repository. Tests: [test/bats/CLAUDE.md](../test/bats/CLAUDE.md).

---

## Source of truth and sync (MUST)

| Edit here                                                                                           | Never hand-edit (synced by the Stop hook)                                                    |
| --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `scripts/lib/*.sh`                                                                                  | `.apm/packages/*/.apm/skills/*/scripts/lib/` and the `.claude/`, `.agents/` and other copies |
| `scripts/{shell-script,go,terraform}/validate.sh`, `scripts/shell-script/fix_function_doc_order.sh` | The paired skill `scripts/` copies                                                           |

Do not run `apm install` or the `scripts/self/apm/sync_*` scripts by hand; the Stop hook does it. `scripts/self/**` is repository-only tooling and is not distributed.

## Library contracts are public (MUST)

`scripts/lib/` is copied into every distributed skill, so a function signature, exit status or output change is a breaking change for consumers.

- A function that validates or checks returns a status (`return 1`); it does not call `error_exit` or `exit`. The caller decides (`if ! f; then`, `f || exit 1`).
- A function that wraps a command returns that command's status and keeps stdout clean (data only); diagnostics go to stderr.
- Build commands as arrays and run them through `execute_command`; do not assemble command strings for `bash -c`.
- When a contract changes, add an entry to the breaking-change list of the change (migration step for downstream repositories) and update the Bats suite that pins the old behavior.

## Do the cheap decision before requiring tools (MUST)

Check for tools (`require_dependencies`, `command -v`) only after the script has decided there is work to do. A no-op path (`--changed-only` with no change, an empty target list, `--help`) must succeed without the Go toolchain, the linter or any other optional tool, because CI runners install fewer tools than a developer machine.

## Temporary files (MUST)

Create disposable files with `mktemp` (system temp dir) and remove them on exit (`trap`); never write them into the repository or into the repo-level `tmp/`. A path derived from `$PWD` or the repository root is not a temp location.

## Failure behavior (MUST)

- A path, option or input the user gave that does not resolve is an error (non-zero), never a silent "nothing to do".
- An unknown option exits non-zero; only `-h` / `--help` exits 0.
- A destructive script (`clean_*`, `rm -rf`) never deletes what git tracks and refuses to run when it cannot tell (for example git is unreadable in a repository).
- A pipeline under `set -o pipefail` whose failure the script wants to tolerate uses `x=$(a | b) || x=default`, not `a | b || echo default` (the second form prints twice).

## Pairing (MUST)

Every script and every `scripts/lib/*.sh` has a Bats suite under `test/bats/` that mirrors its path and names it in a `# Tests for <repo-relative path>` header; the Stop hook `scripts/self/hooks/bats_changed.sh` maps changed files to suites through that header. Entry scripts keep the `if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi` guard so a suite can source them and call one function.
