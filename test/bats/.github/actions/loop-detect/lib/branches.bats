#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/branches.sh

# Use cases:
# - split_csv trims whitespace and drops empty items
# - split_csv yields empty array for empty string
# - branch_matches_pattern list mode requires exact match
# - branch_matches_pattern glob mode matches release/*
# - branch_matches_pattern regex mode matches extended regex
# - resolve_integration_branches yields no branches when patterns are empty (no state_branch fallback)
# - resolve_integration_branches list mode uses patterns as-is

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
    DETECT_BRANCH_MATCH_MODE="list"

    run branch_matches_pattern "main" "main"
    [ "$status" -eq 0 ]

    run branch_matches_pattern "main" "mai"
    [ "$status" -ne 0 ]
}

@test "branch_matches_pattern glob mode matches release/*" {
    DETECT_BRANCH_MATCH_MODE="glob"

    run branch_matches_pattern "release/1.0" "release/*"
    [ "$status" -eq 0 ]

    run branch_matches_pattern "main" "release/*"
    [ "$status" -ne 0 ]
}

@test "branch_matches_pattern regex mode matches extended regex" {
    DETECT_BRANCH_MATCH_MODE="regex"

    run branch_matches_pattern "release/1.2.3" '^release/[0-9.]+$'
    [ "$status" -eq 0 ]

    run branch_matches_pattern "feature/x" '^release/[0-9.]+$'
    [ "$status" -ne 0 ]
}

@test "resolve_integration_branches yields no branches when patterns are empty" {
    local mode checked=0

    STATE_BRANCH="main"
    for mode in list glob regex; do
        DETECT_BRANCH_MATCH_MODE="${mode}"
        INTEGRATION_BRANCHES=("stale")

        resolve_integration_branches ""

        [ "${#INTEGRATION_BRANCHES[@]}" -eq 0 ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}

@test "resolve_integration_branches list mode uses patterns as-is" {
    DETECT_BRANCH_MATCH_MODE="list"
    INTEGRATION_BRANCHES=()

    resolve_integration_branches "main,develop"

    [ "${#INTEGRATION_BRANCHES[@]}" -eq 2 ]
    [ "${INTEGRATION_BRANCHES[0]}" = "main" ]
    [ "${INTEGRATION_BRANCHES[1]}" = "develop" ]
}
