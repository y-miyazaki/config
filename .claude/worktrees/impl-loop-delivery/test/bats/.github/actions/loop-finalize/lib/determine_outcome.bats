#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/determine_outcome.sh
#
# Use cases:
# - an explicit override wins over every other input
# - a failed or cancelled agent job is error
# - no product diff is rejected on REJECT and unchanged otherwise, for every delivery
# - APPROVE with changes follows the delivery table: pr_create is pr_created,
#   pr_push is pr_pushed, none is reported
# - APPROVE with changes and an unknown or empty delivery is error (fail closed)
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

@test "APPROVE with changes follows the delivery table" {
    local row delivery expected checked=0
    for row in "pr_create:pr_created" "pr_push:pr_pushed" "none:reported"; do
        delivery="${row%%:*}"
        expected="${row#*:}"
        run determine_outcome "" success true APPROVE "${delivery}"
        [ "$status" -eq 0 ]
        [ "$output" = "${expected}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}

@test "APPROVE with changes is error for an unknown or empty delivery" {
    local delivery checked=0
    for delivery in "" open_pr push_head push; do
        run determine_outcome "" success true APPROVE "${delivery}"
        [ "$status" -eq 0 ]
        [ "$output" = "error" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 4 ]
}

@test "failed or cancelled agent job is error" {
    local r checked=0
    for r in failure cancelled; do
        run determine_outcome "" "$r" true APPROVE pr_create
        [ "$output" = "error" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "no product diff is rejected or unchanged for every delivery" {
    local delivery checked=0
    for delivery in pr_create pr_push none; do
        run determine_outcome "" success false REJECT "${delivery}"
        [ "$output" = "rejected" ]
        run determine_outcome "" success false APPROVE "${delivery}"
        [ "$output" = "unchanged" ]
        run determine_outcome "" skipped false "" "${delivery}"
        [ "$output" = "unchanged" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}

@test "override wins" {
    run determine_outcome watch failure true REJECT pr_create
    [ "$status" -eq 0 ]
    [ "$output" = "watch" ]
}

@test "REJECT with changes is rejected and a missing verdict is error" {
    run determine_outcome "" success true REJECT pr_push
    [ "$output" = "rejected" ]
    run determine_outcome "" success true "" pr_create
    [ "$output" = "error" ]
}
