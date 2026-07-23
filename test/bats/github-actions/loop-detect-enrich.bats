#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for enrich_target_json_with_detect_fields in loop-detect
#
# Use cases:
# - report_file from detect JSON is merged into target_json
# - empty report_file leaves target_json unchanged
# - invalid target_json fails closed

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

@test "enrich_target_json_with_detect_fields rejects invalid target_json" {
    run enrich_target_json_with_detect_fields "not-json" '{"report_file":"x.md"}'
    [ "$status" -eq 1 ]
}
