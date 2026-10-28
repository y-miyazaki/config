#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-detect/lib/matrix.sh build_prompt_text
#
# Use cases:
# - build_prompt_text emits agent_edit_allowed derived from level via the shared build_constraints helper
# - agent_report_file from the detect JSON reaches the prompt constraints
# - the legacy detect JSON key report_file no longer reaches the prompt
# - an empty or invalid level fails prompt assembly

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

LOOP_DETECT_INIT="$(bats_workspace_root)/.github/actions/loop-detect/lib/_init.sh"

setup() {
    # shellcheck disable=SC1090,SC1091
    source "${LOOP_DETECT_INIT}"
}

@test "build_prompt_text emits agent_edit_allowed false at L1" {
    local expected
    expected=$'## Constraints\nagent_edit_allowed: false\nDo not claim files were modified unless git would show real changes.'

    run build_prompt_text "changelog" "L1" "" "" "abc" "def" "{}" "" "0" "" ""
    [ "$status" -eq 0 ]
    [[ $output == *"${expected}" ]]
}

@test "build_prompt_text emits agent_edit_allowed true at L2" {
    local expected
    expected=$'## Constraints\nagent_edit_allowed: true\nagent_edit_target: fix\nYou MUST persist fixes within allowlist; survey-only output is insufficient when agent_edit_allowed is true.\nDo not claim files were modified unless git would show real changes.\nAllowed paths: scripts/**.\nDo NOT modify any other files.'

    run build_prompt_text "ci-sweeper" "L2" "scripts/**" "" "abc" "def" "{}" "" "0" "fix" ""
    [ "$status" -eq 0 ]
    [[ $output == *"${expected}" ]]
}

@test "build_prompt_text ignores the legacy report_file detect key" {
    run build_prompt_text "tech-debt" "L2" "docs/report/**" "" "abc" "def" \
        '{"report_file":"docs/report/tech-debt/2026-07-23.md"}' "" "0" "report" ""
    [ "$status" -eq 0 ]
    [[ $output == *$'\nagent_edit_target: report\nYou MUST persist agent_report_file'* ]]
    [[ $output != *"2026-07-23.md"* ]]
}

@test "build_prompt_text reads agent_report_file from the detect JSON" {
    run build_prompt_text "tech-debt" "L2" "docs/report/**" "" "abc" "def" \
        '{"agent_report_file":"docs/report/tech-debt/2026-07-23.md"}' "" "0" "report" ""
    [ "$status" -eq 0 ]
    [[ $output == *$'\nagent_edit_target: report\nagent_report_file: docs/report/tech-debt/2026-07-23.md\n'* ]]
}

@test "build_prompt_text rejects an empty level" {
    run --separate-stderr build_prompt_text "changelog" "" "CHANGELOG.md" "" "abc" "def" "{}" "" "0" "fix" ""
    [ "$status" -eq 1 ]
    [ "$stderr" = "::error::Invalid level:  (expected L1, L2, or L3)" ]
}

@test "build_prompt_text uses an explicit agent_report_file argument over the detect JSON" {
    run build_prompt_text "tech-debt" "L2" "docs/report/**" "" "abc" "def" \
        '{"agent_report_file":"docs/report/tech-debt/from-detect.md"}' "" "0" \
        "report" "docs/report/tech-debt/explicit.md"
    [ "$status" -eq 0 ]
    [[ $output == *$'\nagent_report_file: docs/report/tech-debt/explicit.md\n'* ]]
    [[ $output != *"from-detect.md"* ]]
}
