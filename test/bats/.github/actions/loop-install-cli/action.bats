#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154

# Tests for .github/actions/loop-install-cli/action.yml
#
# Use cases:
# - inputs are agent_cli_version / agent_engine (naming rule) in alphabetical order
# - Install CLI passes AGENT_CLI_VERSION / AGENT_ENGINE to lib/install.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/action_yml.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-install-cli/action.yml"

@test "action inputs follow the naming rule in alphabetical order" {
    local expected
    expected="$(printf '%s\n' agent_cli_version agent_engine node_version uv_version)"
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
