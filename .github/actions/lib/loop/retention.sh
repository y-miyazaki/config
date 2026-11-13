#!/bin/bash
#######################################
# Description:
#   The one definition of the loop retention window (30 days) used by the run log prune, the budget
#   aggregation and the state target prune.
#
# Usage:
#   source "${LIB_DIR}/../../lib/loop/retention.sh"
#   cutoff="$(retention_cutoff_date)"
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - The window is a single constant; callers never spell "30 days" themselves
#   - GNU date is tried first, BSD date as the fallback (local runs on macOS)
#######################################

#######################################
# retention_cutoff_date: Date (UTC, YYYY-MM-DD) 30 days ago
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   STDOUT: the cutoff date
#
# Returns:
#   0 on success
#
#######################################
function retention_cutoff_date {
    date -u -d '30 days ago' +%Y-%m-%d 2> /dev/null || date -u -v-30d +%Y-%m-%d
}
