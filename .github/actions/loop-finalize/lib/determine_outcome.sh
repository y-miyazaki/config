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
# - Decision order: failed agent push (error), override, failed agent (error),
#   REJECT (rejected), message deliveries, then the has_changes rules
# - A failed agent push (push_failed=true) is error, even over an outcome
#   override: the branch never reached the remote
# - An explicit outcome override wins over everything else
# - A failed agent job is error
# - REJECT is rejected for every delivery, with or without changes
# - issue_comment is issue_commented and pr_review is pr_reviewed, with or without
#   changes (the posted message is the product, not a diff)
# - No product diff is unchanged
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
#   $5 - Delivery (pr_create, pr_push, none, issue_comment, pr_review)
#   $6 - push_failed flag (true when the agent push failed; optional, defaults to false)
#
# Outputs:
#   Outcome to stdout (pr_created, pr_pushed, reported, issue_commented, pr_reviewed,
#   unchanged, rejected, error, or the override)
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
    local push_failed="${6:-false}"

    if [[ ${push_failed} == "true" ]]; then
        printf '%s\n' "error"
    elif [[ -n ${override} ]]; then
        printf '%s\n' "${override}"
    elif [[ ${agent_result} != "success" && ${agent_result} != "skipped" ]]; then
        printf '%s\n' "error"
    elif [[ ${verdict} == "REJECT" ]]; then
        printf '%s\n' "rejected"
    elif [[ ${delivery} == "issue_comment" ]]; then
        printf '%s\n' "issue_commented"
    elif [[ ${delivery} == "pr_review" ]]; then
        printf '%s\n' "pr_reviewed"
    elif [[ ${has_changes} != "true" ]]; then
        printf '%s\n' "unchanged"
    elif [[ ${verdict} == "APPROVE" ]]; then
        case "${delivery}" in
            pr_create) printf '%s\n' "pr_created" ;;
            pr_push) printf '%s\n' "pr_pushed" ;;
            none) printf '%s\n' "reported" ;;
            *) printf '%s\n' "error" ;;
        esac
    else
        printf '%s\n' "error"
    fi
}
