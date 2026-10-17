#!/usr/bin/env bats
# shellcheck disable=SC2154

# Tests for the "Run Domain Persistence" step env in .github/actions/loop-finalize/action.yml
#
# Use cases:
# - GH_TOKEN is the resolved inputs.github_token
# - GITHUB_REPOSITORY is github.repository
# - env keys stay in alphabetical order (ORD-01)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-finalize/action.yml"

# Print "KEY: value" lines of the env block of the Run Domain Persistence step.
domain_persistence_env() {
    awk '
        /^    - name: / { in_step = ($0 == "    - name: Run Domain Persistence"); in_env = 0; next }
        in_step && /^      env:$/ { in_env = 1; next }
        in_step && in_env && /^        [A-Za-z_][A-Za-z0-9_]*:/ { sub(/^        /, ""); print; next }
        in_step && in_env { in_env = 0 }
    ' "${ACTION_YML}"
}

@test "domain persistence env sets GH_TOKEN from inputs.github_token" {
    run domain_persistence_env
    [ "${status}" -eq 0 ]
    [[ ${output} == *$'GH_TOKEN: ${{ inputs.github_token }}'* ]]
}

@test "domain persistence env sets GITHUB_REPOSITORY from github.repository" {
    run domain_persistence_env
    [ "${status}" -eq 0 ]
    [[ ${output} == *$'GITHUB_REPOSITORY: ${{ github.repository }}'* ]]
}

@test "domain persistence env keys are alphabetical" {
    keys="$(domain_persistence_env | cut -d: -f1)"
    [ -n "${keys}" ]
    sorted="$(printf '%s\n' "${keys}" | LC_ALL=C sort)"
    [ "${keys}" = "${sorted}" ]
}
