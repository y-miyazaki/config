#!/bin/bash
#######################################
# Description: Remove the loop worktree after execution
#
# Usage: bash lib/cleanup.sh
#
# Environment:
#   GITHUB_WORKSPACE - Repository workspace root
#   WORKTREE_PATH - Absolute path to the worktree to remove
#
# Output:
#   None
#
# Design Rules:
#   - Runs under if: always() from action.yml
#   - Best-effort removal; failures do not fail the job
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# main: Remove worktree and prune stale entries
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
#   0
#
#######################################
function main {
    : "${GITHUB_WORKSPACE:?}"
    : "${WORKTREE_PATH:?}"
    cd "${GITHUB_WORKSPACE}" || exit 1
    git worktree remove "${WORKTREE_PATH}" --force 2> /dev/null || true
    git worktree prune
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
