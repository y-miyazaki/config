#!/usr/bin/env bash
# Portable git repository helpers for bats (local/CI independent).
# Uses the real git binary; sets repo-local identity so global git config is not required.
# Load via: source "$(bats_support_dir)/git_test_mock.bash" (after common.bash).

readonly BATS_GIT_TEST_USER_EMAIL="test@example.com"
readonly BATS_GIT_TEST_USER_NAME="Test User"

# bats_git_local_identity: Set repo-local user.name/email for commits
#
# Arguments:
#   $1 - Repository path
function bats_git_local_identity {
    local repo="$1"
    git -C "${repo}" config user.email "${BATS_GIT_TEST_USER_EMAIL}"
    git -C "${repo}" config user.name "${BATS_GIT_TEST_USER_NAME}"
}

# bats_git_init_in_place: git init + local identity in an existing directory tree
#
# Arguments:
#   $1 - Repository path
function bats_git_init_in_place {
    local repo="$1"
    git -C "${repo}" init -q
    bats_git_local_identity "${repo}"
}

# bats_git_fresh_repo: Remove, recreate, init, and set local identity
#
# Arguments:
#   $1 - Repository path
function bats_git_fresh_repo {
    local repo="$1"
    rm -rf "${repo}"
    mkdir -p "${repo}"
    bats_git_init_in_place "${repo}"
}

# bats_git_commit: Stage paths (or all) and commit
#
# Arguments:
#   $1 - Repository path
#   $2 - Commit subject
#   $@ - Optional paths to stage (default: all)
function bats_git_commit {
    local repo="$1"
    local message="$2"
    shift 2

    if [[ $# -eq 0 ]]; then
        git -C "${repo}" add -A
    else
        git -C "${repo}" add "$@"
    fi
    git -C "${repo}" commit -q -m "${message}"
}

export -f bats_git_local_identity bats_git_init_in_place bats_git_fresh_repo bats_git_commit
