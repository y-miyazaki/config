#!/usr/bin/env bats

# Tests for .github/actions/lib/loop/outcome.sh
#
# Use cases:
# - outcome_normalize maps each old persisted outcome to its new name
# - outcome_normalize passes new names, unknown values, and empty input through unchanged
# - outcome_counter_effect maps rejected and pr_closed (old and new names) to increment, watch, error and any unmapped or empty outcome to keep, every listed success outcome to reset
# - outcome_is_prune_terminal succeeds only for rejected and pr_closed (old and new names)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

bats_require_minimum_version 1.5.0

OUTCOME_LIB="$(bats_workspace_root)/.github/actions/lib/loop/outcome.sh"

setup() {
    # shellcheck disable=SC1090
    source "${OUTCOME_LIB}"
}

@test "outcome_normalize: empty value passes through unchanged" {
    run outcome_normalize ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "outcome_normalize: error passes through unchanged" {
    run outcome_normalize "error"
    [ "$status" -eq 0 ]
    [ "$output" = "error" ]
}

@test "outcome_normalize: escalated passes through unchanged" {
    run outcome_normalize "escalated"
    [ "$status" -eq 0 ]
    [ "$output" = "escalated" ]
}

@test "outcome_normalize: merged maps to pr_merged" {
    run outcome_normalize "merged"
    [ "$status" -eq 0 ]
    [ "$output" = "pr_merged" ]
}

@test "outcome_normalize: no-action maps to unchanged" {
    run outcome_normalize "no-action"
    [ "$status" -eq 0 ]
    [ "$output" = "unchanged" ]
}

@test "outcome_normalize: no-changes maps to unchanged" {
    run outcome_normalize "no-changes"
    [ "$status" -eq 0 ]
    [ "$output" = "unchanged" ]
}

@test "outcome_normalize: pr-closed maps to pr_closed" {
    run outcome_normalize "pr-closed"
    [ "$status" -eq 0 ]
    [ "$output" = "pr_closed" ]
}

@test "outcome_normalize: pr-created maps to pr_created" {
    run outcome_normalize "pr-created"
    [ "$status" -eq 0 ]
    [ "$output" = "pr_created" ]
}

@test "outcome_normalize: pr_pushed passes through unchanged" {
    run outcome_normalize "pr_pushed"
    [ "$status" -eq 0 ]
    [ "$output" = "pr_pushed" ]
}

@test "outcome_normalize: rejected passes through unchanged" {
    run outcome_normalize "rejected"
    [ "$status" -eq 0 ]
    [ "$output" = "rejected" ]
}

@test "outcome_normalize: reported passes through unchanged" {
    run outcome_normalize "reported"
    [ "$status" -eq 0 ]
    [ "$output" = "reported" ]
}

@test "outcome_normalize: skipped passes through unchanged" {
    run outcome_normalize "skipped"
    [ "$status" -eq 0 ]
    [ "$output" = "skipped" ]
}

@test "outcome_normalize: watch passes through unchanged" {
    run outcome_normalize "watch"
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

@test "outcome_counter_effect: listed success outcomes reset, including old names" {
    local value
    for value in pr_created pr_pushed pr_merged merged unchanged no-changes reported issue_created issue_commented pr_reviewed skipped; do
        run outcome_counter_effect "${value}"
        [ "$status" -eq 0 ]
        [ "$output" = "reset" ]
    done
}

@test "outcome_counter_effect: unmapped and empty outcomes keep the counter and warn" {
    local value
    for value in unknown approved ""; do
        run --separate-stderr outcome_counter_effect "${value}"
        [ "$status" -eq 0 ]
        [ "$output" = "keep" ]
        [[ ${stderr} == *"unmapped outcome"* ]]
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
