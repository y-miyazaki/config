#!/bin/bash
#######################################
# Description: Decide whether loop-finalize should delete the work branch
#
# Usage: source "${GITHUB_ACTION_PATH}/lib/should_delete_rejected_branch.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Delete only empty-vs-base REJECT runs (has_changes is not true)
# - Keep the branch when REJECT still has a product diff vs base (open PR / retries)
#######################################

#######################################
# should_delete_rejected_branch: Whether finalize should delete the work branch
#
# Globals:
#   None
#
# Arguments:
#   $1 - Verdict (APPROVE or REJECT)
#   $2 - has_changes flag (true/false)
#
# Outputs:
#   None
#
# Returns:
#   0 when the branch should be deleted, 1 otherwise
#
#######################################
function should_delete_rejected_branch {
    local verdict="$1"
    local has_changes="$2"
    if [[ ${verdict} == "REJECT" && ${has_changes} != "true" ]]; then
        return 0
    fi
    return 1
}
