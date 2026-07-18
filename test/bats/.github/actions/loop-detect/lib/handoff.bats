#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/handoff.sh
#
# Use cases:
# - loop_handoff_write_bundle writes manifest and per-target payload files
# - loop_handoff_read_detect_result and loop_handoff_read_verifier_context load payloads
# - loop_handoff_resolve_detect_result_json prefers inline JSON over artifact files
# - loop_handoff_resolve_detect_result_json falls back to artifact when DETECT_RESULT_JSON is unset
# - loop_handoff_resolve_detect_result_json returns empty object when no source
# - loop_handoff_write_candidate_payload rejects invalid candidate JSON
# - loop_handoff_write_bundle returns error when payload write fails
# - loop_handoff_read_payload returns error when payload file is missing
# - loop_handoff_read_payload returns error when payload is invalid JSON
# - loop_handoff_resolve_detect_result_json returns empty object when handoff_key mismatches

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/handoff.sh"
    HANDOFF_DIR="${BATS_TEST_TMPDIR}/loop-handoff"
}

@test "loop_handoff_read_detect_result loads payload by key" {
    local candidate

    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"","result":{"since":"abc","commits":[{"sha":"deadbeef","type":"feat","scope":"","breaking":false,"subject":"x"}]}}'
    loop_handoff_write_bundle "${HANDOFF_DIR}" "${candidate}"

    run loop_handoff_read_detect_result "${HANDOFF_DIR}" "integration:main"
    [ "$status" -eq 0 ]
    run jq -e '.since == "abc" and .commits[0].subject == "x"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "loop_handoff_read_verifier_context loads markdown from payload" {
    local candidate

    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"## CI Failures","result":{"skip":false}}'
    loop_handoff_write_bundle "${HANDOFF_DIR}" "${candidate}"

    run loop_handoff_read_verifier_context "${HANDOFF_DIR}" "integration:main"
    [ "$status" -eq 0 ]
    [ "$output" = "## CI Failures" ]
}

@test "loop_handoff_resolve_detect_result_json loads from handoff when inline empty" {
    local candidate

    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"","result":{"from":"artifact"}}'
    loop_handoff_write_bundle "${HANDOFF_DIR}" "${candidate}"

    export DETECT_RESULT_JSON="{}"
    export LOOP_HANDOFF_DIR="${HANDOFF_DIR}"
    export HANDOFF_KEY="integration:main"

    run loop_handoff_resolve_detect_result_json
    [ "$status" -eq 0 ]
    run jq -e '.from == "artifact"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "loop_handoff_resolve_detect_result_json prefers inline JSON" {
    local inline

    inline='{"inline":true}'
    export DETECT_RESULT_JSON="${inline}"
    export LOOP_HANDOFF_DIR="${HANDOFF_DIR}"
    export HANDOFF_KEY="integration:main"

    run loop_handoff_resolve_detect_result_json
    [ "$status" -eq 0 ]
    [ "$output" = "${inline}" ]
}

@test "loop_handoff_resolve_detect_result_json falls back to artifact when DETECT_RESULT_JSON is unset" {
    local candidate

    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"","result":{"from":"artifact"}}'
    loop_handoff_write_bundle "${HANDOFF_DIR}" "${candidate}"

    unset DETECT_RESULT_JSON
    export LOOP_HANDOFF_DIR="${HANDOFF_DIR}"
    export HANDOFF_KEY="integration:main"

    run loop_handoff_resolve_detect_result_json
    [ "$status" -eq 0 ]
    run jq -e '.from == "artifact"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "loop_handoff_resolve_detect_result_json returns empty object when no source" {
    unset DETECT_RESULT_JSON LOOP_HANDOFF_DIR HANDOFF_KEY

    run loop_handoff_resolve_detect_result_json
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}

@test "loop_handoff_write_candidate_payload rejects invalid candidate JSON" {
    run loop_handoff_write_candidate_payload "${HANDOFF_DIR}" 'not-json'
    [ "$status" -eq 1 ]
}

@test "loop_handoff_write_bundle returns error when payload write fails" {
    local handoff_dir repo_root

    handoff_dir="${BATS_TEST_TMPDIR}/loop-handoff-fail"
    repo_root="$(bats_workspace_root)"
    export HANDOFF_FAIL_CANDIDATE='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"","result":{}}'

    run bash -c '
        set -euo pipefail
        # shellcheck disable=SC1091
        source "'"${repo_root}"'/.github/actions/loop-detect/lib/handoff.sh"
        loop_handoff_write_candidate_payload() { return 1; }
        loop_handoff_write_bundle "'"${handoff_dir}"'" "${HANDOFF_FAIL_CANDIDATE}"
    '
    [ "$status" -eq 1 ]
    [[ $output == *"failed to write payload"* ]]
    [ ! -f "${handoff_dir}/manifest.json" ]
}

@test "loop_handoff_write_bundle writes manifest and per-key payloads" {
    local -a candidates=(
        '{"target_json":{"key":"integration:main"},"prompt":"p1","verifier_context":"vc1","result":{"skip":false,"commits":[]}}'
        '{"target_json":{"key":"pull_request:42"},"prompt":"p2","verifier_context":"vc2","result":{"skip":false,"failures":[]}}'
    )

    loop_handoff_write_bundle "${HANDOFF_DIR}" "${candidates[@]}"

    [ -f "${HANDOFF_DIR}/manifest.json" ]
    run jq -e '.version == 1 and (.keys | length) == 2' "${HANDOFF_DIR}/manifest.json"
    [ "$status" -eq 0 ]
    [ -f "${HANDOFF_DIR}/payloads/integration_main.json" ]
    [ -f "${HANDOFF_DIR}/payloads/pull_request_42.json" ]
    run jq -e '.result.skip == false and .verifier_context == "vc1"' \
        "${HANDOFF_DIR}/payloads/integration_main.json"
    [ "$status" -eq 0 ]
}

@test "loop_handoff_read_payload returns error when payload file is missing" {
    run loop_handoff_read_payload "${HANDOFF_DIR}" "integration:main"
    [ "$status" -eq 1 ]
}

@test "loop_handoff_read_payload returns error when payload is invalid JSON" {
    mkdir -p "${HANDOFF_DIR}/payloads"
    printf 'not-json' > "${HANDOFF_DIR}/payloads/integration_main.json"
    run loop_handoff_read_payload "${HANDOFF_DIR}" "integration:main"
    [ "$status" -eq 1 ]
}

@test "loop_handoff_resolve_detect_result_json returns empty object when handoff_key mismatches" {
    local candidate

    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"","result":{"from":"artifact"}}'
    loop_handoff_write_bundle "${HANDOFF_DIR}" "${candidate}"

    export DETECT_RESULT_JSON="{}"
    export LOOP_HANDOFF_DIR="${HANDOFF_DIR}"
    export HANDOFF_KEY="integration:other"

    run loop_handoff_resolve_detect_result_json
    [ "$status" -eq 0 ]
    [ "$output" = "{}" ]
}
