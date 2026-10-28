#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/go/validate.sh
#
# Use cases:
# - determine_target_pattern fails for a missing directory instead of validating the whole repository
# - determine_target_pattern fails for a scoped directory without Go files
# - determine_target_pattern keeps ./... and accepts a scoped directory that contains Go files

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

VALIDATE_SCRIPT="$(bats_workspace_root)/scripts/go/validate.sh"

setup() {
    WORK_DIR="${BATS_TEST_TMPDIR}/work"
    mkdir -p "${WORK_DIR}/empty" "${WORK_DIR}/pkg dir"
    echo 'package x' > "${WORK_DIR}/pkg dir/a.go"
    echo 'package root' > "${WORK_DIR}/root.go"
}

@test "determine_target_pattern fails for a missing directory instead of validating the whole repository" {
    run bash -c "cd '${WORK_DIR}' && source '${VALIDATE_SCRIPT}' && determine_target_pattern missing"
    [ "$status" -ne 0 ]
    [[ $output == *"Directory not found: missing"* ]]
}

@test "determine_target_pattern fails for a scoped directory without Go files" {
    run bash -c "cd '${WORK_DIR}' && source '${VALIDATE_SCRIPT}' && determine_target_pattern empty"
    [ "$status" -ne 0 ]
    [[ $output == *"No Go files found in empty"* ]]
}

@test "determine_target_pattern keeps ./... and accepts a scoped directory that contains Go files" {
    run bash -c "cd '${WORK_DIR}' && source '${VALIDATE_SCRIPT}' && determine_target_pattern './...'"
    [ "$status" -eq 0 ]
    [ "$output" = "./..." ]

    run bash -c "cd '${WORK_DIR}' && source '${VALIDATE_SCRIPT}' && determine_target_pattern 'pkg dir'"
    [ "$status" -eq 0 ]
    [ "$output" = "./pkg dir/..." ]
}
