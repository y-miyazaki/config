#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/resolve_state_write_mode.sh
#
# Use cases:
# - APPROVE with changes and a pushed agent branch follows the delivery table:
#   pr_create is pending, pr_push is advance, none is metadata
# - pr_create and pr_push are metadata unless the agent branch was pushed
#   (agent failure, missing bundle, or an omitted pushed flag)
# - every other verdict / has_changes combination is metadata for every delivery
# - a failed agent push is metadata for every delivery
# - old strategy names (open_pr, push, push_head) are metadata (not recognized)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/resolve_state_write_mode.sh"
}

@test "APPROVE with changes and a pushed branch follows the delivery table" {
    local row delivery expected checked=0
    for row in "pr_create:pending" "pr_push:advance" "none:metadata"; do
        delivery="${row%%:*}"
        expected="${row#*:}"
        run resolve_state_write_mode APPROVE true "${delivery}" false true
        [ "${status}" -eq 0 ]
        [ "${output}" = "${expected}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}

@test "old strategy names are metadata" {
    local delivery checked=0
    for delivery in open_pr push push_head ""; do
        run resolve_state_write_mode APPROVE true "${delivery}" false true
        [ "${output}" = "metadata" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 4 ]
}

@test "REJECT, missing verdict, or no changes is metadata for every delivery" {
    local delivery pair checked=0
    for delivery in pr_create pr_push none; do
        for pair in "REJECT:true" "REJECT:false" ":true" "APPROVE:false"; do
            run resolve_state_write_mode "${pair%%:*}" "${pair#*:}" "${delivery}" false true
            [ "${status}" -eq 0 ]
            [ "${output}" = "metadata" ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 12 ]
}

@test "push failure records metadata" {
    run resolve_state_write_mode APPROVE true pr_push true false
    [ "${output}" = "metadata" ]
    run resolve_state_write_mode APPROVE true pr_create true false
    [ "${output}" = "metadata" ]
    run resolve_state_write_mode APPROVE true pr_create false true
    [ "${output}" = "pending" ]
}

@test "pr_create and pr_push record metadata unless the agent branch was pushed" {
    local delivery pushed checked=0
    for delivery in pr_create pr_push; do
        for pushed in false "" "TRUE"; do
            run resolve_state_write_mode APPROVE true "${delivery}" false "${pushed}"
            [ "${status}" -eq 0 ]
            [ "${output}" = "metadata" ]
            checked=$((checked + 1))
        done
        run resolve_state_write_mode APPROVE true "${delivery}" false
        [ "${output}" = "metadata" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 8 ]
    run resolve_state_write_mode APPROVE true none false false
    [ "${output}" = "metadata" ]
}
