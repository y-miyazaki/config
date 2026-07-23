#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for .github/actions/loop-prompt-generate/lib/build_constraints.sh
#
# Use cases:
# - L1/L2/L3 map to may_edit false/true
# - allowlist-only emits may_edit false
# - empty level and allowlist emit nothing
# - invalid level fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

BUILD_CONSTRAINTS="$(bats_workspace_root)/.github/actions/loop-prompt-generate/lib/build_constraints.sh"

@test "emit_loop_constraints maps L1 to may_edit false" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "L1" "CHANGELOG.md"
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: false"* ]]
    [[ $output != *"persist edits to disk"* ]]
    [[ $output == *"Allowed paths: CHANGELOG.md."* ]]
}

@test "emit_loop_constraints maps L2 to may_edit true" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "L2" "CHANGELOG.md"
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: true"* ]]
    [[ $output == *"persist edits to disk"* ]]
}

@test "emit_loop_constraints maps L3 to may_edit true" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "L3" ""
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: true"* ]]
}

@test "emit_loop_constraints allowlist-only defaults may_edit false" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "" "CHANGELOG.md"
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: false"* ]]
    [[ $output == *"Allowed paths: CHANGELOG.md."* ]]
}

@test "emit_loop_constraints rejects invalid level" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "L0" "CHANGELOG.md"
    [ "$status" -eq 1 ]
}

@test "emit_loop_constraints emits nothing when inputs are empty" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "" ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
