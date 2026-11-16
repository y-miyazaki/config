#!/bin/bash
#######################################
# Description:
#   The one definition of the names loop actions accept before they reach git, gh or a file path:
#   branch names, the loop name and the state file path. Every action sources this file; none keeps its own regex.
#
# Usage:
#   source "${GITHUB_ACTION_PATH}/../lib/loop/check_names.sh"
#   check_names_branch "${BRANCH}" || exit 1
#   check_names_state_file "${STATE_FILE}" || exit 1
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Functions only return a status; callers print their own error with their own context
#   - A branch name starts with an alphanumeric, "_", "." or "/", never "-", so git never reads it as an option
#   - A branch name and a state file path never contain ".." (git refuses it in a ref name too)
#   - The loop name starts with an alphanumeric and holds only alphanumerics, "_", "." and "-"
#   - The state file path is .loop/state-<name>.json, the pattern loop-state-promote lists
#   - Change a rule here and add a Bats case in test/bats/.github/actions/lib/loop/check_names.bats
#######################################

#######################################
# check_names_branch: Check a git branch name (or ref name) used in fetch, checkout, push and API paths
#
# Globals:
#   None
#
# Arguments:
#   $1 - Branch name
#
# Outputs:
#   None
#
# Returns:
#   0 when the name is accepted; 1 when it is empty, starts with "-", contains ".." or an unsafe character
#
#######################################
function check_names_branch {
    local name="${1:-}"

    [[ ${name} =~ ^[A-Za-z0-9_./][A-Za-z0-9/_.-]*$ ]] && [[ ${name} != *".."* ]]
}

#######################################
# check_names_loop_name: Check a loop name used to derive the state file path and branch names
#
# Globals:
#   None
#
# Arguments:
#   $1 - Loop name
#
# Outputs:
#   None
#
# Returns:
#   0 when the name is accepted; 1 otherwise
#
#######################################
function check_names_loop_name {
    local name="${1:-}"

    [[ ${name} =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
}

#######################################
# check_names_state_file: Check a loop state file path
#
# Globals:
#   None
#
# Arguments:
#   $1 - Repo-relative state file path
#
# Outputs:
#   None
#
# Returns:
#   0 when the path is .loop/state-<name>.json without ".."; 1 otherwise
#
#######################################
function check_names_state_file {
    local path="${1:-}"

    [[ ${path} =~ ^\.loop/state-[A-Za-z0-9_.-]+\.json$ ]] && [[ ${path} != *".."* ]]
}
