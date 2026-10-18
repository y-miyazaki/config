#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154

# Tests for .github/actions/loop-execute/action.yml
#
# Use cases:
# - inputs follow the naming rule (agent_engine, agent_cli_version, agent_tool_allowlist,
#   agent_commit_message, agent_checker_path_pattern, agent_edit_allowlist,
#   agent_edit_denylist, agent_unchanged_verdict) in alphabetical order, and
#   detect_result_json is gone
# - agent_unchanged_verdict has no REJECT default (empty; validated by the scripts)
# - the watch override is exported as finalize_outcome_override
# - Install CLI and Run Bounded Loop pass the renamed env vars; no step passes
#   DETECT_RESULT_JSON (detect JSON comes from the handoff)
# - no old input or env name remains in the file
# - setup actions do not use or save the Actions cache

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/action_yml.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-execute/action.yml"

@test "action has no old input, output, or env names" {
    run grep -c -E '\b(engine|cli_version|agent_allowed_tools|commit_message|infer_files_pattern|allowlist|denylist|no_changes_verdict|outcome_override|detect_result_json|ENGINE|CLI_VERSION|AGENT_ALLOWED_TOOLS|COMMIT_MESSAGE|INFER_FILES_PATTERN|ALLOWLIST|DENYLIST|NO_CHANGES_VERDICT|OUTCOME_OVERRIDE|DETECT_RESULT_JSON):' "${ACTION_YML}"
    [ "${output}" = "0" ]
    run grep -c -E 'inputs\.(engine|cli_version|agent_allowed_tools|commit_message|infer_files_pattern|allowlist|denylist|no_changes_verdict|detect_result_json)\b|outputs\.outcome_override\b' "${ACTION_YML}"
    [ "${output}" = "0" ]
}

@test "action inputs follow the naming rule in alphabetical order" {
    local expected
    expected="$(printf '%s\n' \
        agent_checker_effort agent_checker_instructions agent_checker_max_turns \
        agent_checker_model agent_checker_path_pattern agent_checker_skill_name \
        agent_cli_version agent_commit_message agent_edit_allowlist \
        agent_edit_denylist agent_engine agent_loop_max_attempts \
        agent_maker_effort agent_maker_max_turns agent_maker_model \
        agent_maker_skill_name agent_token agent_tool_allowlist \
        agent_unchanged_verdict base_branch branch github_token handoff_dir \
        handoff_key node_version prompt_implementer_feedback prompt_text \
        prompt_verifier_default_criteria prompt_verifier_initial \
        prompt_verifier_output_contract prompt_verifier_regression \
        prompt_verifier_task uv_version verifier_context worktree_path)"
    run action_yml_input_names "${ACTION_YML}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${expected}" ]
}

@test "agent_unchanged_verdict defaults to empty, not REJECT" {
    run action_yml_input_field "${ACTION_YML}" agent_unchanged_verdict default
    [ "${output}" = '""' ]
    run action_yml_input_field "${ACTION_YML}" agent_unchanged_verdict required
    [ "${output}" = "false" ]
}

@test "build notify context does not pass DETECT_RESULT_JSON" {
    run action_yml_step_env "${ACTION_YML}" "Build Notify Context"
    [ "${status}" -eq 0 ]
    [[ ${output} == *'HANDOFF_KEY: ${{ inputs.handoff_key }}'* ]]
    [[ ${output} == *'LOOP_HANDOFF_DIR: ${{ inputs.handoff_dir }}'* ]]
    [[ ${output} != *"DETECT_RESULT_JSON"* ]]
}

@test "install cli passes AGENT_CLI_VERSION and AGENT_ENGINE" {
    local expected
    expected="$(printf '%s\n' \
        'AGENT_CLI_VERSION: ${{ inputs.agent_cli_version }}' \
        'AGENT_ENGINE: ${{ inputs.agent_engine }}')"
    run action_yml_step_env "${ACTION_YML}" "Install CLI"
    [ "${output}" = "${expected}" ]
}

@test "outputs export finalize_outcome_override from the loop step" {
    run action_yml_output_lines "${ACTION_YML}"
    [ "${status}" -eq 0 ]
    [[ ${output} == *'finalize_outcome_override: ${{ steps.loop.outputs.finalize_outcome_override }}'* ]]
    [[ ${output} != *"
outcome_override:"* ]]
}

@test "run bounded loop passes the renamed agent env vars" {
    local line checked=0
    run action_yml_step_env "${ACTION_YML}" "Run Bounded Loop"
    [ "${status}" -eq 0 ]
    for line in \
        'AGENT_CHECKER_PATH_PATTERN: ${{ inputs.agent_checker_path_pattern }}' \
        'AGENT_COMMIT_MESSAGE: ${{ inputs.agent_commit_message }}' \
        'AGENT_EDIT_ALLOWLIST: ${{ inputs.agent_edit_allowlist }}' \
        'AGENT_EDIT_DENYLIST: ${{ inputs.agent_edit_denylist }}' \
        'AGENT_ENGINE: ${{ inputs.agent_engine }}' \
        'AGENT_TOOL_ALLOWLIST: ${{ inputs.agent_tool_allowlist }}' \
        'AGENT_UNCHANGED_VERDICT: ${{ inputs.agent_unchanged_verdict }}'; do
        [[ $'\n'"${output}"$'\n' == *$'\n'"${line}"$'\n'* ]]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 7 ]
    [[ ${output} != *"DETECT_RESULT_JSON"* ]]
}

@test "setup actions do not use or save the Actions cache" {
    run grep -c 'enable-cache: true' "${ACTION_YML}"
    [ "${output}" = "0" ]
    run grep -c 'enable-cache: false' "${ACTION_YML}"
    [ "${output}" = "1" ]
    run grep -c 'package-manager-cache: false' "${ACTION_YML}"
    [ "${output}" = "1" ]
}

@test "bundle branch replaces push branch and gets no token" {
    run grep -c 'name: Push Branch' "${ACTION_YML}"
    [ "${output}" = "0" ]
    run grep -c 'name: Bundle Branch' "${ACTION_YML}"
    [ "${output}" = "1" ]
    run action_yml_step_env "${ACTION_YML}" "Bundle Branch"
    [ "${status}" -eq 0 ]
    [[ ${output} != *"GITHUB_TOKEN"* ]]
    [[ ${output} == *'BUNDLE_FILE: ${{ runner.temp }}/loop-agent-bundle/branch.bundle'* ]]
    run action_yml_step_env "${ACTION_YML}" "Build Notify Context"
    [[ ${output} == *'HAS_CHANGES: ${{ steps.bundle.outputs.has_changes }}'* ]]
    run action_yml_output_lines "${ACTION_YML}"
    [[ ${output} == *'has_changes: ${{ steps.bundle.outputs.has_changes }}'* ]]
    run grep -c 'description: "true when a bundle of the agent branch was written (commits not on origin/<base_branch>)"' "${ACTION_YML}"
    [ "${output}" = "1" ]
    run action_yml_output_lines "${ACTION_YML}"
    [[ ${output} == *"bundle_file: \${{ steps.bundle.outputs.has_changes == 'true' && format('{0}/loop-agent-bundle/branch.bundle', runner.temp) || '' }}"* ]]
}
