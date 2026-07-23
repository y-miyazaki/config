#!/usr/bin/env bats

# Tests for .github/actions/loop-prompt-generate/lib/validate_loop_write_contract.sh
#
# Use cases:
# - normative may_edit × write_target × delivery × level combinations
# - enum rejection for invalid caller fields
# - L1 read-only routing rejects may_edit true

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

VALIDATE_LIB="$(bats_workspace_root)/.github/actions/loop-prompt-generate/lib/validate_loop_write_contract.sh"

setup() {
    # shellcheck disable=SC1090
    source "${VALIDATE_LIB}"
}

@test "validate accepts may_edit false delivery log at L1" {
    run validate_loop_write_contract "false" "" "log" "L1"
    [ "$status" -eq 0 ]
}

@test "validate accepts may_edit false delivery none at L1" {
    run validate_loop_write_contract "false" "" "none" "L1"
    [ "$status" -eq 0 ]
}

@test "validate accepts may_edit true write_target fix delivery none at L2" {
    run validate_loop_write_contract "true" "fix" "none" "L2"
    [ "$status" -eq 0 ]
}

@test "validate accepts may_edit true write_target fix delivery open_pr at L2" {
    run validate_loop_write_contract "true" "fix" "open_pr" "L2"
    [ "$status" -eq 0 ]
}

@test "validate accepts may_edit true write_target report delivery open_pr at L2" {
    run validate_loop_write_contract "true" "report" "open_pr" "L2"
    [ "$status" -eq 0 ]
}

@test "validate rejects empty may_edit" {
    run validate_loop_write_contract "" "fix" "open_pr" "L2"
    [ "$status" -eq 1 ]
    [[ $output == *"may_edit is required"* ]]
}

@test "validate rejects invalid delivery" {
    run validate_loop_write_contract "true" "fix" "slack" "L2"
    [ "$status" -eq 1 ]
    [[ $output == *"delivery must be"* ]]
}

@test "validate rejects invalid level" {
    run validate_loop_write_contract "true" "fix" "open_pr" "L0"
    [ "$status" -eq 1 ]
    [[ $output == *"level must be"* ]]
}

@test "validate rejects invalid may_edit" {
    run validate_loop_write_contract "yes" "fix" "open_pr" "L2"
    [ "$status" -eq 1 ]
    [[ $output == *"may_edit must be true or false"* ]]
}

@test "validate rejects invalid write_target" {
    run validate_loop_write_contract "true" "hybrid" "open_pr" "L2"
    [ "$status" -eq 1 ]
    [[ $output == *"write_target must be fix or report"* ]]
}

@test "validate rejects L1 may_edit true write_target fix delivery open_pr" {
    run validate_loop_write_contract "true" "fix" "open_pr" "L1"
    [ "$status" -eq 1 ]
    [[ $output == *"L1 with may_edit true"* ]]
}

@test "validate rejects may_edit false delivery open_pr" {
    run validate_loop_write_contract "false" "" "open_pr" "L2"
    [ "$status" -eq 1 ]
    [[ $output == *"may_edit false"* ]]
}

@test "validate rejects may_edit true without write_target" {
    run validate_loop_write_contract "true" "" "open_pr" "L2"
    [ "$status" -eq 1 ]
}

@test "validate rejects may_edit true write_target fix delivery log" {
    run validate_loop_write_contract "true" "fix" "log" "L2"
    [ "$status" -eq 1 ]
}

@test "validate rejects may_edit true write_target report delivery issue" {
    run validate_loop_write_contract "true" "report" "issue" "L2"
    [ "$status" -eq 1 ]
}

@test "validate warns write_target ignored when may_edit false" {
    run validate_loop_write_contract "false" "fix" "log" "L1"
    [ "$status" -eq 0 ]
    [[ $output == *"write_target ignored when may_edit is false"* ]]
}
