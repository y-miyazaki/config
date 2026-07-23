#!/usr/bin/env bats

# Tests for .github/actions/lib/loop/resolve_state_file.sh
#
# Use cases:
# - explicit state_file input overrides loop_name default
# - loop_name derives .loop/state-<name>.json
# - empty output when neither input is provided
# - reject path traversal and non-loop paths

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

RESOLVE_STATE_LIB="$(bats_workspace_root)/.github/actions/lib/loop/resolve_state_file.sh"

setup() {
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
}

@test "resolve_state_file uses explicit state_file input" {
    # shellcheck disable=SC1090
    source "${RESOLVE_STATE_LIB}"
    run bash -c 'source "'"${RESOLVE_STATE_LIB}"'"; LOOP_NAME=changelog STATE_FILE_INPUT=.loop/state-custom.json GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_state_file'
    [ "$status" -eq 0 ]
    grep -q '^state_file=.loop/state-custom.json$' "${GITHUB_OUTPUT}"
}

@test "resolve_state_file derives path from loop_name" {
    # shellcheck disable=SC1090
    source "${RESOLVE_STATE_LIB}"
    run bash -c 'source "'"${RESOLVE_STATE_LIB}"'"; LOOP_NAME=docs-triage STATE_FILE_INPUT= GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_state_file'
    [ "$status" -eq 0 ]
    grep -q '^state_file=.loop/state-docs-triage.json$' "${GITHUB_OUTPUT}"
}

@test "resolve_state_file emits empty path when inputs missing" {
    # shellcheck disable=SC1090
    source "${RESOLVE_STATE_LIB}"
    run bash -c 'source "'"${RESOLVE_STATE_LIB}"'"; LOOP_NAME= STATE_FILE_INPUT= GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_state_file'
    [ "$status" -eq 0 ]
    grep -q '^state_file=$' "${GITHUB_OUTPUT}"
}

@test "resolve_state_file rejects path traversal" {
    # shellcheck disable=SC1090
    source "${RESOLVE_STATE_LIB}"
    run bash -c 'source "'"${RESOLVE_STATE_LIB}"'"; LOOP_NAME= STATE_FILE_INPUT=.loop/../outside.json GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_state_file'
    [ "$status" -eq 1 ]
    [[ $output == *"must not contain '..'"* ]]
}

@test "resolve_state_file rejects non-loop state path pattern" {
    # shellcheck disable=SC1090
    source "${RESOLVE_STATE_LIB}"
    run bash -c 'source "'"${RESOLVE_STATE_LIB}"'"; LOOP_NAME= STATE_FILE_INPUT=state.json GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" resolve_state_file'
    [ "$status" -eq 1 ]
    [[ $output == *"must match .loop/state-<name>.json"* ]]
}
