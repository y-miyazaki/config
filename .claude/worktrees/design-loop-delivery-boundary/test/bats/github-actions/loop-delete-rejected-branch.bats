#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/should_delete_rejected_branch.sh
#
# Use cases:
# - REJECT with no branch diff vs base → delete
# - REJECT with has_changes true (diff vs base remains) → keep
# - APPROVE never deletes

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    # shellcheck disable=SC1091
    bats_source_rel ".github/actions/loop-finalize/lib/should_delete_rejected_branch.sh"
}

@test "should_delete_rejected_branch is true for REJECT without has_changes" {
    run should_delete_rejected_branch "REJECT" "false"
    [ "$status" -eq 0 ]
}

@test "should_delete_rejected_branch is false for REJECT when has_changes is true" {
    run should_delete_rejected_branch "REJECT" "true"
    [ "$status" -eq 1 ]
}

@test "should_delete_rejected_branch is false for APPROVE even without has_changes" {
    run should_delete_rejected_branch "APPROVE" "false"
    [ "$status" -eq 1 ]
}
