#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/state.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/state.sh"
}

@test "target_pending_blocks_detect returns true when pending cursor exists" {
    local target_state='{"pending":{"pr":42,"sha":"abc123"}}'
    run target_pending_blocks_detect "${target_state}"
    [ "$status" -eq 0 ]
}

@test "target_pending_blocks_detect returns false when pending is absent" {
    local target_state='{"last_sha":"abc123"}'
    run target_pending_blocks_detect "${target_state}"
    [ "$status" -eq 1 ]
}
