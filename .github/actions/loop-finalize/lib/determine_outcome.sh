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
# - A failed agent job is error; no product diff is rejected (REJECT) or unchanged
# - APPROVE with changes follows delivery: pr_create is pr_created, pr_push is
#   pr_pushed, none is reported (no PR, nothing landed; the finalize hook delivered it)
# - APPROVE with changes and an unknown delivery is error (fail closed)
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
#   $5 - Delivery (pr_create, pr_push, none)
#
# Outputs:
#   Outcome to stdout (pr_created, pr_pushed, reported, unchanged, rejected, error,
#   or the override)
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
    local delivery="${5:-}"

    if [[ -n ${override} ]]; then
        printf '%s\n' "${override}"
    elif [[ ${agent_result} != "success" && ${agent_result} != "skipped" ]]; then
        printf '%s\n' "error"
    elif [[ ${has_changes} != "true" ]]; then
        if [[ ${verdict} == "REJECT" ]]; then
            printf '%s\n' "rejected"
        else
            printf '%s\n' "unchanged"
        fi
    elif [[ ${verdict} == "APPROVE" ]]; then
        case "${delivery}" in
            pr_create) printf '%s\n' "pr_created" ;;
            pr_push) printf '%s\n' "pr_pushed" ;;
            none) printf '%s\n' "reported" ;;
            *) printf '%s\n' "error" ;;
        esac
    elif [[ ${verdict} == "REJECT" ]]; then
        printf '%s\n' "rejected"
    else
        printf '%s\n' "error"
    fi
}
