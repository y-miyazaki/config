#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for .github/actions/lib/loop/build_constraints.sh
#
# Use cases:
# - agent_edit_allowed is derived from level (L1 false, L2/L3 true)
# - agent_edit_target and agent_report_file emission for fix and report
# - agent_edit_allowlist "**" is byte-identical to an empty allowlist
# - a concrete allowlist emits the Allowed paths line
# - old keys (may_edit, write_target, report_file) are never emitted
# - invalid level or agent_edit_target fails
# - removed level shim functions no longer exist

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

BUILD_CONSTRAINTS="$(bats_workspace_root)/.github/actions/lib/loop/build_constraints.sh"

setup() {
    # shellcheck disable=SC1090
    source "${BUILD_CONSTRAINTS}"
}

@test "emit_loop_constraints L1 emits agent_edit_allowed false without agent_edit_target" {
    run emit_loop_constraints "L1" "" "CHANGELOG.md" ""
    [ "$status" -eq 0 ]
    [[ $output == *"agent_edit_allowed: false"* ]]
    [[ $output != *"agent_edit_target"* ]]
    [[ $output == *"Allowed paths: CHANGELOG.md."* ]]
}

@test "emit_loop_constraints L1 ignores agent_edit_target" {
    run emit_loop_constraints "L1" "fix" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"agent_edit_allowed: false"* ]]
    [[ $output != *"agent_edit_target"* ]]
}

@test "emit_loop_constraints L2 fix emits agent_edit_allowed true and agent_edit_target fix" {
    run emit_loop_constraints "L2" "fix" "src/**" ""
    [ "$status" -eq 0 ]
    [[ $output == *"agent_edit_allowed: true"* ]]
    [[ $output == *"agent_edit_target: fix"* ]]
    [[ $output == *"persist fixes within allowlist"* ]]
    [[ $output != *"agent_report_file"* ]]
}

@test "emit_loop_constraints L2 report emits agent_report_file" {
    run emit_loop_constraints "L2" "report" "docs/report/tech-debt/**/*.md" "docs/report/tech-debt/2026-07-23.md"
    [ "$status" -eq 0 ]
    [[ $output == *"agent_edit_allowed: true"* ]]
    [[ $output == *"agent_edit_target: report"* ]]
    [[ $output == *"agent_report_file: docs/report/tech-debt/2026-07-23.md"* ]]
    [[ $output == *"MUST persist agent_report_file"* ]]
}

@test "emit_loop_constraints L3 fix emits agent_edit_allowed true" {
    run emit_loop_constraints "L3" "fix" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"agent_edit_allowed: true"* ]]
    [[ $output == *"agent_edit_target: fix"* ]]
}

@test "emit_loop_constraints never emits old keys" {
    local level target allowlist report_file combos=0
    for level in L1 L2 L3; do
        for target in fix report; do
            for allowlist in "" "**" "docs/**"; do
                for report_file in "" "docs/r.md"; do
                    run emit_loop_constraints "${level}" "${target}" "${allowlist}" "${report_file}"
                    [ "$status" -eq 0 ]
                    [[ $output != *"may_edit"* ]]
                    [[ $output != *"write_target"* ]]
                    [[ $output != *$'\nreport_file:'* ]]
                    combos=$((combos + 1))
                done
            done
        done
    done
    [ "${combos}" -eq 36 ]
}

@test "emit_loop_constraints rejects empty and invalid level" {
    run emit_loop_constraints "L0" "fix" "" ""
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid level: L0"* ]]
    run emit_loop_constraints "" "fix" "" ""
    [ "$status" -eq 1 ]
}

@test "emit_loop_constraints rejects invalid agent_edit_target when edit allowed" {
    run emit_loop_constraints "L2" "hybrid" "CHANGELOG.md" ""
    [ "$status" -eq 1 ]
    [[ $output == *"agent_edit_target must be fix or report"* ]]
}

@test "emit_loop_constraints treats double-star allowlist as empty byte for byte" {
    local expected
    expected=$'## Constraints\nagent_edit_allowed: true\nagent_edit_target: fix\nYou MUST persist fixes within allowlist; survey-only output is insufficient when agent_edit_allowed is true.\nDo not claim files were modified unless git would show real changes.'
    run emit_loop_constraints "L2" "fix" "" ""
    [ "$status" -eq 0 ]
    [ "$output" = "${expected}" ]
    run emit_loop_constraints "L2" "fix" "**" ""
    [ "$status" -eq 0 ]
    [ "$output" = "${expected}" ]
    [[ $output != *"Allowed paths:"* ]]
}

@test "emit_loop_constraints with concrete allowlist emits Allowed paths line" {
    run emit_loop_constraints "L2" "fix" "docs/**" ""
    [ "$status" -eq 0 ]
    [[ $output == *"Allowed paths: docs/**."* ]]
    [[ $output == *"Do NOT modify any other files."* ]]
}

@test "level shim functions are removed" {
    run declare -f emit_loop_constraints_from_level
    [ "$status" -ne 0 ]
    run declare -f emit_loop_constraints_legacy
    [ "$status" -ne 0 ]
}
