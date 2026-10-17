#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154

# Tests for .github/actions/loop-agent-once/action.yml
#
# Use cases:
# - inputs follow the naming rule (agent_engine, agent_cli_version,
#   agent_tool_allowlist, agent_maker_effort, agent_maker_max_turns,
#   agent_maker_model) in alphabetical order
# - Install CLI passes AGENT_CLI_VERSION / AGENT_ENGINE
# - Run CLI Agent passes AGENT_MAKER_* (run.sh maps them onto the role vars) and
#   never sets the role vars EFFORT / MAX_TURNS / MODEL directly

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/action_yml.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-agent-once/action.yml"

@test "action inputs follow the naming rule in alphabetical order" {
    local expected
    expected="$(printf '%s\n' \
        agent_cli_version agent_engine agent_maker_effort agent_maker_max_turns \
        agent_maker_model agent_token agent_tool_allowlist github_token \
        node_version output_file prompt_text uv_version working_directory)"
    run action_yml_input_names "${ACTION_YML}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${expected}" ]
}

@test "install cli passes AGENT_CLI_VERSION and AGENT_ENGINE" {
    local expected
    expected="$(printf '%s\n' \
        'AGENT_CLI_VERSION: ${{ inputs.agent_cli_version }}' \
        'AGENT_ENGINE: ${{ inputs.agent_engine }}')"
    run action_yml_step_env "${ACTION_YML}" "Install CLI"
    [ "${output}" = "${expected}" ]
}

@test "run cli agent passes AGENT_MAKER_* and not the role vars" {
    local expected
    expected="$(printf '%s\n' \
        'AGENT_ENGINE: ${{ inputs.agent_engine }}' \
        'AGENT_MAKER_EFFORT: ${{ inputs.agent_maker_effort }}' \
        'AGENT_MAKER_MAX_TURNS: ${{ inputs.agent_maker_max_turns }}' \
        'AGENT_MAKER_MODEL: ${{ inputs.agent_maker_model }}' \
        'AGENT_TOKEN: ${{ inputs.agent_token }}' \
        'AGENT_TOOL_ALLOWLIST: ${{ inputs.agent_tool_allowlist }}' \
        'GITHUB_TOKEN: ${{ inputs.github_token }}' \
        'OUTPUT_FILE: ${{ inputs.output_file }}' \
        'PROMPT: ${{ inputs.prompt_text }}' \
        'WORKING_DIRECTORY: ${{ inputs.working_directory }}')"
    run action_yml_step_env "${ACTION_YML}" "Run CLI Agent"
    [ "${output}" = "${expected}" ]
}
