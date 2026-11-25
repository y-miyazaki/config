#!/bin/bash
#######################################
# Description:
#   Land an agent branch onto to.branch for delivery pr_push (existing PR head).
#   Fetches the latest destination tip, merges the agent branch into it (preserving
#   commits already on to.branch from earlier serialized runs), and pushes without
#   force. Merge conflicts fail closed.
#
# Usage:
#   AGENT_BRANCH=loop/skill/ts TO_BRANCH=feature/foo GITHUB_TOKEN=... \
#   [GITHUB_OUTPUT=...] [LOOP_FAILURE_FILE=...] bash lib/push_target.sh
#
# Design Rules:
#   - Agent branch MUST differ from to.branch (never push agent tip over PR head by name)
#   - Always merge origin/AGENT into a checkout of origin/TO (not the reverse tip push)
#   - Never force-push; non-fast-forward push failures stay failures
#   - Conflict or merge failure aborts and exits non-zero (no silent has_changes success)
#   - Merge and push failures are redacted, then recorded via failure_record_write when LOOP_FAILURE_FILE is set
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
LOOP_FAILURE_FILE="${LOOP_FAILURE_FILE:-}"
TO_BRANCH="${TO_BRANCH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/loop/check_names.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/check_names.sh"
# shellcheck source=../../lib/loop/failure_record.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/failure_record.sh"
# shellcheck source=../../lib/loop/git_auth.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/git_auth.sh"

#######################################
# push_target_fail: Redact and print a failure, record it, then exit 1
#
# Globals:
#   LOOP_FAILURE_FILE - Optional failure record path
#
# Arguments:
#   $1 - Summary message
#   $2 - Raw command output (optional; redacted before printing or recording)
#
# Outputs:
#   STDERR redacted detail and ::error:: line; failure record when LOOP_FAILURE_FILE is set
#
# Returns:
#   Exits 1
#
#######################################
function push_target_fail {
    local summary="${1:?summary required}"
    local detail="${2:-}"
    local redacted_detail

    redacted_detail="$(redact_sensitive_text "${detail}")"
    if [[ -n ${redacted_detail} ]]; then
        printf '%s\n' "${redacted_detail}" >&2
    fi
    echo "::error::push_target: ${summary}" >&2
    if [[ -n ${LOOP_FAILURE_FILE} ]]; then
        if ! failure_record_write "finalize_push" "${summary}: ${redacted_detail}" "${LOOP_FAILURE_FILE}"; then
            echo "::warning::push_target: could not record the failure" >&2
        fi
    fi
    exit 1
}

#######################################
# main: Merge agent branch into latest to.branch and push
# Globals:
#   AGENT_BRANCH - Agent worktree branch with approved commits
#   GITHUB_OUTPUT - Optional path for action outputs
#   GITHUB_TOKEN - Token for fetch/push auth
#   LOOP_FAILURE_FILE - Optional failure record path (merge/push failures)
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
    local commit_sha merge_err merge_status push_err

    : "${AGENT_BRANCH:?AGENT_BRANCH is required}"
    : "${TO_BRANCH:?TO_BRANCH is required}"
    : "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

    if ! check_names_branch "${AGENT_BRANCH}"; then
        echo "::error::push_target: invalid agent branch: ${AGENT_BRANCH}" >&2
        exit 1
    fi
    if ! check_names_branch "${TO_BRANCH}"; then
        echo "::error::push_target: invalid to.branch: ${TO_BRANCH}" >&2
        exit 1
    fi
    if [[ ${AGENT_BRANCH} == "${TO_BRANCH}" ]]; then
        echo "::error::push_target: agent branch must differ from to.branch (${TO_BRANCH})" >&2
        exit 1
    fi

    git_auth_configure

    git fetch origin "${AGENT_BRANCH}" "${TO_BRANCH}" --prune
    git checkout -B "${TO_BRANCH}" "origin/${TO_BRANCH}"

    set +e
    merge_err="$(git merge --no-ff "origin/${AGENT_BRANCH}" -m "chore(loop): automated fix" 2>&1)"
    merge_status=$?
    set -e
    if [[ ${merge_status} -ne 0 ]]; then
        git merge --abort 2> /dev/null || true
        push_target_fail "merge conflict incorporating ${AGENT_BRANCH} into ${TO_BRANCH}; fail closed (no force push)" "${merge_err}"
    fi

    if ! push_err="$(git push origin "HEAD:refs/heads/${TO_BRANCH}" 2>&1)"; then
        push_target_fail "push to ${TO_BRANCH} failed (non-fast-forward or auth); fail closed" "${push_err}"
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
