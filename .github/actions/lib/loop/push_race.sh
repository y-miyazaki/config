#!/bin/bash
#######################################
# Description:
#   Detect a git push rejected because the remote branch moved (a push race).
#
# Usage:
#   loop_action_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"
#   source "${loop_action_lib}/push_race.sh"
#   if is_push_race_error "${push_err}"; then ...; fi
#
# Design Rules:
#   - Functions are pure: no globals are read or written
#   - Shared by every loop state writer so one definition decides what a push race is
#
# Output:
#   None
#######################################

#######################################
# is_push_race_error: Detect a push rejected because the remote moved
#
# Globals:
#   None
#
# Arguments:
#   $1 - git push stderr text
#
# Outputs:
#   None
#
# Returns:
#   0 for "! [rejected] ... (fetch first|non-fast-forward)" without "[remote rejected]", 1 otherwise
#
#######################################
function is_push_race_error {
    local text="$1"

    if [[ ${text} == *"[remote rejected]"* ]]; then
        return 1
    fi
    [[ ${text} =~ \!\ \[rejected\].*\((fetch\ first|non-fast-forward)\) ]]
}
