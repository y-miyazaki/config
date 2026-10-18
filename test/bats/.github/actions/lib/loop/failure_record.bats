#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/failure_record.sh

# Use cases:
# - loop_failure_record writes failure_stage and failure_message JSON
# - loop_failure_record redacts sensitive text before persistence
# - loop_failure_record truncates long messages to 500 codepoints
# - loop_failure_export_outputs writes multiline GITHUB_OUTPUT when set
# - loop_failure_export_outputs ends the message before a delimiter line (GitHub matches the whole line)
# - loop_failure_recorded is true only for a file with a non-empty failure_stage

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

@test "loop_failure_export_outputs puts the delimiter on its own line" {
    local failure_file="${FAILURE_TMP}/failure.json"
    local delim

    loop_failure_record "push" $'line one\nline two' "${failure_file}"
    loop_failure_export_outputs "${failure_file}"

    delim="$(sed -n 's/^failure_message<<//p' "${GITHUB_OUTPUT}")"
    [ -n "${delim}" ]
    [ "$(grep -cxF "${delim}" "${GITHUB_OUTPUT}")" = "1" ]
    [ "$(grep -xF -B1 "${delim}" "${GITHUB_OUTPUT}" | head -n1)" = "line two" ]
}

@test "loop_failure_export_outputs writes multiline GITHUB_OUTPUT when set" {
    local failure_file="${FAILURE_TMP}/failure.json"

    loop_failure_record "notify_context" "detect result JSON is invalid" "${failure_file}"
    loop_failure_export_outputs "${failure_file}"

    grep -q '^failure_stage=notify_context$' "${GITHUB_OUTPUT}"
    grep -q '^failure_message<<' "${GITHUB_OUTPUT}"
    grep -q 'detect result JSON is invalid' "${GITHUB_OUTPUT}"
}

@test "loop_failure_recorded fails for a missing file, malformed JSON, or an empty stage" {
    local missing="${FAILURE_TMP}/missing.json"
    local malformed="${FAILURE_TMP}/malformed.json"
    local empty_stage="${FAILURE_TMP}/empty.json"

    printf '{' > "${malformed}"
    printf '{"failure_stage":"","failure_message":"x"}' > "${empty_stage}"

    run loop_failure_recorded "${missing}"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]

    run loop_failure_recorded "${malformed}"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]

    run loop_failure_recorded "${empty_stage}"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

@test "loop_failure_recorded succeeds after loop_failure_record" {
    local f="${FAILURE_TMP}/failure.json"

    loop_failure_record "finalize_pr" "x" "${f}"
    run loop_failure_recorded "${f}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}
