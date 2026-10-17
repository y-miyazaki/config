#!/bin/bash
#######################################
# Description: Map loop-finalize inputs to the run outcome written to state and run log
#
# Usage: source "${GITHUB_ACTION_PATH}/lib/determine_outcome.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - An explicit outcome override always wins
# - A failed agent job is error; no product diff is rejected (REJECT) or no-changes
# - APPROVE with changes is pr-created, except finalize strategy none, which opens
#   no PR and lands nothing: it records reported (domain persistence delivered it)
# - Any other verdict with changes is error
#######################################

#######################################
# determine_outcome: Resolve the run outcome
#
# Globals:
#   None
#
# Arguments:
#   $1 - Outcome override (empty when none)
#   $2 - Agent job result (success, skipped, failure, cancelled)
#   $3 - has_changes flag (true/false)
#   $4 - Verdict (APPROVE, REJECT, or empty)
#   $5 - Finalize strategy (open_pr, push, push_head, none; may be empty)
#
# Outputs:
#   Outcome to stdout (pr-created, reported, no-changes, rejected, error, or the override)
#
# Returns:
#   0 always
#
#######################################
function determine_outcome {
    local override="$1"
    local agent_result="$2"
    local has_changes="$3"
    local verdict="$4"
    local strategy="${5:-}"

    if [[ -n ${override} ]]; then
        printf '%s\n' "${override}"
    elif [[ ${agent_result} != "success" && ${agent_result} != "skipped" ]]; then
        printf '%s\n' "error"
    elif [[ ${has_changes} != "true" ]]; then
        if [[ ${verdict} == "REJECT" ]]; then
            printf '%s\n' "rejected"
        else
            printf '%s\n' "no-changes"
        fi
    elif [[ ${verdict} == "APPROVE" ]]; then
        if [[ ${strategy} == "none" ]]; then
            printf '%s\n' "reported"
        else
            printf '%s\n' "pr-created"
        fi
    elif [[ ${verdict} == "REJECT" ]]; then
        printf '%s\n' "rejected"
    else
        printf '%s\n' "error"
    fi
}
