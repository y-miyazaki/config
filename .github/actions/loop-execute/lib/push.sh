#!/bin/bash
#######################################
# Description: Push the loop worktree branch when changes exist
#
# Usage: bash lib/push.sh
#
# Environment:
#   BRANCH - Branch name to push
#   GH_TOKEN - GitHub token for push authentication
#   LOOP_HAS_CHANGES - true when loop step produced commits
#   WORKTREE_PATH - Absolute path to the worktree
#
# Output:
#   Writes has_changes to GITHUB_OUTPUT
#
# Design Rules:
#   - Branch names are validated before push
#   - Uses http.extraheader auth (same pattern as actions/checkout)
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# main: Push branch when loop produced changes
#
# Arguments:
#   None
#
# Globals:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success or when no push is needed
#
#######################################
function main {
    : "${BRANCH:?}"
    : "${GH_TOKEN:?}"
    : "${LOOP_HAS_CHANGES:?}"
    : "${WORKTREE_PATH:?}"
    : "${GITHUB_OUTPUT:?}"
    if ! [[ ${BRANCH} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::Invalid branch name: ${BRANCH}"
        exit 1
    fi
    if [[ ${LOOP_HAS_CHANGES} != "true" ]]; then
        echo "has_changes=false" >> "${GITHUB_OUTPUT}"
        return 0
    fi
    cd "${WORKTREE_PATH}" || exit 1
    git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GH_TOKEN}" | base64 -w0)"
    git push -u origin "${BRANCH}"
    echo "has_changes=true" >> "${GITHUB_OUTPUT}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
