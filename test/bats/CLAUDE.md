# CLAUDE.md

Behavioral rules for `test/bats/**`. Generic Bats rules live in the companion Bats rules (`.claude/rules/bats.md`); this file holds only what is specific to this repository. Script rules: [scripts/CLAUDE.md](../../scripts/CLAUDE.md).

---

## Layout and headers (MUST)

| Rule            | Requirement                                                                                                                                                                                                                   |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Suite path      | Mirror the source path: `scripts/lib/aws.sh` -> `test/bats/scripts/lib/aws.bats`; `.github/actions/<action>/lib/x.sh` -> `test/bats/.github/actions/<action>/lib/x.bats`; workflow suites live in `test/bats/github-actions/` |
| Header          | `# Tests for <repo-relative path>` exactly, then `# Use cases:` with one bullet per guaranteed behavior. `scripts/self/hooks/bats_changed.sh` maps a changed script to its suites through this line                           |
| Shared helpers  | Load `support/common.bash` with the walk-up loader; use `support/` helpers (`aws_mock.bash`, `gh_mock.bash`, `git_test_mock.bash`, `shell_tool_mock.bash`, `action_yml.bash`) instead of copying mocks                        |
| Repository root | Use `bats_workspace_root` / `bats_source_rel`; suites assume the working directory is the repository root                                                                                                                     |

## Tests must not depend on the machine (MUST)

CI installs only Bats, GNU parallel, `shfmt`, `actionlint`, `ghalint`, `zizmor` and ShellSpec (see `.github/workflows/ci-shell-script.yaml`), on top of the runner's system tools. A developer machine also has the `mise` tools (`golangci-lint`, `terraform`, `tflint`, `trivy`, ...), so a test can pass locally and fail in CI.

- Do not rely on a tool outside the CI set. Mock it (shim under `BATS_TEST_TMPDIR`, prepended to `PATH`) or `skip` with a reason when the real tool is required.
- To prove a no-tool path, run with a system-only `PATH` (`env PATH=/usr/bin:/bin ...`) after checking `command -v <tool>` fails there; do not filter one directory out of `PATH` (here the `mise` shims directory holds every tool, so the filter removes nothing useful).
- Never call real AWS, GitHub or the network. Use `aws_mock.bash` / `gh_mock.bash` and local bare git repositories.
- A new test for a bug must fail on the old code: revert the fix temporarily (or run the test on `git show HEAD:<file>`) and confirm it fails before keeping it.
- A green local run is not proof for CI. When a CI-only failure appears, reproduce the CI environment (tool set, `PATH`, working directory) instead of re-running the same command.

## Isolation (MUST)

CI runs `bats --jobs "$(nproc)" --no-parallelize-within-files`: suites run in parallel, so files must not share state.

- Write only under `BATS_TEST_TMPDIR`; never create files in the repository working directory or at a fixed path under `/tmp`. Create fixtures in `setup()`, remove them in `teardown()` when they live outside `BATS_TEST_TMPDIR`.
- A test that changes the working directory does it inside `run bash -c 'cd ... && ...'`, never as a bare `cd` before `run`.
- Isolate git: create repositories with `bats_git_fresh_repo` (local identity); do not read or write the repository's own `.git`, and do not rely on the caller's `GIT_*` variables or global config.
- A script whose `main` runs when sourced (no entry guard) cannot be unit-tested function by function; test it through `run bash <script>`, or add the guard in the same change.

## Running (SHOULD)

- Run the suites for the files you changed (`bats test/bats/<path>.bats`). The full suite (`bats -r test/bats`) takes about four minutes; run it before opening a PR, not after every edit.
- The Stop hook `scripts/self/hooks/bats_changed.sh` runs only the suites mapped from changed files, with a 120 second limit; it does not see suites that merely source a changed library. Run those suites yourself when you change `scripts/lib/`.
