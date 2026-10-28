#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154

# Tests for .github/actions/loop-state-promote/action.yml
#
# Use cases:
# - inputs are state_branch (required, no default) and state_pr_skip; the old names are gone
# - Promote Pending State passes STATE_BRANCH and STATE_PR_SKIP

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/action_yml.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-state-promote/action.yml"

@test "action inputs are state_branch and state_pr_skip" {
    local expected
    expected="$(printf '%s\n' github_token merged pr_number state_branch state_pr_skip)"
    run action_yml_input_names "${ACTION_YML}"
    [ "${output}" = "${expected}" ]
}

@test "action passes STATE_BRANCH and STATE_PR_SKIP" {
    local expected
    expected="$(printf '%s\n' \
        'GITHUB_TOKEN: ${{ inputs.github_token }}' \
        'MERGED: ${{ inputs.merged }}' \
        'PR_NUMBER: ${{ inputs.pr_number }}' \
        'STATE_BRANCH: ${{ inputs.state_branch }}' \
        'STATE_PR_SKIP: ${{ inputs.state_pr_skip }}')"
    run action_yml_step_env "${ACTION_YML}" "Promote Pending State"
    [ "${output}" = "${expected}" ]
}

@test "action state_branch is required without a default" {
    run action_yml_input_field "${ACTION_YML}" state_branch required
    [ "${output}" = "true" ]
    run action_yml_input_field "${ACTION_YML}" state_branch default
    [ -z "${output}" ]
}
