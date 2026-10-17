#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/should_push_target.sh
#
# Use cases:
# - push and push_head push on APPROVE with changes
# - open_pr and none never push
# - REJECT, no changes, or empty branch never push

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/should_push_target.sh"
}

@test "does not push for open_pr or none" {
    run should_push_target APPROVE true loop/x/1 open_pr
    [ "$status" -eq 1 ]
    run should_push_target APPROVE true loop/x/1 none
    [ "$status" -eq 1 ]
}

@test "does not push on REJECT, no changes, or empty branch" {
    run should_push_target REJECT true loop/x/1 push
    [ "$status" -eq 1 ]
    run should_push_target APPROVE false loop/x/1 push
    [ "$status" -eq 1 ]
    run should_push_target APPROVE true "" push
    [ "$status" -eq 1 ]
}

@test "pushes on APPROVE with changes for push and push_head" {
    run should_push_target APPROVE true loop/x/1 push
    [ "$status" -eq 0 ]
    run should_push_target APPROVE true loop/x/1 push_head
    [ "$status" -eq 0 ]
}
