#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/should_delete_rejected_branch.sh
#
# Use cases:
# - delivery none deletes the branch for any verdict, with or without changes
# - APPROVE with pr_create or pr_push keeps the branch
# - REJECT with changes keeps the branch for pr_create and pr_push
# - REJECT without changes deletes the branch for pr_create and pr_push
# - the old strategy name push_head is not treated as none

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/should_delete_rejected_branch.sh"
}

@test "deletes REJECT branches without changes for pr_create and pr_push" {
    local d checked=0
    for d in pr_create pr_push; do
        run should_delete_rejected_branch REJECT false "$d"
        [ "$status" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "deletes for delivery none regardless of verdict and changes" {
    local v c checked=0
    for v in APPROVE REJECT ""; do
        for c in true false; do
            run should_delete_rejected_branch "$v" "$c" none
            [ "$status" -eq 0 ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 6 ]
}

@test "keeps APPROVE branches for pr_create and pr_push" {
    local d c checked=0
    for d in pr_create pr_push; do
        for c in true false; do
            run should_delete_rejected_branch APPROVE "$c" "$d"
            [ "$status" -eq 1 ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 4 ]
}

@test "keeps REJECT branches with changes for pr_create, pr_push, and push_head" {
    local d checked=0
    for d in pr_create pr_push push_head; do
        run should_delete_rejected_branch REJECT true "$d"
        [ "$status" -eq 1 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}
