#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/should_delete_rejected_branch.sh
#
# Use cases:
# - legacy behavior without a strategy argument
# - APPROVE with strategy none deletes the branch
# - APPROVE with open_pr, push, push_head keeps the branch
# - REJECT with changes keeps the branch even for none

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/should_delete_rejected_branch.sh"
}

@test "deletes after APPROVE when strategy is none" {
    run should_delete_rejected_branch APPROVE true none
    [ "$status" -eq 0 ]
}

@test "keeps APPROVE branches for open_pr, push, push_head" {
    for s in open_pr push push_head; do
        run should_delete_rejected_branch APPROVE true "$s"
        [ "$status" -eq 1 ]
    done
}

@test "keeps legacy behavior without strategy" {
    run should_delete_rejected_branch REJECT false
    [ "$status" -eq 0 ]
    run should_delete_rejected_branch REJECT true
    [ "$status" -eq 1 ]
    run should_delete_rejected_branch APPROVE true
    [ "$status" -eq 1 ]
}

@test "REJECT with changes is kept for none too" {
    run should_delete_rejected_branch REJECT true none
    [ "$status" -eq 1 ]
}
