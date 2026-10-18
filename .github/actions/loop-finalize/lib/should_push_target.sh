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
# - Push only for delivery pr_push (merge into the existing PR head)
# - Never push for pr_create (PR flow) or none (no delivery); unknown values do not push
# - Mirrors the `if:` of the "Push to Target Branch" step (lib/push_target.sh) in
#   action.yml, which is the gate that runs; keep the two in sync
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
#   $4 - Delivery (pr_create, pr_push, none)
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
    local delivery="$4"
    if [[ ${verdict} != "APPROVE" || ${has_changes} != "true" || -z ${branch} ]]; then
        return 1
    fi
    [[ ${delivery} == "pr_push" ]]
}
