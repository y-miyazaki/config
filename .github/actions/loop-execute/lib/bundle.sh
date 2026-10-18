#!/bin/bash
#######################################
# Description: Bundle the loop worktree branch when changes exist
#
# Usage: bash lib/bundle.sh
#
# Environment:
#   BASE_BRANCH - Base branch; the bundle excludes commits on origin/<base>
#   BRANCH - Branch name to bundle
#   BUNDLE_FILE - Output path of the git bundle
#   GITHUB_OUTPUT - GitHub Actions output file
#   LOOP_DENYLIST_BLOCKED - true when the final attempt's diff still matched
#     the denylist (optional; defaults to false)
#   LOOP_HAS_CHANGES - true when loop step produced commits
#   STATUS_DIR - Directory for failure.json (optional)
#   WORKTREE_PATH - Absolute path to the worktree
#
# Output:
#   Writes has_changes to GITHUB_OUTPUT
#
# Design Rules:
#   - Branch names are validated before bundling
#   - No token is read: the bundle is written locally and a later job with
#     write credentials pushes it
#   - A denylist-blocked attempt never bundles, even if it produced commits:
#     an ordinary checker REJECT may still deliver for human inspection, but a
#     denylist hit (secrets/credentials paths) must never reach the remote.
#   - LOOP_HAS_CHANGES=true with no commits outside origin/<base> fails with
#     stage bundle: git refuses an empty bundle, and failing closed is intended
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

_LOOP_BUNDLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"

#######################################
# main: Bundle branch when loop produced changes
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success or when no bundle is needed
#
#######################################
function main {
    local bundle_err

    : "${BASE_BRANCH:?}"
    : "${BRANCH:?}"
    : "${BUNDLE_FILE:?}"
    : "${LOOP_HAS_CHANGES:?}"
    : "${WORKTREE_PATH:?}"
    : "${GITHUB_OUTPUT:?}"
    LOOP_DENYLIST_BLOCKED="${LOOP_DENYLIST_BLOCKED:-false}"
    if ! [[ ${BRANCH} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::Invalid branch name: ${BRANCH}"
        exit 1
    fi
    if [[ ${LOOP_DENYLIST_BLOCKED} == "true" ]]; then
        echo "::warning::Skipping bundle: final diff still matches the denylist"
        echo "has_changes=false" >> "${GITHUB_OUTPUT}"
        return 0
    fi
    if [[ ${LOOP_HAS_CHANGES} != "true" ]]; then
        echo "has_changes=false" >> "${GITHUB_OUTPUT}"
        return 0
    fi
    mkdir -p "$(dirname "${BUNDLE_FILE}")"
    if ! bundle_err="$(git -C "${WORKTREE_PATH}" bundle create "${BUNDLE_FILE}" "^origin/${BASE_BRANCH}" "refs/heads/${BRANCH}" 2>&1)"; then
        if [[ -n ${STATUS_DIR:-} ]]; then
            # shellcheck source=../../lib/loop/failure_record.sh
            # shellcheck disable=SC1091
            source "${_LOOP_BUNDLE_LIB_DIR}/failure_record.sh"
            loop_failure_record "bundle" "${bundle_err}" "${STATUS_DIR}/failure.json"
        fi
        printf '%s\n' "${bundle_err}" >&2
        exit 1
    fi
    echo "has_changes=true" >> "${GITHUB_OUTPUT}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
