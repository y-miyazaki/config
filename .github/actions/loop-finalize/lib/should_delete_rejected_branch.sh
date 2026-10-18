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
# - Delivery none, issue_comment, and pr_review always delete: nothing is merged or
#   opened as a PR, and the finalize script has already read the branch
# - Otherwise delete only empty-vs-base REJECT runs (has_changes is not true)
# - Keep the branch when REJECT still has a product diff vs base (open PR / retries)
#######################################

#######################################
# should_delete_rejected_branch: Whether finalize should delete the work branch
#
# Globals:
#   None
#
# Arguments:
#   $1 - Verdict (APPROVE or REJECT; may be empty)
#   $2 - has_changes flag (true/false)
#   $3 - Delivery (pr_create, pr_push, none, issue_comment, pr_review)
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
    local delivery="${3:-}"
    case "${delivery}" in
        none | issue_comment | pr_review) return 0 ;;
    esac
    if [[ ${verdict} == "REJECT" && ${has_changes} != "true" ]]; then
        return 0
    fi
    return 1
}
