#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for apply_scoped_pr_number_filter in loop-detect
#
# Use cases:
# - 0 sentinel leaves watch lists unchanged (optional workflow_call number input)
# - non-zero scoped PR clears integration watch and filters PR list

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_LIB="$(bats_workspace_root)/.github/actions/loop-detect/lib/detect.sh"

setup() {
    # shellcheck disable=SC1090
    source "${DETECT_LIB}"
}

@test "apply_scoped_pr_number_filter treats 0 as unset" {
    INTEGRATION_BRANCHES=("main")
    OPEN_PRS_JSON=('{"number":42,"headRefName":"feat"}')

    apply_scoped_pr_number_filter "0"

    [[ ${INTEGRATION_BRANCHES[0]} == "main" ]]
    [[ ${#OPEN_PRS_JSON[@]} -eq 1 ]]
}

@test "apply_scoped_pr_number_filter keeps only matching PR" {
    INTEGRATION_BRANCHES=("main")
    OPEN_PRS_JSON=(
        '{"number":41,"headRefName":"other"}'
        '{"number":42,"headRefName":"feat"}'
    )

    apply_scoped_pr_number_filter "42"

    [[ ${#INTEGRATION_BRANCHES[@]} -eq 0 ]]
    [[ ${#OPEN_PRS_JSON[@]} -eq 1 ]]
    [[ ${OPEN_PRS_JSON[0]} == *'"number":42'* ]]
}
