#!/bin/bash
#######################################
# Description: Map loop-finalize inputs to the state write mode used by write_state.sh
#
# Usage: source "${GITHUB_ACTION_PATH}/lib/resolve_state_write_mode.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Only APPROVE with changes and a pushed agent branch moves the cursor:
#   pr_create records pending (the cursor advances when the PR merges), pr_push
#   advances (the head was pushed)
# - pr_create and pr_push record metadata unless pushed=true (agent failure or a
#   missing bundle leaves pushed=false failed=false: nothing landed, no PR exists)
# - delivery none, every other verdict, and no changes record metadata only
# - A failed agent push (push_failed=true) records metadata for every delivery
# - Unknown delivery values record metadata (never advance the cursor)
#######################################

#######################################
# resolve_state_write_mode: Resolve the state write mode for a finalize run
#
# Globals:
#   None
#
# Arguments:
#   $1 - Verdict (APPROVE, REJECT, or empty)
#   $2 - has_changes flag (true/false)
#   $3 - Delivery (pr_create, pr_push, none)
#   $4 - push_failed flag (true when the agent push failed; optional, defaults to false)
#   $5 - pushed flag (true when the agent branch was pushed; optional, defaults to
#        false, which makes pr_create and pr_push metadata)
#
# Outputs:
#   Mode to stdout (pending, advance, or metadata)
#
# Returns:
#   0 always
#
#######################################
function resolve_state_write_mode {
    local verdict="$1"
    local has_changes="$2"
    local delivery="${3:-}"
    local push_failed="${4:-false}"
    local pushed="${5:-false}"

    if [[ ${push_failed} == "true" || ${verdict} != "APPROVE" || ${has_changes} != "true" ]]; then
        printf '%s\n' "metadata"
        return 0
    fi
    case "${delivery}" in
        pr_create | pr_push)
            if [[ ${pushed} != "true" ]]; then
                printf '%s\n' "metadata"
            elif [[ ${delivery} == "pr_create" ]]; then
                printf '%s\n' "pending"
            else
                printf '%s\n' "advance"
            fi
            ;;
        *) printf '%s\n' "metadata" ;;
    esac
}
