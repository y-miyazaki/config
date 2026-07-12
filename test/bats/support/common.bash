#!/usr/bin/env bash
# Shared helpers for test/bats suites.
#
# Conventions (all *.bats under test/bats/):
# - Header: `# Tests for <repo-relative path>`
# - Load this file via the walk-up preamble placed after the header in each suite.
# - setup(): source targets with bats_source_rel / bats_source_apm_skill; export temp state.
# - teardown(): remove artifacts created in setup when applicable.
# - Suites assume cwd is the repository root (see scripts/shell-script/validate.sh).

# bats_workspace_root: Print absolute repository root
#
# Returns:
#   Repository root path on stdout
#
function bats_workspace_root {
    local dir
    dir="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    while [[ ! -f "${dir}/apm.yml" ]]; do
        if [[ ${dir} == "/" ]]; then
            break
        fi
        dir="$(dirname "${dir}")"
    done
    printf '%s' "${dir}"
}

# bats_support_dir: Print absolute test/bats/support directory
#
# Returns:
#   Support directory path on stdout
#
function bats_support_dir {
    local dir
    dir="$(dirname "${BATS_TEST_FILENAME}")"
    while [[ ! -f "${dir}/support/common.bash" ]]; do
        dir="$(dirname "${dir}")"
    done
    printf '%s/support' "${dir}"
}

# bats_source_rel: Source a repository-relative script path
#
# Arguments:
#   $1 - Path relative to repository root
#
function bats_source_rel {
    local rel="$1"
    # shellcheck disable=SC1090,SC1091
    source "${rel}"
}

# apm_skill_script_path: Resolve an APM loop skill script path
#
# Arguments:
#   $1 - Package name (for example loop-changelog)
#   $2 - Script file name (for example detect_changelog_commits.sh)
#
# Returns:
#   Absolute script path on stdout
#
function apm_skill_script_path {
    local package="$1"
    local script="$2"
    printf '%s/.apm/packages/%s/.apm/skills/%s/scripts/%s' \
        "$(bats_workspace_root)" "${package}" "${package}" "${script}"
}

# bats_source_apm_skill: Source an APM loop skill script
#
# Arguments:
#   $1 - Package name
#   $2 - Script file name
#
function bats_source_apm_skill {
    local package="$1"
    local script="$2"
    # shellcheck disable=SC1090,SC1091
    source "$(apm_skill_script_path "${package}" "${script}")"
}

# git_test_repo_setup: Create an isolated git repository for integration tests
#
# Global Variables:
#   GIT_TEST_REPO - Path to the temporary repository
#
function git_test_repo_setup {
    GIT_TEST_REPO="${BATS_TEST_TMPDIR}/repo"
    rm -rf "${GIT_TEST_REPO}"
    mkdir -p "${GIT_TEST_REPO}"
    git -C "${GIT_TEST_REPO}" init -q
    git -C "${GIT_TEST_REPO}" config user.email "test@example.com"
    git -C "${GIT_TEST_REPO}" config user.name "Test User"
}

# git_test_repo_commit: Create a tracked change and commit in GIT_TEST_REPO
#
# Arguments:
#   $1 - Commit subject
#
function git_test_repo_commit {
    local message="$1"
    echo "change-${RANDOM}" >> "${GIT_TEST_REPO}/file.txt"
    git -C "${GIT_TEST_REPO}" add -A
    git -C "${GIT_TEST_REPO}" commit -q -m "${message}"
}

# git_test_repo_run: Run a command with cwd set to GIT_TEST_REPO via bats run
#
# Arguments:
#   $@ - Shell command string passed to bash -c
#
function git_test_repo_run {
    run bash -c "cd '${GIT_TEST_REPO}' && $*"
}

export -f bats_workspace_root bats_support_dir bats_source_rel apm_skill_script_path
export -f bats_source_apm_skill git_test_repo_setup git_test_repo_commit git_test_repo_run
