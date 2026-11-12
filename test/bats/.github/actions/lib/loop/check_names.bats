#!/usr/bin/env bats

# Tests for .github/actions/lib/loop/check_names.sh
#
# Use cases:
# - check_names_branch accepts ordinary branch names, loop agent branches and PR head names
# - check_names_branch rejects empty names, a leading dash, "..", spaces and shell metacharacters
# - check_names_state_file accepts .loop/state-<name>.json and rejects every other shape
# - check_names_state_file rejects ".." and path separators inside the name
# - every action that validates a branch or state file path sources check_names.sh and keeps no regex of its own

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/check_names.sh"
}

@test "check_names_branch accepts ordinary branch names, loop agent branches and PR head names" {
    local name
    for name in main release/1.2 feature/pr-head loop/github-pr-revise/20261112-120000-issue-7 _x .hidden user/fix_bug-1; do
        run check_names_branch "${name}"
        [ "$status" -eq 0 ]
    done
}

@test "check_names_branch rejects empty names, a leading dash, dot-dot, spaces and shell metacharacters" {
    local name
    for name in "" "-f" "--upload-pack=x" "a..b" "../x" "bad branch" 'a;b' 'a$(id)' 'a`id`' "a|b" "a'b"; do
        run check_names_branch "${name}"
        [ "$status" -eq 1 ]
    done
}

@test "check_names_state_file accepts .loop/state-<name>.json" {
    local path
    for path in .loop/state-changelog.json .loop/state-ci-sweeper-run-ledger.json .loop/state-a_b.c.json; do
        run check_names_state_file "${path}"
        [ "$status" -eq 0 ]
    done
}

@test "check_names_state_file rejects dot-dot, separators in the name and every other shape" {
    local path
    for path in "" state.json .loop/state.json .loop/state_foo.json .loop/state.foo.json .loop/state-a..b.json .loop/state-../x.json .loop/state-a/b.json .loop/state-a b.json ../.loop/state-a.json /abs/.loop/state-a.json .loop/state-a.json.bak; do
        run check_names_state_file "${path}"
        [ "$status" -eq 1 ]
    done
}

@test "no action keeps its own branch-name or state-path regex outside check_names.sh" {
    local root hits
    root="$(bats_workspace_root)/.github"
    hits="$(grep -rnE 'a-zA-Z0-9/_\.-\]|a-zA-Z0-9_\./\]|\\\.loop/state-\[' "${root}/actions" "${root}/workflows" | grep -v 'lib/loop/check_names.sh' | grep -v 'check_names.sh:' || true)"
    [ -z "${hits}" ]
}
