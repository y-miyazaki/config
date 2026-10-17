#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154

# Tests for .github/actions/loop-worktree-setup/action.yml
#
# Use cases:
# - inputs are from_branch / from_ref / agent_branch_prefix (naming rule) in
#   alphabetical order
# - Setup Worktree passes FROM_BRANCH / FROM_REF / AGENT_BRANCH_PREFIX
# - the inline script creates <agent_branch_prefix>/<skill>/<date> from
#   origin/<from_branch> and ignores the legacy BASE_BRANCH / BASE_REF /
#   BRANCH_PREFIX names

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "${_bats_support}/support/action_yml.bash"

ACTION_YML="$(bats_workspace_root)/.github/actions/loop-worktree-setup/action.yml"

setup() {
    SETUP_SCRIPT="${BATS_TEST_TMPDIR}/setup_worktree.sh"
    awk '
        /^    - name: Setup Worktree$/ { in_step = 1; next }
        in_step && /^      run: \|$/ { in_run = 1; next }
        in_run && /^        / { sub(/^        /, ""); print; next }
        in_run && /^$/ { print; next }
        in_run { exit }
    ' "${ACTION_YML}" > "${SETUP_SCRIPT}"
}

@test "action inputs follow the naming rule in alphabetical order" {
    local expected
    expected="$(printf '%s\n' \
        agent_branch_prefix agent_maker_skill_name branch from_branch from_ref \
        github_token)"
    run action_yml_input_names "${ACTION_YML}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${expected}" ]
}

@test "setup script branches from origin/from_branch with agent_branch_prefix" {
    local remote work runner_temp output_file branch_line
    remote="${BATS_TEST_TMPDIR}/remote"
    work="${BATS_TEST_TMPDIR}/work"
    runner_temp="${BATS_TEST_TMPDIR}/runner"
    output_file="${BATS_TEST_TMPDIR}/github_output"
    mkdir -p "${runner_temp}"
    : > "${output_file}"

    bats_git_fresh_repo "${remote}"
    bats_git_cmd -C "${remote}" checkout -q -b main
    printf 'base\n' > "${remote}/base.txt"
    bats_git_commit "${remote}" "init"
    bats_git_cmd -C "${remote}" checkout -q -b release
    printf 'release\n' > "${remote}/release.txt"
    bats_git_commit "${remote}" "release"
    bats_git_cmd -C "${remote}" checkout -q main
    bats_git_cmd clone -q "${remote}" "${work}"
    bats_git_local_identity "${work}"

    run bash -c "cd '${work}' && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
        AGENT_BRANCH_PREFIX='bot' \
        AGENT_MAKER_SKILL_NAME='changelog' \
        BASE_BRANCH='legacy-missing' \
        BASE_REF='legacy-missing' \
        BRANCH='' \
        BRANCH_PREFIX='legacy' \
        FROM_BRANCH='release' \
        FROM_REF='' \
        GITHUB_OUTPUT='${output_file}' \
        GITHUB_TOKEN='dummy-token' \
        RUNNER_TEMP='${runner_temp}' \
        bash '${SETUP_SCRIPT}'"
    [ "${status}" -eq 0 ]
    branch_line="$(grep '^branch=' "${output_file}")"
    [[ ${branch_line} =~ ^branch=bot/changelog/[0-9]{8}-[0-9]{6}$ ]]
    [ "$(grep '^worktree_path=' "${output_file}")" = "worktree_path=${runner_temp}/worktree-changelog" ]
    [ -f "${runner_temp}/worktree-changelog/release.txt" ]
}

@test "setup script rejects an invalid from_ref" {
    local work
    work="${BATS_TEST_TMPDIR}/work-invalid"
    bats_git_fresh_repo "${work}"
    printf 'x\n' > "${work}/x.txt"
    bats_git_commit "${work}" "init"

    run bash -c "cd '${work}' && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
        AGENT_BRANCH_PREFIX='loop' \
        AGENT_MAKER_SKILL_NAME='changelog' \
        BRANCH='' \
        FROM_BRANCH='' \
        FROM_REF='bad ref;' \
        GITHUB_OUTPUT='${BATS_TEST_TMPDIR}/github_output_invalid' \
        GITHUB_TOKEN='dummy-token' \
        RUNNER_TEMP='${BATS_TEST_TMPDIR}' \
        bash '${SETUP_SCRIPT}'"
    [ "${status}" -eq 1 ]
    [ "${output}" = "::error::Invalid from ref: bad ref;" ]
}

@test "setup worktree passes FROM_BRANCH, FROM_REF, and AGENT_BRANCH_PREFIX" {
    local expected
    expected="$(printf '%s\n' \
        'AGENT_BRANCH_PREFIX: ${{ inputs.agent_branch_prefix }}' \
        'AGENT_MAKER_SKILL_NAME: ${{ inputs.agent_maker_skill_name }}' \
        'BRANCH: ${{ inputs.branch }}' \
        'FROM_BRANCH: ${{ inputs.from_branch }}' \
        'FROM_REF: ${{ inputs.from_ref }}' \
        'GITHUB_TOKEN: ${{ inputs.github_token }}')"
    run action_yml_step_env "${ACTION_YML}" "Setup Worktree"
    [ "${output}" = "${expected}" ]
}
