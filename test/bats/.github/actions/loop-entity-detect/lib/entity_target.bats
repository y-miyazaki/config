#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-entity-detect/lib/entity_target.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ENTITY_TARGET_SH="$(bats_workspace_root)/.github/actions/loop-entity-detect/lib/entity_target.sh"
    # shellcheck disable=SC1090,SC1091
    source "${ENTITY_TARGET_SH}"
}

@test "build_entity_target_matrix returns empty array when skip true" {
    printf '%s' '{"status":"ok","skip":true,"result":{}}' > "${BATS_TEST_TMPDIR}/d.json"
    run build_entity_target_matrix "${BATS_TEST_TMPDIR}/d.json" "issue-triage" "issue-triage" "triage pls" "L1" "none"
    [ "$status" -eq 0 ]
    run jq -e 'type == "array" and length == 0' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "build_entity_target_matrix uses detect handoff_key" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7","issue_number":7},"verifier_context":"Issue #7"}' \
        > "${BATS_TEST_TMPDIR}/d.json"
    run build_entity_target_matrix "${BATS_TEST_TMPDIR}/d.json" "issue-triage" "issue-triage" "do triage" "L1" "none"
    [ "$status" -eq 0 ]
    run jq -e 'length == 1 and .[0].handoff_key == "entity:issue:7"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "build_entity_target_matrix fails when skip false and handoff_key missing" {
    printf '%s' '{"status":"ok","skip":false,"result":{"issue_number":7}}' > "${BATS_TEST_TMPDIR}/d.json"
    run build_entity_target_matrix "${BATS_TEST_TMPDIR}/d.json" "issue-triage" "issue-triage" "x" "L1" "none"
    [ "$status" -ne 0 ]
}

@test "build_entity_target_matrix sets finalize none when delivery is none" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7"}}' \
        > "${BATS_TEST_TMPDIR}/d.json"
    run build_entity_target_matrix "${BATS_TEST_TMPDIR}/d.json" "issue-triage" "issue-triage" "x" "L1" "none"
    [ "$status" -eq 0 ]
    run jq -e '.[0].target_json.finalize == "none"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "build_entity_target_matrix sets finalize open_pr when delivery is open_pr" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7"}}' \
        > "${BATS_TEST_TMPDIR}/d.json"
    run build_entity_target_matrix "${BATS_TEST_TMPDIR}/d.json" "issue-autofix" "issue-autofix" "x" "L3" "open_pr"
    [ "$status" -eq 0 ]
    run jq -e '.[0].target_json.finalize == "open_pr"' <<< "${output}"
    [ "$status" -eq 0 ]
}
