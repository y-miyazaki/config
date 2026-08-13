#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/paths.sh list_non_loop_branch_files
#
# Use cases:
# - clean worktree with commits ahead of base counts as branch changes
# - only .loop/ files vs base do not count
# - HEAD identical to base is empty

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    # shellcheck disable=SC1091
    bats_source_rel ".github/actions/loop-execute/lib/paths.sh"
    WORK="${BATS_TEST_TMPDIR}/work"
    ORIGIN="${BATS_TEST_TMPDIR}/origin.git"
    rm -rf "${WORK}" "${ORIGIN}"
    mkdir -p "${WORK}"
    bats_git_init_in_place "${WORK}"
    git -C "${WORK}" checkout -q -b main
    printf 'base\n' > "${WORK}/tracked.txt"
    bats_git_commit "${WORK}" "chore: init" tracked.txt
    git init -q --bare "${ORIGIN}"
    git -C "${WORK}" remote add origin "${ORIGIN}"
    git -C "${WORK}" push -q -u origin main
}

@test "list_non_loop_branch_files is empty when HEAD matches origin/base" {
    run list_non_loop_branch_files "${WORK}" "main"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "list_non_loop_branch_files lists committed files ahead of base with a clean worktree" {
    git -C "${WORK}" checkout -q -b feature
    printf 'changed\n' > "${WORK}/tracked.txt"
    bats_git_commit "${WORK}" "fix: change tracked" tracked.txt
    run list_non_loop_branch_files "${WORK}" "main"
    [ "$status" -eq 0 ]
    [[ $output == *"tracked.txt"* ]]
}

@test "list_non_loop_branch_files ignores .loop-only commits vs base" {
    git -C "${WORK}" checkout -q -b feature
    mkdir -p "${WORK}/.loop"
    printf '{}\n' > "${WORK}/.loop/state.json"
    bats_git_commit "${WORK}" "chore(loop): state" .loop/state.json
    run list_non_loop_branch_files "${WORK}" "main"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
