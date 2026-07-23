#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/sync_loop_contract.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

SYNC_SCRIPT="$(bats_workspace_root)/scripts/self/apm/sync_loop_contract.sh"

@test "sync_loop_contract --check passes when portable sources match skill copies" {
    run bash "${SYNC_SCRIPT}" --check
    [ "$status" -eq 0 ]
    [[ $output == *"OK: All loop contract mirrors are in sync."* ]]
}

@test "sync_loop_contract --help exits successfully" {
    run bash "${SYNC_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"sync_loop_contract.sh"* ]]
}
