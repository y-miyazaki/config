#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for .github/actions/loop-prompt-generate/lib/build_constraints.sh
#
# Use cases:
# - explicit may_edit and write_target emission
# - legacy L1/L2/L3 shim maps to may_edit and fix
# - allowlist-only emits may_edit false
# - empty inputs emit nothing
# - invalid level fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

BUILD_CONSTRAINTS="$(bats_workspace_root)/.github/actions/loop-prompt-generate/lib/build_constraints.sh"

@test "emit_loop_constraints emits deprecation warning for legacy level shim" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run bash -c 'source "'"${BUILD_CONSTRAINTS}"'"; emit_loop_constraints "L2" "CHANGELOG.md" 2>&1'
    [ "$status" -eq 0 ]
    [[ $output == *"emit_loop_constraints_from_level is deprecated"* ]]
    [[ $output == *"may_edit: true"* ]]
}

@test "emit_loop_constraints rejects invalid may_edit" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "yes" "fix" "CHANGELOG.md" ""
    [ "$status" -eq 1 ]
    [[ $output == *"may_edit must be true or false"* ]]
}

@test "emit_loop_constraints rejects invalid write_target when may_edit true" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "true" "hybrid" "CHANGELOG.md" ""
    [ "$status" -eq 1 ]
    [[ $output == *"write_target must be fix or report"* ]]
}

@test "emit_loop_constraints maps L1 to may_edit false" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "L1" "CHANGELOG.md"
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: false"* ]]
    [[ $output != *"write_target:"* ]]
    [[ $output == *"Allowed paths: CHANGELOG.md."* ]]
}

@test "emit_loop_constraints maps L2 to may_edit true" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "L2" "CHANGELOG.md"
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: true"* ]]
    [[ $output == *"write_target: fix"* ]]
    [[ $output == *"persist fixes within allowlist"* ]]
}

@test "emit_loop_constraints maps L3 to may_edit true" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "L3" ""
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: true"* ]]
    [[ $output == *"write_target: fix"* ]]
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

@test "emit_loop_constraints emits write_target report and report_file" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "true" "report" "docs/report/tech-debt/**/*.md" "docs/report/tech-debt/2026-07-23.md"
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: true"* ]]
    [[ $output == *"write_target: report"* ]]
    [[ $output == *"report_file: docs/report/tech-debt/2026-07-23.md"* ]]
    [[ $output == *"MUST persist report_file"* ]]
    [[ $output != *"report alone is not sufficient"* ]]
}

@test "emit_loop_constraints emits fix persistence obligation" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "true" "fix" "src/**" ""
    [ "$status" -eq 0 ]
    [[ $output == *"write_target: fix"* ]]
    [[ $output == *"persist fixes within allowlist"* ]]
    [[ $output != *"report_file:"* ]]
}

@test "emit_loop_constraints survey omits write_target" {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
    run emit_loop_constraints "false" "" "CHANGELOG.md" ""
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: false"* ]]
    [[ $output != *"write_target:"* ]]
}
