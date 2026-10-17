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
# - Only APPROVE with changes moves the cursor: pr_create records pending (the
#   cursor advances when the PR merges), pr_push advances (the head was pushed)
# - delivery none, every other verdict, and no changes record metadata only
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

    if [[ ${verdict} != "APPROVE" || ${has_changes} != "true" ]]; then
        printf '%s\n' "metadata"
        return 0
    fi
    case "${delivery}" in
        pr_create) printf '%s\n' "pending" ;;
        pr_push) printf '%s\n' "advance" ;;
        *) printf '%s\n' "metadata" ;;
    esac
}
