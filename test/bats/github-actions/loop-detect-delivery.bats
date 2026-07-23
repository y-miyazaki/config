#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for delivery-driven git finalize resolution in loop-detect
#
# Use cases:
# - delivery open_pr maps to open_pr git landing defaults and overrides
# - non-PR delivery maps finalize strategies to none
# - invalid delivery and git_landing enums fail closed
# - resolve_loop_write_contract rejects omitted may_edit

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

@test "resolve_git_finalize_strategies honors git_landing overrides for open_pr delivery" {
    export DELIVERY="open_pr"
    export GIT_LANDING_INTEGRATION="push"
    export GIT_LANDING_PULL_REQUEST="push_head"
    resolve_git_finalize_strategies
    [ "${GIT_FINALIZE_INTEGRATION}" = "push" ]
    [ "${GIT_FINALIZE_PULL_REQUEST}" = "push_head" ]
}

@test "resolve_git_finalize_strategies maps delivery log to none git landing" {
    export DELIVERY="log"
    resolve_git_finalize_strategies
    [ "${GIT_FINALIZE_INTEGRATION}" = "none" ]
    [ "${GIT_FINALIZE_PULL_REQUEST}" = "none" ]
}

@test "resolve_git_finalize_strategies maps delivery none to none git landing" {
    export DELIVERY="none"
    resolve_git_finalize_strategies
    [ "${GIT_FINALIZE_INTEGRATION}" = "none" ]
    [ "${GIT_FINALIZE_PULL_REQUEST}" = "none" ]
}

@test "resolve_git_finalize_strategies maps delivery notion to none git landing" {
    export DELIVERY="notion"
    resolve_git_finalize_strategies
    [ "${GIT_FINALIZE_INTEGRATION}" = "none" ]
    [ "${GIT_FINALIZE_PULL_REQUEST}" = "none" ]
}

@test "resolve_git_finalize_strategies maps delivery open_pr to open_pr git landing" {
    export DELIVERY="open_pr"
    unset GIT_LANDING_INTEGRATION GIT_LANDING_PULL_REQUEST
    resolve_git_finalize_strategies
    [ "${GIT_FINALIZE_INTEGRATION}" = "open_pr" ]
    [ "${GIT_FINALIZE_PULL_REQUEST}" = "open_pr" ]
}

@test "resolve_git_finalize_strategies maps non-pr delivery to none git landing" {
    export DELIVERY="issue"
    resolve_git_finalize_strategies
    [ "${GIT_FINALIZE_INTEGRATION}" = "none" ]
    [ "${GIT_FINALIZE_PULL_REQUEST}" = "none" ]
}

@test "resolve_git_finalize_strategies rejects invalid delivery" {
    export DELIVERY="slack"
    run resolve_git_finalize_strategies
    [ "$status" -eq 1 ]
    [[ $output == *"delivery must be"* ]]
}

@test "resolve_git_finalize_strategies rejects invalid git_landing_integration" {
    export DELIVERY="open_pr"
    export GIT_LANDING_INTEGRATION="merge"
    run resolve_git_finalize_strategies
    [ "$status" -eq 1 ]
    [[ $output == *"git_landing_integration must be open_pr or push"* ]]
}

@test "resolve_git_finalize_strategies rejects invalid git_landing_pull_request" {
    export DELIVERY="open_pr"
    export GIT_LANDING_PULL_REQUEST="merge"
    run resolve_git_finalize_strategies
    [ "$status" -eq 1 ]
    [[ $output == *"git_landing_pull_request must be open_pr or push_head"* ]]
}

@test "resolve_loop_write_contract rejects omitted may_edit" {
    export MAY_EDIT=""
    export WRITE_TARGET="fix"
    export DELIVERY="open_pr"
    export LEVEL="L2"
    run resolve_loop_write_contract
    [ "$status" -eq 1 ]
    [[ $output == *"may_edit is required"* ]]
}
