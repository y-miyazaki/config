#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/failure_record.sh

# Use cases:
# - loop_failure_record writes failure_stage and failure_message JSON
# - loop_failure_record redacts sensitive text before persistence
# - loop_failure_record truncates long messages to 500 codepoints
# - loop_failure_export_outputs writes multiline GITHUB_OUTPUT when set

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/failure_record.sh"
    FAILURE_TMP="$(mktemp -d)"
    export FAILURE_TMP
    GITHUB_OUTPUT="$(mktemp)"
    export GITHUB_OUTPUT
}

teardown() {
    rm -rf "${FAILURE_TMP}"
    rm -f "${GITHUB_OUTPUT:-}"
}

@test "loop_failure_record writes failure_stage and failure_message JSON" {
    local failure_file="${FAILURE_TMP}/failure.json"

    loop_failure_record "push" "remote rejected" "${failure_file}"
    [ "$(jq -r '.failure_stage' "${failure_file}")" = "push" ]
    [ "$(jq -r '.failure_message' "${failure_file}")" = "remote rejected" ]
}

@test "loop_failure_record redacts sensitive text before persistence" {
    local failure_file="${FAILURE_TMP}/failure.json"
    local message='auth failed: x-access-token:ghp_abcdefghijklmnopqrstuvwxyz'

    loop_failure_record "push" "${message}" "${failure_file}"
    [[ "$(jq -r '.failure_message' "${failure_file}")" == *"[REDACTED]"* ]]
    [[ "$(jq -r '.failure_message' "${failure_file}")" != *"ghp_"* ]]
}

@test "loop_failure_record truncates long messages to 500 codepoints" {
    local failure_file="${FAILURE_TMP}/failure.json"
    local long_message

    long_message="$(printf 'a%.0s' {1..600})"
    loop_failure_record "push" "${long_message}" "${failure_file}"
    [ "$(jq -r '.failure_message | length' "${failure_file}")" -eq 500 ]
}

@test "loop_failure_export_outputs writes multiline GITHUB_OUTPUT when set" {
    local failure_file="${FAILURE_TMP}/failure.json"

    loop_failure_record "notify_context" "detect result JSON is invalid" "${failure_file}"
    loop_failure_export_outputs "${failure_file}"

    grep -q '^failure_stage=notify_context$' "${GITHUB_OUTPUT}"
    grep -q '^failure_message<<' "${GITHUB_OUTPUT}"
    grep -q 'detect result JSON is invalid' "${GITHUB_OUTPUT}"
}
