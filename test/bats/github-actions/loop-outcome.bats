#!/usr/bin/env bats

# Tests for .github/actions/lib/loop/outcome.sh
#
# Use cases:
# - normalize_outcome maps each old persisted outcome to its new name
# - normalize_outcome passes new names, unknown values, and empty input through unchanged
# - outcome_counter_effect maps rejected and pr_closed (old and new names) to increment, watch and error to keep, every other outcome to reset
# - outcome_is_prune_terminal succeeds only for rejected and pr_closed (old and new names)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

OUTCOME_LIB="$(bats_workspace_root)/.github/actions/lib/loop/outcome.sh"

setup() {
    # shellcheck disable=SC1090
    source "${OUTCOME_LIB}"
}

@test "normalize_outcome: empty value passes through unchanged" {
    run normalize_outcome ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "normalize_outcome: error passes through unchanged" {
    run normalize_outcome "error"
    [ "$status" -eq 0 ]
    [ "$output" = "error" ]
}

@test "normalize_outcome: escalated passes through unchanged" {
    run normalize_outcome "escalated"
    [ "$status" -eq 0 ]
    [ "$output" = "escalated" ]
}

@test "normalize_outcome: merged maps to pr_merged" {
    run normalize_outcome "merged"
    [ "$status" -eq 0 ]
    [ "$output" = "pr_merged" ]
}

@test "normalize_outcome: no-action maps to unchanged" {
    run normalize_outcome "no-action"
    [ "$status" -eq 0 ]
    [ "$output" = "unchanged" ]
}

@test "normalize_outcome: no-changes maps to unchanged" {
    run normalize_outcome "no-changes"
    [ "$status" -eq 0 ]
    [ "$output" = "unchanged" ]
}

@test "normalize_outcome: pr-closed maps to pr_closed" {
    run normalize_outcome "pr-closed"
    [ "$status" -eq 0 ]
    [ "$output" = "pr_closed" ]
}

@test "normalize_outcome: pr-created maps to pr_created" {
    run normalize_outcome "pr-created"
    [ "$status" -eq 0 ]
    [ "$output" = "pr_created" ]
}

@test "normalize_outcome: pr_pushed passes through unchanged" {
    run normalize_outcome "pr_pushed"
    [ "$status" -eq 0 ]
    [ "$output" = "pr_pushed" ]
}

@test "normalize_outcome: rejected passes through unchanged" {
    run normalize_outcome "rejected"
    [ "$status" -eq 0 ]
    [ "$output" = "rejected" ]
}

@test "normalize_outcome: reported passes through unchanged" {
    run normalize_outcome "reported"
    [ "$status" -eq 0 ]
    [ "$output" = "reported" ]
}

@test "normalize_outcome: skipped passes through unchanged" {
    run normalize_outcome "skipped"
    [ "$status" -eq 0 ]
    [ "$output" = "skipped" ]
}

@test "normalize_outcome: watch passes through unchanged" {
    run normalize_outcome "watch"
    [ "$status" -eq 0 ]
    [ "$output" = "watch" ]
}

@test "outcome_counter_effect: rejected and pr_closed increment, old pr-closed too" {
    local value
    for value in rejected pr_closed pr-closed; do
        run outcome_counter_effect "${value}"
        [ "$status" -eq 0 ]
        [ "$output" = "increment" ]
    done
}

@test "outcome_counter_effect: watch and error keep the counter" {
    local value
    for value in watch error; do
        run outcome_counter_effect "${value}"
        [ "$status" -eq 0 ]
        [ "$output" = "keep" ]
    done
}

@test "outcome_counter_effect: every other outcome resets, including unknown and empty" {
    local value
    for value in pr_created pr_pushed pr_merged merged unchanged approved reported escalated unknown ""; do
        run outcome_counter_effect "${value}"
        [ "$status" -eq 0 ]
        [ "$output" = "reset" ]
    done
}

@test "outcome_is_prune_terminal: succeeds only for rejected and pr_closed" {
    local value
    for value in rejected pr_closed pr-closed; do
        run outcome_is_prune_terminal "${value}"
        [ "$status" -eq 0 ]
    done
    for value in watch error pr_merged pr_created unchanged ""; do
        run outcome_is_prune_terminal "${value}"
        [ "$status" -eq 1 ]
    done
}
