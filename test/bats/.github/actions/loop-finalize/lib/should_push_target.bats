#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/should_push_target.sh
#
# Use cases:
# - delivery pr_push pushes on APPROVE with changes
# - delivery pr_create, none, and old strategy names never push
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

@test "does not push for pr_create, none, or old strategy names" {
    local delivery checked=0
    for delivery in pr_create none push push_head open_pr ""; do
        run should_push_target APPROVE true loop/x/1 "${delivery}"
        [ "$status" -eq 1 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 6 ]
}

@test "does not push on REJECT, no changes, or empty branch" {
    run should_push_target REJECT true loop/x/1 pr_push
    [ "$status" -eq 1 ]
    run should_push_target APPROVE false loop/x/1 pr_push
    [ "$status" -eq 1 ]
    run should_push_target APPROVE true "" pr_push
    [ "$status" -eq 1 ]
}

@test "pushes on APPROVE with changes for pr_push" {
    run should_push_target APPROVE true loop/x/1 pr_push
    [ "$status" -eq 0 ]
}
