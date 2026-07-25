#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for scripts/lib/common.sh

# Use cases:
# - execute_command executes the command and logs when VERBOSE=true
# - execute_command in dry-run mode only logs planned command
# - is_dry_run returns non-zero when DRY_RUN is false/unset
# - is_dry_run returns success when DRY_RUN=true
# - log prints ERROR messages regardless of VERBOSE
# - validate_dependencies reports missing tools on stdout
# - require_dependencies exits 1 when tools are missing

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/lib/common.sh"
}

@test "execute_command executes the command and logs when VERBOSE=true" {
    DRY_RUN=false
    VERBOSE=true
    run execute_command echo hi_there
    [ "$status" -eq 0 ]
    # Should include the debug log line about Executing and the command output
    [[ $output == *"Executing: echo hi_there"* ]]
    [[ $output == *"hi_there"* ]]
}

@test "execute_command in dry-run mode only logs planned command" {
    DRY_RUN=true
    run execute_command echo hello world
    [ "$status" -eq 0 ]
    # Use substring match to avoid regex quoting issues
    [[ $output == *"DRY-RUN: Would execute: echo hello world"* ]]
}

@test "is_dry_run returns non-zero when DRY_RUN is false/unset" {
    unset DRY_RUN
    run is_dry_run
    [ "$status" -ne 0 ]
}

@test "is_dry_run returns success when DRY_RUN=true" {
    DRY_RUN=true
    run is_dry_run
    [ "$status" -eq 0 ]
}

@test "log prints ERROR messages regardless of VERBOSE" {
    unset VERBOSE
    run log ERROR "fatal"
    [ "$status" -eq 0 ]
    [[ $output == *"[ERROR] fatal"* ]]
}

@test "validate_dependencies reports missing tools on stdout" {
    run validate_dependencies bash __missing_tool_xyz__
    [ "$status" -eq 1 ]
    [[ $output == "__missing_tool_xyz__" ]]
}

@test "require_dependencies exits 1 when tools are missing" {
    run --separate-stderr require_dependencies bash __missing_tool_xyz__
    [ "$status" -eq 1 ]
    [[ ${stderr} == *"Missing required tools"*__missing_tool_xyz__* ]]
}
