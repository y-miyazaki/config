#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154

# Tests for .github/actions/loop-notify-pr/action.yml
#
# Use cases:
# - inputs follow the naming rule (pr_auto_merge, agent_loop_max_attempts, agent_engine)
#   in alphabetical order; level, auto_merge, max_attempts, and engine are gone
# - Notify Pull Request passes PR_AUTO_MERGE / AGENT_LOOP_MAX_ATTEMPTS / AGENT_ENGINE and no LEVEL

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/action_yml.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-notify-pr/action.yml"

@test "action inputs follow the naming rule in alphabetical order" {
    local expected
    expected="$(printf '%s\n' \
        agent_engine agent_loop_max_attempts attempts commit_sha fix_pr_number fix_pr_url \
        github_event_name github_token loop_name loop_run_id notify_context_json outcome \
        pr_auto_merge pr_number reject_reason repository target_json trigger_comment_id \
        usage_json verdict)"
    run action_yml_input_names "${ACTION_YML}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${expected}" ]
}

@test "notify step passes renamed env and no LEVEL" {
    run action_yml_step_env "${ACTION_YML}" "Notify Pull Request"
    [ "${status}" -eq 0 ]
    [[ ${output} == *'PR_AUTO_MERGE: ${{ inputs.pr_auto_merge }}'* ]]
    [[ ${output} == *'AGENT_LOOP_MAX_ATTEMPTS: ${{ inputs.agent_loop_max_attempts }}'* ]]
    [[ ${output} == *'AGENT_ENGINE: ${{ inputs.agent_engine }}'* ]]
    [[ ${output} != *'LEVEL'* ]]
    [[ ${output} != *'inputs.auto_merge'* ]]
    [[ ${output} != *'inputs.max_attempts'* ]]
    [[ ${output} != *'inputs.engine'* ]]
}
