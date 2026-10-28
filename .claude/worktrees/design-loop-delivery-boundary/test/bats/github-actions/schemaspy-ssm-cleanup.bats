#!/usr/bin/env bats

# Tests for .github/actions/schemaspy-ssm-cleanup/lib/cleanup.sh
#
# Use cases:
# - no-op when SSM_PID is unset
# - no-op when process is not running
# - terminates a running background process

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/aws_mock.bash"

CLEANUP_LIB="$(bats_workspace_root)/.github/actions/schemaspy-ssm-cleanup/lib/cleanup.sh"

setup() {
    mock_aws_setup
    unset SSM_PID
}

teardown() {
    mock_aws_teardown
}

@test "cleanup_ssm_port_forward no-ops when ssm pid is unset" {
    # shellcheck disable=SC1090
    source "${CLEANUP_LIB}"
    run bash -c 'source "'"${CLEANUP_LIB}"'"; unset SSM_PID; cleanup_ssm_port_forward'
    [ "$status" -eq 0 ]
    [[ $output == *"No active SSM session to clean up"* ]]
}

@test "cleanup_ssm_port_forward no-ops when process is not running" {
    # shellcheck disable=SC1090
    source "${CLEANUP_LIB}"
    run bash -c 'source "'"${CLEANUP_LIB}"'"; SSM_PID=999999 cleanup_ssm_port_forward'
    [ "$status" -eq 0 ]
    [[ $output == *"No active SSM session to clean up"* ]]
}

@test "cleanup_ssm_port_forward rejects invalid ssm pid" {
    # shellcheck disable=SC1090
    source "${CLEANUP_LIB}"
    run bash -c 'source "'"${CLEANUP_LIB}"'"; SSM_PID="not-a-pid" cleanup_ssm_port_forward'
    [ "$status" -eq 1 ]
    [[ $output == *"invalid SSM_PID"* ]]
}

@test "cleanup_ssm_port_forward terminates running process" {
    # shellcheck disable=SC1090
    source "${CLEANUP_LIB}"
    run bash -c 'source "'"${CLEANUP_LIB}"'"; /bin/sleep 300 & SSM_PID=$!; cleanup_ssm_port_forward; kill -0 "${SSM_PID}" 2>/dev/null && exit 1 || exit 0'
    [ "$status" -eq 0 ]
    [[ $output == *"SSM session terminated successfully"* ]]
}
