#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for .github/actions/loop-detect/lib/matrix.sh build_prompt_text
#
# Use cases:
# - build_prompt_text emits may_edit from shared build_constraints helper
# - L1 survey prompts include may_edit false

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

LOOP_DETECT_INIT="$(bats_workspace_root)/.github/actions/loop-detect/lib/_init.sh"

setup() {
    # shellcheck disable=SC1090,SC1091
    source "${LOOP_DETECT_INIT}"
}

@test "build_prompt_text emits may_edit false at L1" {
    run build_prompt_text "changelog" "L1" "CHANGELOG.md" "" "abc" "def" "{}" "" "0"
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: false"* ]]
    [[ $output == *"## Constraints"* ]]
}

@test "build_prompt_text emits may_edit true at L2" {
    run build_prompt_text "ci-sweeper" "L2" "scripts/**" "" "abc" "def" "{}" "" "0"
    [ "$status" -eq 0 ]
    [[ $output == *"may_edit: true"* ]]
    [[ $output == *"persist edits to disk"* ]]
}
