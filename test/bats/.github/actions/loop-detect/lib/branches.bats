#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/branches.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/_init.sh"
}

@test "split_csv trims whitespace and drops empty items" {
    local -a items=()

    split_csv " main, develop ,,release/* " items

    [ "${#items[@]}" -eq 3 ]
    [ "${items[0]}" = "main" ]
    [ "${items[1]}" = "develop" ]
    [ "${items[2]}" = "release/*" ]
}

@test "split_csv yields empty array for empty string" {
    local -a items=("stale")

    split_csv "" items

    [ "${#items[@]}" -eq 0 ]
}

@test "branch_matches_pattern list mode requires exact match" {
    LOOP_BRANCH_MATCH="list"

    run branch_matches_pattern "main" "main"
    [ "$status" -eq 0 ]

    run branch_matches_pattern "main" "mai"
    [ "$status" -ne 0 ]
}

@test "branch_matches_pattern glob mode matches release/*" {
    LOOP_BRANCH_MATCH="glob"

    run branch_matches_pattern "release/1.0" "release/*"
    [ "$status" -eq 0 ]

    run branch_matches_pattern "main" "release/*"
    [ "$status" -ne 0 ]
}

@test "branch_matches_pattern regex mode matches extended regex" {
    LOOP_BRANCH_MATCH="regex"

    run branch_matches_pattern "release/1.2.3" '^release/[0-9.]+$'
    [ "$status" -eq 0 ]

    run branch_matches_pattern "feature/x" '^release/[0-9.]+$'
    [ "$status" -ne 0 ]
}

@test "resolve_integration_branches falls back to base when patterns empty" {
    LOOP_BRANCH_MATCH="glob"
    INTEGRATION_BRANCHES=("stale")

    resolve_integration_branches "" "main"

    [ "${#INTEGRATION_BRANCHES[@]}" -eq 1 ]
    [ "${INTEGRATION_BRANCHES[0]}" = "main" ]
}

@test "resolve_integration_branches list mode uses patterns as-is" {
    LOOP_BRANCH_MATCH="list"
    INTEGRATION_BRANCHES=()

    resolve_integration_branches "main,develop" "main"

    [ "${#INTEGRATION_BRANCHES[@]}" -eq 2 ]
    [ "${INTEGRATION_BRANCHES[0]}" = "main" ]
    [ "${INTEGRATION_BRANCHES[1]}" = "develop" ]
}
