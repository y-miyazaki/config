#!/bin/bash
#######################################
# Description:
#   Normalize persisted loop outcome values to their current names and hold the one
#   outcome mapping table: outcome -> consecutive_failures effect and prune terminality.
#
# Usage:
#   loop_action_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"
#   source "${loop_action_lib}/outcome.sh"
#   outcome_normalize "<value>"
#   outcome_counter_effect "<value>"
#   outcome_is_prune_terminal "<value>"
#
# Design Rules:
#   - Functions are pure: no globals are read or written
#   - Old persisted names map to new names; every other value passes through unchanged
#   - Outcome mapping table (single source for write_state.sh, prune_targets.sh and loop-state-promote):
#       rejected, pr_closed  -> consecutive_failures +1; prune terminal
#       watch, error         -> consecutive_failures kept; not terminal
#       every other outcome  -> consecutive_failures reset to 0; not terminal
#     pr_closed is written by loop-state-promote when a loop PR closes without merging
#
# Output:
#   Normalized outcome on stdout
#######################################

#######################################
# outcome_normalize: Map an old persisted outcome value to its current name
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
function outcome_normalize {
    local value="${1:-}"

    case "${value}" in
        pr-created) echo "pr_created" ;;
        merged) echo "pr_merged" ;;
        pr-closed) echo "pr_closed" ;;
        no-changes | no-action) echo "unchanged" ;;
        *) echo "${value}" ;;
    esac
}

#######################################
# outcome_counter_effect: Return how an outcome changes consecutive_failures
#
# Globals:
#   None
#
# Arguments:
#   $1 - outcome value (old or new name)
#
# Outputs:
#   STDOUT: increment | keep | reset
#
# Returns:
#   0 always
#
#######################################
function outcome_counter_effect {
    case "$(outcome_normalize "${1:-}")" in
        rejected | pr_closed) echo "increment" ;;
        watch | error) echo "keep" ;;
        *) echo "reset" ;;
    esac
}

#######################################
# outcome_is_prune_terminal: Return success when the retention prune treats the outcome as terminal
#
# Globals:
#   None
#
# Arguments:
#   $1 - outcome value (old or new name)
#
# Outputs:
#   None
#
# Returns:
#   0 when the outcome is rejected or pr_closed; 1 otherwise
#
#######################################
function outcome_is_prune_terminal {
    case "$(outcome_normalize "${1:-}")" in
        rejected | pr_closed) return 0 ;;
        *) return 1 ;;
    esac
}
