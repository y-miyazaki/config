#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/determine_outcome.sh
#
# Use cases:
# - an explicit override wins over every other input
# - a failed or cancelled agent job is error
# - no product diff is rejected on REJECT and no-changes otherwise
# - APPROVE with changes is pr-created for open_pr, push, push_head, and an empty strategy
# - APPROVE with changes is reported for strategy none (no PR, nothing landed)
# - REJECT with changes is rejected; a missing verdict with changes is error

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/determine_outcome.sh"
}

@test "APPROVE with changes is pr-created for strategies that open or land" {
    local s
    for s in open_pr push push_head ""; do
        run determine_outcome "" success true APPROVE "$s"
        [ "$status" -eq 0 ]
        [ "$output" = "pr-created" ]
    done
}

@test "APPROVE with changes is reported for strategy none" {
    run determine_outcome "" success true APPROVE none
    [ "$status" -eq 0 ]
    [ "$output" = "reported" ]
}

@test "failed or cancelled agent job is error" {
    local r
    for r in failure cancelled; do
        run determine_outcome "" "$r" true APPROVE none
        [ "$output" = "error" ]
    done
}

@test "no product diff is rejected or no-changes" {
    run determine_outcome "" success false REJECT none
    [ "$output" = "rejected" ]
    run determine_outcome "" success false APPROVE none
    [ "$output" = "no-changes" ]
    run determine_outcome "" skipped false "" open_pr
    [ "$output" = "no-changes" ]
}

@test "override wins" {
    run determine_outcome watch failure true REJECT none
    [ "$status" -eq 0 ]
    [ "$output" = "watch" ]
}

@test "REJECT with changes is rejected and a missing verdict is error" {
    run determine_outcome "" success true REJECT none
    [ "$output" = "rejected" ]
    run determine_outcome "" success true "" open_pr
    [ "$output" = "error" ]
}
