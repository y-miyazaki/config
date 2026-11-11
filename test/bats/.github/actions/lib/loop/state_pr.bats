#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/state_pr.sh
#
# Use cases:
# - loop_open_state_pr pushes a prefixed branch and queues auto-merge
# - loop_open_state_pr falls back to an immediate merge when auto-merge is refused
# - loop_open_state_pr warns when the PR cannot be merged
# - loop_open_state_pr exits 1 when the branch push fails
# - loop_open_state_pr exits 1 with an error when gh pr create fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/state_pr.sh"
    BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${BIN}"
    CALLS="${BATS_TEST_TMPDIR}/calls"
    : > "${CALLS}"
    export CALLS GITHUB_REPOSITORY="owner/repo" GITHUB_RUN_ID=11 GITHUB_RUN_ATTEMPT=2
    cat > "${BIN}/git" << 'MOCK'
#!/bin/bash
echo "git $*" >> "${CALLS}"
[[ $1 == push && -n ${MOCK_PUSH_FAIL:-} ]] && exit 1
exit 0
MOCK
    cat > "${BIN}/gh" << 'MOCK'
#!/bin/bash
echo "gh $*" >> "${CALLS}"
if [[ $2 == create ]]; then [[ -n ${MOCK_CREATE_RC:-} ]] && exit "${MOCK_CREATE_RC}"; echo "https://example.test/pr/1"; exit 0; fi
if [[ $2 == merge && $* == *--auto* ]]; then exit "${MOCK_AUTO_RC:-0}"; fi
exit "${MOCK_MERGE_RC:-0}"
MOCK
    chmod +x "${BIN}/git" "${BIN}/gh"
    export PATH="${BIN}:${PATH}"
}

@test "loop_open_state_pr exits 1 when the branch push fails" {
    MOCK_PUSH_FAIL=1 run loop_open_state_pr main loop/state "t" "b" "State PR"
    [ "$status" -eq 1 ]
    [[ $output == *"Failed to push state branch loop/state-11-2-"* ]]
    run grep -q "^gh pr create" "${CALLS}"
    [ "$status" -ne 0 ]
}

@test "loop_open_state_pr exits 1 with an error when gh pr create fails" {
    MOCK_CREATE_RC=1 run loop_open_state_pr main loop/state "t" "b" "State PR"
    [ "$status" -eq 1 ]
    [[ $output == *"::error::Failed to open State PR from loop/state-11-2-"* ]]
    run grep -q "^gh pr merge" "${CALLS}"
    [ "$status" -ne 0 ]
}

@test "loop_open_state_pr falls back to an immediate merge when auto-merge is refused" {
    MOCK_AUTO_RC=1 run loop_open_state_pr main loop/state "t" "b" "State PR"
    [ "$status" -eq 0 ]
    [[ $output == *"State PR merged: https://example.test/pr/1"* ]]
}

@test "loop_open_state_pr pushes a prefixed branch and queues auto-merge" {
    run loop_open_state_pr develop loop/state-promote "title text" "body text" "State promote PR"
    [ "$status" -eq 0 ]
    [[ $output == *"State promote PR queued for auto-merge: https://example.test/pr/1"* ]]
    grep -qE "^git checkout -B loop/state-promote-11-2-[0-9a-f]{8}$" "${CALLS}"
    grep -q -- "--base develop" "${CALLS}"
    grep -q -- "--title title text" "${CALLS}"
}

@test "loop_open_state_pr warns when the PR cannot be merged" {
    MOCK_AUTO_RC=1 MOCK_MERGE_RC=1 run loop_open_state_pr main loop/state "t" "b" "State PR"
    [ "$status" -eq 0 ]
    [[ $output == *"::warning::State PR requires manual merge: https://example.test/pr/1"* ]]
}
