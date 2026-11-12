#!/bin/bash
#######################################
# Description:
#   Copy state-branch files (state file, run log) to stable paths before any target checkout.
#
# Usage:
#   source "${LIB_DIR}/../../lib/loop/state_snapshot.sh"
#   state_snapshot_from_branch "${STATE_BRANCH}" "${STATE_FILE}" "${state_copy}" "${RUN_LOG_FILE}" "${run_log_copy}"
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Per-target state is authoritative on the state branch (write_state and loop-state-promote
#     read origin/<state_branch>); the checked-out tree may be a PR head holding a stale copy
#   - The branch is fetched once per call, however many files are copied
#   - A file missing on the branch leaves its destination absent, so a first run starts from the default
#   - A failed fetch falls back to the local copy with a warning
#   - Policy configuration (the budget file) is not state: read it from the trusted checkout, never from here
#   - The branch name goes through check_names_branch (lib/loop/check_names.sh, sourced by the caller)
#######################################

#######################################
# state_snapshot_from_branch: Copy files as they are on origin/<branch> to the given destinations
#
# Globals:
#   None
#
# Arguments:
#   $1 - State branch name
#   $2... - Pairs of <repo-relative file> <destination path>; each destination is removed first
#
# Outputs:
#   STDOUT: error annotation for an invalid branch name; warning when the fetch fails
#
# Returns:
#   0 on success (including missing files); 1 when the branch name is invalid or the pairs are odd
#
#######################################
function state_snapshot_from_branch {
    local branch="$1"
    shift
    local fetched="false"
    local file dest

    if ! check_names_branch "${branch}"; then
        echo "::error::Invalid state branch: ${branch}"
        return 1
    fi
    if (($# % 2 != 0)); then
        echo "::error::state_snapshot_from_branch needs <file> <destination> pairs"
        return 1
    fi
    if git fetch origin "${branch}" > /dev/null 2>&1; then
        fetched="true"
    else
        echo "::warning::loop-state-snapshot: could not fetch ${branch}; reading the local copies"
    fi

    while (($# > 0)); do
        file="$1"
        dest="$2"
        shift 2
        rm -f "${dest}"
        if [[ ${fetched} == "true" ]]; then
            if git cat-file -e "origin/${branch}:${file}" 2> /dev/null; then
                git show "origin/${branch}:${file}" > "${dest}"
            fi
        elif [[ -f ${file} ]]; then
            cp "${file}" "${dest}"
        fi
    done
    return 0
}
