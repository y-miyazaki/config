#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/export_failure_diag.sh

# Use cases:
# - main exports failure diagnostics from LOOP_FAILURE_FILE
# - main resolves STATUS_DIR/failure.json when LOOP_FAILURE_FILE is unset
# - main no-ops when failure file is missing

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/failure_record.sh"
    EXPORT_TMP="$(mktemp -d)"
    export EXPORT_TMP
    GITHUB_OUTPUT="$(mktemp)"
    export GITHUB_OUTPUT
    EXPORT_SCRIPT="$(bats_workspace_root)/.github/actions/lib/loop/export_failure_diag.sh"
}

teardown() {
    rm -rf "${EXPORT_TMP}"
    rm -f "${GITHUB_OUTPUT:-}"
}

@test "main exports failure diagnostics from LOOP_FAILURE_FILE" {
    local failure_file="${EXPORT_TMP}/failure.json"

    loop_failure_record "finalize_pr" "already exists" "${failure_file}"
    LOOP_FAILURE_FILE="${failure_file}" STATUS_DIR="" run bash "${EXPORT_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q '^failure_stage=finalize_pr$' "${GITHUB_OUTPUT}"
    grep -q 'already exists' "${GITHUB_OUTPUT}"
}

@test "main resolves STATUS_DIR failure.json when LOOP_FAILURE_FILE is unset" {
    local status_dir="${EXPORT_TMP}/status"

    mkdir -p "${status_dir}"
    loop_failure_record "push" "remote rejected" "${status_dir}/failure.json"
    LOOP_FAILURE_FILE="" STATUS_DIR="${status_dir}" run bash "${EXPORT_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q '^failure_stage=push$' "${GITHUB_OUTPUT}"
}

@test "main no-ops when failure file is missing" {
    LOOP_FAILURE_FILE="${EXPORT_TMP}/missing.json" STATUS_DIR="" run bash "${EXPORT_SCRIPT}"
    [ "$status" -eq 0 ]
    [ ! -s "${GITHUB_OUTPUT}" ]
}
