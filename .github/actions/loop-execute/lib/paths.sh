#!/bin/bash
#######################################
# Description: Path guard utilities for loop-execute verification
#
# Usage: source "${SCRIPT_DIR}/lib/paths.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Allowlist and denylist checks live in lib/loop/edit_paths.sh (sourced below)
# - This file keeps checker-text path inference and branch diff listing
#######################################

# shellcheck source=../../lib/loop/edit_paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)/edit_paths.sh"

#######################################
# infer_files_from_text: Infer file paths from checker text
#
# Globals:
#   AGENT_CHECKER_PATH_PATTERN - Optional extended-regex override
#
# Arguments:
#   $1 - Checker text to scan
#   $2 - Fallback comma-separated file paths
#
# Outputs:
#   Comma-separated file paths to stdout
#
# Returns:
#   0 on success
#
#######################################
function infer_files_from_text {
    local text="$1"
    local fallback="$2"
    local inferred=""
    if [[ -n ${AGENT_CHECKER_PATH_PATTERN:-} ]]; then
        inferred=$(printf '%s\n' "${text}" | grep -oE "${AGENT_CHECKER_PATH_PATTERN}" | sort -u | paste -sd, - || true)
    else
        inferred=$(printf '%s\n' "${text}" | grep -oE '[[:alnum:]_.-]+/[^[:space:],)]+' | sort -u | paste -sd, - || true)
    fi
    if [[ -n ${inferred} ]]; then
        printf '%s' "${inferred}"
    else
        printf '%s' "${fallback}"
    fi
}

#######################################
# list_non_loop_branch_files: List files that differ from the base branch
#
# Description:
#   Uses origin/<base> when that ref exists (after a best-effort fetch),
#   otherwise <base>. Ignores .loop/ so state-only commits are not treated
#   as product changes.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Worktree path
#   $2 - Base branch name
#
# Outputs:
#   Newline-separated repo-relative paths to stdout, or nothing
#
# Returns:
#   0 on success
#
#######################################
function list_non_loop_branch_files {
    local worktree="${1:?}"
    local base_branch="${2:?}"
    local base_ref
    (
        cd "${worktree}" || exit 1
        # No --depth=1: a shallow fetch over a full checkout grafts the base ref
        # into a rootless commit and the three-dot diff then fails with
        # "no merge base", which would read here as an empty change set.
        git fetch origin "${base_branch}" > /dev/null 2>&1 || true
        base_ref="origin/${base_branch}"
        if ! git rev-parse --verify "${base_ref}" > /dev/null 2>&1; then
            base_ref="${base_branch}"
        fi
        if ! git diff --name-only --no-renames "${base_ref}...HEAD" -- . ':!.loop/'; then
            echo "::error::Branch diff against ${base_ref} failed; path guards saw no files" >&2
        fi
    )
}
