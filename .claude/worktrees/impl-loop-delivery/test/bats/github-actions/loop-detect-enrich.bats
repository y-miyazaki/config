#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for enrich_target_json_with_ci_context in loop-detect
#
# Use cases:
# - invalid target_json degrades to the original value instead of aborting
#   the whole detect run under set -e
# - invalid detect_result leaves target_json unchanged for ci-context enrich
# - detect-owned fields (agent_report_file) are not merged into target_json

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_LIB="$(bats_workspace_root)/.github/actions/loop-detect/lib/detect.sh"

setup() {
    # shellcheck disable=SC1090
    source "${DETECT_LIB}"
}

@test "enrich_target_json_with_ci_context degrades to original target_json when invalid" {
    local detect='{"failures":[{"workflow_run_id":"1","workflow_name":"ci","head_sha":"abc1234"}]}'
    run enrich_target_json_with_ci_context "not-json" "${detect}"
    [ "$status" -eq 0 ]
    [[ $output == *"not-json" ]]
}

@test "enrich_target_json_with_ci_context leaves target_json unchanged when detect_result is invalid" {
    local base='{"mode":"integration","key":"integration:main"}'
    run enrich_target_json_with_ci_context "${base}" "not-json"
    [ "$status" -eq 0 ]
    [ "$output" = "${base}" ]
}

@test "enrich_target_json_with_detect_fields is removed" {
    run declare -F enrich_target_json_with_detect_fields
    [ "$status" -eq 1 ]
}
