#!/bin/bash
#######################################
# Description:
#   Normalize persisted loop outcome values to their current names.
#
# Usage:
#   loop_action_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"
#   source "${loop_action_lib}/outcome.sh"
#   normalize_outcome "<value>"
#
# Design Rules:
#   - Functions are pure: no globals are read or written
#   - Old persisted names map to new names; every other value passes through unchanged
#
# Output:
#   Normalized outcome on stdout
#######################################

#######################################
# normalize_outcome: Map an old persisted outcome value to its current name
#
# Globals:
#   None
#
# Arguments:
#   $1 - outcome value (old names: pr-created | merged | pr-closed | no-changes | no-action;
#        any other value, including new names and empty, passes through)
#
# Outputs:
#   STDOUT: the normalized outcome value
#
# Returns:
#   0 always
#
#######################################
function normalize_outcome {
    local value="${1:-}"

    case "${value}" in
        pr-created) echo "pr_created" ;;
        merged) echo "pr_merged" ;;
        pr-closed) echo "pr_closed" ;;
        no-changes | no-action) echo "unchanged" ;;
        *) echo "${value}" ;;
    esac
}
