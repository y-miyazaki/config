#!/bin/bash
#######################################
# Description:
#   Land an agent branch onto to.branch for finalize strategies push / push_head.
#   Fetches the latest destination tip, merges the agent branch into it (preserving
#   commits already on to.branch from earlier serialized runs), and pushes without
#   force. Merge conflicts fail closed.
#
# Usage:
#   AGENT_BRANCH=loop/skill/ts TO_BRANCH=feature/foo GITHUB_TOKEN=... \
#   [GITHUB_OUTPUT=...] bash lib/push_target.sh
#
# Design Rules:
#   - Agent branch MUST differ from to.branch (never push agent tip over PR head by name)
#   - Always merge origin/AGENT into a checkout of origin/TO (not the reverse tip push)
#   - Never force-push; non-fast-forward push failures stay failures
#   - Conflict or merge failure aborts and exits non-zero (no silent has_changes success)
#
# Output:
#   Optional GITHUB_OUTPUT keys: commit_sha, pushed=true
#
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
AGENT_BRANCH="${AGENT_BRANCH:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
TO_BRANCH="${TO_BRANCH:-}"

#######################################
# configure_git_auth: Set commit identity and HTTPS push credentials
# Globals:
#   GITHUB_TOKEN - Token used for http.extraheader
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   None
#######################################
function configure_git_auth {
    : "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GITHUB_TOKEN}" | base64 -w0)"
}

#######################################
# main: Merge agent branch into latest to.branch and push
# Globals:
#   AGENT_BRANCH - Agent worktree branch with approved commits
#   GITHUB_OUTPUT - Optional path for action outputs
#   GITHUB_TOKEN - Token for fetch/push auth
#   TO_BRANCH - Destination branch (PR head or integration)
#
# Arguments:
#   None
#
# Outputs:
#   STDERR errors on validation/merge/push failure; GITHUB_OUTPUT when set
#
# Returns:
#   0 on successful push; non-zero on validation, merge conflict, or push failure
#######################################
function main {
    local commit_sha merge_err merge_status

    : "${AGENT_BRANCH:?AGENT_BRANCH is required}"
    : "${TO_BRANCH:?TO_BRANCH is required}"
    : "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

    if ! [[ ${AGENT_BRANCH} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::push_target: invalid agent branch: ${AGENT_BRANCH}" >&2
        exit 1
    fi
    if ! [[ ${TO_BRANCH} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::push_target: invalid to.branch: ${TO_BRANCH}" >&2
        exit 1
    fi
    if [[ ${AGENT_BRANCH} == "${TO_BRANCH}" ]]; then
        echo "::error::push_target: agent branch must differ from to.branch (${TO_BRANCH})" >&2
        exit 1
    fi

    configure_git_auth

    git fetch origin "${AGENT_BRANCH}" "${TO_BRANCH}" --prune
    git checkout -B "${TO_BRANCH}" "origin/${TO_BRANCH}"

    set +e
    merge_err="$(git merge --no-ff "origin/${AGENT_BRANCH}" -m "chore(loop): automated fix [skip ci]" 2>&1)"
    merge_status=$?
    set -e
    if [[ ${merge_status} -ne 0 ]]; then
        printf '%s\n' "${merge_err}" >&2
        echo "::error::push_target: merge conflict incorporating ${AGENT_BRANCH} into ${TO_BRANCH}; fail closed (no force push)" >&2
        git merge --abort 2> /dev/null || true
        exit 1
    fi

    if ! git push origin "HEAD:refs/heads/${TO_BRANCH}"; then
        echo "::error::push_target: push to ${TO_BRANCH} failed (non-fast-forward or auth); fail closed" >&2
        exit 1
    fi

    commit_sha="$(git rev-parse HEAD)"
    if [[ -n ${GITHUB_OUTPUT} ]]; then
        {
            echo "commit_sha=${commit_sha}"
            echo "pushed=true"
        } >> "${GITHUB_OUTPUT}"
    fi
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
