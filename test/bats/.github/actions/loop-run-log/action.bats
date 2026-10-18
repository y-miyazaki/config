#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154

# Tests for .github/actions/loop-run-log/action.yml
#
# Use cases:
# - state_branch is a required input with no default; base_branch is gone
# - Append Run Log Entry passes STATE_BRANCH
# - the outcome and skip_reason descriptions list the current values

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/action_yml.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-run-log/action.yml"

@test "action outcome and skip_reason descriptions list current values" {
    run action_yml_input_field "${ACTION_YML}" outcome description
    [ "${output}" = '"Run outcome (pr_created | pr_pushed | reported | issue_commented | pr_reviewed | unchanged | rejected | error | skipped)"' ]
    run action_yml_input_field "${ACTION_YML}" skip_reason description
    [ "${output}" = '"Why execution was skipped (none | no_changes | circuit_breaker | budget | pr_number_missing)"' ]
}

@test "action passes STATE_BRANCH from state_branch" {
    run action_yml_step_env "${ACTION_YML}" "Append Run Log Entry"
    [ "${status}" -eq 0 ]
    [[ ${output} == *'STATE_BRANCH: ${{ inputs.state_branch }}'* ]]
    [[ ${output} != *'BASE_BRANCH'* ]]
}

@test "action state_branch is required without a default" {
    run action_yml_input_names "${ACTION_YML}"
    [[ ${output} == *"state_branch"* ]]
    [[ ${output} != *"base_branch"* ]]
    run action_yml_input_field "${ACTION_YML}" state_branch required
    [ "${output}" = "true" ]
    run action_yml_input_field "${ACTION_YML}" state_branch default
    [ -z "${output}" ]
}
