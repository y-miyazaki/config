#!/bin/bash
#######################################
# Description: Decide whether loop-finalize should push the agent branch into the target branch
#
# Usage: source "${GITHUB_ACTION_PATH}/lib/should_push_target.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Push only APPROVE runs that have changes and a non-empty agent branch
# - Push only for finalize strategies push and push_head
# - Never push for open_pr (PR flow) or none (review-only); unknown values do not push
#######################################

#######################################
# should_push_target: Whether finalize should push the agent branch to the target branch
#
# Globals:
#   None
#
# Arguments:
#   $1 - Verdict (APPROVE or REJECT)
#   $2 - has_changes flag (true/false)
#   $3 - Agent branch name
#   $4 - finalize strategy (push, push_head, open_pr, none)
#
# Outputs:
#   None
#
# Returns:
#   0 when the branch should be pushed, 1 otherwise
#
#######################################
function should_push_target {
    local verdict="$1"
    local has_changes="$2"
    local branch="$3"
    local strategy="$4"
    if [[ ${verdict} != "APPROVE" || ${has_changes} != "true" || -z ${branch} ]]; then
        return 1
    fi
    case "${strategy}" in
        push | push_head) return 0 ;;
        *) return 1 ;;
    esac
}
