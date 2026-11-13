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
#   - Without an origin remote (a local-only checkout) the local copies are used; with one, a failed fetch fails closed (return 1) unless the branch does not exist on the remote yet; the checked-out tree is never read
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
#   0 on success (including missing files or a branch that does not exist yet); 1 when the branch name is invalid,
#   the pairs are odd, or the fetch fails while the branch exists
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
    if ! git remote get-url origin > /dev/null 2>&1; then
        # No remote at all (a local-only checkout): there is no state branch to read, so use the local copies.
        while (($# > 0)); do
            rm -f "$2"
            [[ -f $1 ]] && cp "$1" "$2"
            shift 2
        done
        return 0
    fi
    if git fetch origin "${branch}" > /dev/null 2>&1; then
        fetched="true"
    elif git ls-remote --exit-code --heads origin "${branch}" > /dev/null 2>&1 || [[ $? -ne 2 ]]; then
        # The branch exists (or the remote is unreachable): fail closed, never read the checked-out tree.
        echo "::error::loop-state-snapshot: could not fetch ${branch}; state cannot be read"
        return 1
    fi
    # Otherwise the state branch does not exist yet: every file is absent and the run starts from the default.

    while (($# > 0)); do
        file="$1"
        dest="$2"
        shift 2
        rm -f "${dest}"
        if [[ ${fetched} == "true" ]] && git cat-file -e "origin/${branch}:${file}" 2> /dev/null; then
            git show "origin/${branch}:${file}" > "${dest}"
        fi
    done
    return 0
}
