#!/usr/bin/env bats
# shellcheck disable=SC2154

# Tests for the "Run Finalize Hook" step in .github/actions/loop-finalize/action.yml
#
# Use cases:
# - the step runs whenever finalize_script is set, regardless of delivery
# - FINALIZE_SCRIPT is inputs.finalize_script
# - GH_TOKEN is the resolved inputs.github_token
# - GITHUB_REPOSITORY is github.repository
# - the hook gets LOOP_MESSAGE_DIR to write its message into; the step builds no LOOP_META_BLOCK
# - env keys stay in alphabetical order (ORD-01)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-finalize/action.yml"

# Print "KEY: value" lines of the env block of the Run Finalize Hook step.
finalize_hook_env() {
    awk '
        /^    - name: / { in_step = ($0 == "    - name: Run Finalize Hook"); in_env = 0; next }
        in_step && /^      env:$/ { in_env = 1; next }
        in_step && in_env && /^        [A-Za-z_][A-Za-z0-9_]*:/ { sub(/^        /, ""); print; next }
        in_step && in_env { in_env = 0 }
    ' "${ACTION_YML}"
}

# Print the single-line if: of the Run Finalize Hook step.
finalize_hook_if() {
    awk '
        /^    - name: / { in_step = ($0 == "    - name: Run Finalize Hook"); next }
        in_step && /^      if: / { sub(/^      if: /, ""); print }
    ' "${ACTION_YML}"
}

@test "finalize hook env keys are alphabetical" {
    keys="$(finalize_hook_env | cut -d: -f1)"
    [ -n "${keys}" ]
    sorted="$(printf '%s\n' "${keys}" | LC_ALL=C sort)"
    [ "${keys}" = "${sorted}" ]
}

@test "finalize hook env sets FINALIZE_SCRIPT from inputs.finalize_script" {
    run finalize_hook_env
    [ "${status}" -eq 0 ]
    [[ ${output} == *$'FINALIZE_SCRIPT: ${{ inputs.finalize_script }}'* ]]
}

@test "finalize hook env sets GH_TOKEN from inputs.github_token" {
    run finalize_hook_env
    [ "${status}" -eq 0 ]
    [[ ${output} == *$'GH_TOKEN: ${{ inputs.github_token }}'* ]]
}

@test "finalize hook env sets GITHUB_REPOSITORY from github.repository" {
    run finalize_hook_env
    [ "${status}" -eq 0 ]
    [[ ${output} == *$'GITHUB_REPOSITORY: ${{ github.repository }}'* ]]
}

@test "finalize hook runs whenever finalize_script is set, regardless of delivery" {
    run finalize_hook_if
    [ "${status}" -eq 0 ]
    [ "${output}" = "inputs.finalize_script != ''" ]
}

@test "finalize hook gets LOOP_MESSAGE_DIR and no LOOP_META_BLOCK" {
    run finalize_hook_env
    [ "${status}" -eq 0 ]
    [[ ${output} == *$'LOOP_MESSAGE_DIR: ${{ runner.temp }}/loop-message'* ]]
    [[ ${output} != *"LOOP_META_BLOCK"* ]]
    run grep -c 'LOOP_META_BLOCK' "${ACTION_YML}"
    [ "${output}" = "0" ]
}
