#!/usr/bin/env bats

# Tests for .github/actions/lib/loop/_resolve.sh
#
# Use cases:
# - GITHUB_ACTION_PATH resolves ../lib/loop when set
# - BASH_SOURCE fallback resolves sibling lib/loop directory
# - LOOP_ACTION_LIB_DIR is idempotent when already set

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

RESOLVE_LIB="$(bats_workspace_root)/.github/actions/lib/loop/_resolve.sh"

@test "resolve uses GITHUB_ACTION_PATH when set" {
    local action_root="${BATS_TEST_TMPDIR}/actions/loop-detect"
    mkdir -p "${action_root}/../lib/loop"
    touch "${action_root}/../lib/loop/_resolve.sh"

    run bash -c 'export GITHUB_ACTION_PATH="'"${action_root}"'"; unset LOOP_ACTION_LIB_DIR; source "'"${RESOLVE_LIB}"'"; printf "%s" "${LOOP_ACTION_LIB_DIR}"'
    [ "$status" -eq 0 ]
    [[ $output == *"/lib/loop" ]]
}

@test "resolve uses BASH_SOURCE directory when GITHUB_ACTION_PATH unset" {
    run bash -c 'unset GITHUB_ACTION_PATH LOOP_ACTION_LIB_DIR; source "'"${RESOLVE_LIB}"'"; printf "%s" "${LOOP_ACTION_LIB_DIR}"'
    [ "$status" -eq 0 ]
    [[ $output == *"/.github/actions/lib/loop" ]]
}

@test "resolve keeps existing LOOP_ACTION_LIB_DIR" {
    run bash -c 'export LOOP_ACTION_LIB_DIR="/tmp/custom-lib"; source "'"${RESOLVE_LIB}"'"; printf "%s" "${LOOP_ACTION_LIB_DIR}"'
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/custom-lib" ]
}
