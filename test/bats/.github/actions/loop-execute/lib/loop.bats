#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154,SC2317

# Tests for .github/actions/loop-execute/lib/loop.sh helpers
#
# Use cases:
# - parse_outcome_override_from_agent_output detects bold Outcome watch
# - parse_outcome_override_from_agent_output detects plain Outcome deferred
# - parse_outcome_override_from_agent_output detects no actionable failures
# - parse_outcome_override_from_agent_output ignores fix outcomes
# - promote_has_changes_after_attempt ignores branch-ahead on attempt 1
# - promote_has_changes_after_attempt keeps branch-ahead on attempt 2+
# - promote_has_changes_after_attempt treats HEAD movement as this-attempt changes

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    # loop.sh pulls in the full execute lib stack via _init.
    bats_source_rel ".github/actions/loop-execute/lib/loop.sh"
}

@test "parse_outcome_override_from_agent_output detects bold Outcome watch" {
    run parse_outcome_override_from_agent_output $'## Summary\n- **Outcome:** watch\n'
    [ "$status" -eq 0 ]
}

@test "parse_outcome_override_from_agent_output detects plain Outcome deferred" {
    run parse_outcome_override_from_agent_output $'Outcome: deferred — infra flake\n'
    [ "$status" -eq 0 ]
}

@test "parse_outcome_override_from_agent_output detects no actionable failures" {
    run parse_outcome_override_from_agent_output $'- **Outcome:** no actionable failures\n'
    [ "$status" -eq 0 ]
}

@test "parse_outcome_override_from_agent_output ignores fix outcomes" {
    run parse_outcome_override_from_agent_output $'- **Outcome:** Fixed MD001 in docs/ci-sweeper-test.md\n'
    [ "$status" -ne 0 ]
}

@test "promote_has_changes_after_attempt leaves HAS_CHANGES false on attempt 1 when HEAD unchanged" {
    HAS_CHANGES="false"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}/wt-a1"
    bats_git_fresh_repo "${WORKTREE_PATH}"
    printf 'x\n' > "${WORKTREE_PATH}/x.txt"
    bats_git_commit "${WORKTREE_PATH}" "init"
    BASE_BRANCH="main"
    function list_non_loop_branch_files { printf 'docs/foo.md\n'; }
    local pre
    pre="$(git -C "${WORKTREE_PATH}" rev-parse HEAD)"
    promote_has_changes_after_attempt 1 "${pre}" "false"
    [[ ${HAS_CHANGES} == "false" ]]
}

@test "promote_has_changes_after_attempt sets HAS_CHANGES on attempt 2 when branch has product files" {
    HAS_CHANGES="false"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}/wt-a2"
    bats_git_fresh_repo "${WORKTREE_PATH}"
    printf 'x\n' > "${WORKTREE_PATH}/x.txt"
    bats_git_commit "${WORKTREE_PATH}" "init"
    BASE_BRANCH="main"
    function list_non_loop_branch_files { printf 'docs/foo.md\n'; }
    local pre
    pre="$(git -C "${WORKTREE_PATH}" rev-parse HEAD)"
    promote_has_changes_after_attempt 2 "${pre}" "false"
    [[ ${HAS_CHANGES} == "true" ]]
}

@test "promote_has_changes_after_attempt sets HAS_CHANGES when HEAD moved" {
    HAS_CHANGES="false"
    WORKTREE_PATH="${BATS_TEST_TMPDIR}/wt-head"
    bats_git_fresh_repo "${WORKTREE_PATH}"
    printf 'x\n' > "${WORKTREE_PATH}/x.txt"
    bats_git_commit "${WORKTREE_PATH}" "init"
    BASE_BRANCH="main"
    function list_non_loop_branch_files { printf ''; }
    local pre
    pre="$(git -C "${WORKTREE_PATH}" rev-parse HEAD)"
    printf 'y\n' > "${WORKTREE_PATH}/x.txt"
    bats_git_commit "${WORKTREE_PATH}" "agent commit"
    promote_has_changes_after_attempt 1 "${pre}" "false"
    [[ ${HAS_CHANGES} == "true" ]]
}
