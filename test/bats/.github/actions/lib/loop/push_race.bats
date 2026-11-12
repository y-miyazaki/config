#!/usr/bin/env bats

# Tests for .github/actions/lib/loop/push_race.sh
#
# Use cases:
# - push_race_is_error matches fetch first and non-fast-forward rejections
# - push_race_is_error rejects a remote rejected push and unrelated errors

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/push_race.sh"
}

@test "push_race_is_error matches fetch first and non-fast-forward" {
    run push_race_is_error " ! [rejected]        HEAD -> main (fetch first)"
    [ "$status" -eq 0 ]
    run push_race_is_error " ! [rejected]        HEAD -> main (non-fast-forward)"
    [ "$status" -eq 0 ]
}

@test "push_race_is_error rejects remote rejected and unrelated errors" {
    run push_race_is_error " ! [remote rejected] HEAD -> main (push declined due to repository rule violations)"
    [ "$status" -eq 1 ]
    run push_race_is_error "fatal: unable to access the remote"
    [ "$status" -eq 1 ]
}
