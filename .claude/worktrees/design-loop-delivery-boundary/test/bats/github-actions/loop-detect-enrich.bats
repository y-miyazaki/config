#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for enrich_target_json_with_detect_fields and
# enrich_target_json_with_ci_context in loop-detect
#
# Use cases:
# - report_file from detect JSON is merged into target_json
# - empty report_file leaves target_json unchanged
# - invalid target_json degrades to the original value instead of aborting
#   the whole detect run under set -e
# - invalid detect_result leaves target_json unchanged for ci-context enrich

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

@test "enrich_target_json_with_detect_fields adds report_file from detect result" {
    local base='{"mode":"integration","key":"integration:main","finalize":"open_pr"}'
    local detect='{"report_file":"docs/report/tech-debt/2026-07-23.md"}'
    run enrich_target_json_with_detect_fields "${base}" "${detect}"
    [ "$status" -eq 0 ]
    [[ $output == *'"report_file":"docs/report/tech-debt/2026-07-23.md"'* ]]
}

@test "enrich_target_json_with_detect_fields skips when report_file empty" {
    local base='{"mode":"integration","key":"integration:main","finalize":"open_pr"}'
    local detect='{"signals":[]}'
    run enrich_target_json_with_detect_fields "${base}" "${detect}"
    [ "$status" -eq 0 ]
    [ "$output" = "${base}" ]
}

@test "enrich_target_json_with_detect_fields degrades to original target_json when invalid" {
    # Regression guard: a failing enrich must not abort the whole detect.sh
    # run under set -e (append_detect_candidate has no `|| return 0` guard on
    # this call) — it must degrade like every other invalid-input branch.
    run enrich_target_json_with_detect_fields "not-json" '{"report_file":"x.md"}'
    [ "$status" -eq 0 ]
    [[ $output == *"not-json" ]]
}

@test "enrich_target_json_with_ci_context degrades to original target_json when invalid" {
    local detect='{"failures":[{"workflow_run_id":"1","workflow_name":"ci","head_sha":"abc1234"}]}'
    run enrich_target_json_with_ci_context "not-json" "${detect}"
    [ "$status" -eq 0 ]
    [[ $output == *"not-json" ]]
}

@test "enrich_target_json_with_ci_context leaves target_json unchanged when detect_result is invalid" {
    local base='{"mode":"integration","key":"integration:main","finalize":"open_pr"}'
    run enrich_target_json_with_ci_context "${base}" "not-json"
    [ "$status" -eq 0 ]
    [ "$output" = "${base}" ]
}
