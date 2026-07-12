#!/bin/bash
#######################################
# Description: State helpers for loop-detect (targets map + legacy migration)
#
# Usage: source "${LIB_DIR}/state.sh"
#
# Output:
# - None (library file)
#
# Design Rules:
# - Migrates flat last_sha into targets["integration:<default_branch>"] on first read
#######################################

#######################################
# migrate_state_targets: Ensure targets map exists with legacy migration
#
# Arguments:
#   $1 - State file path
#   $2 - Default branch for migration key
#
# Global Variables:
#   None
#
# Returns:
#   None
#
#######################################
function migrate_state_targets {
    local state_file="$1"
    local default_branch="$2"
    local migration_key="integration:${default_branch}"

    if [[ ! -f ${state_file} ]]; then
        jq -n --arg key "${migration_key}" '{targets: {($key): {}}}' > "${state_file}"
        return 0
    fi

    if jq -e '.targets' "${state_file}" > /dev/null 2>&1; then
        return 0
    fi

    local legacy_sha legacy_outcome legacy_failures legacy_reject legacy_open
    legacy_sha=$(jq -r '.last_sha // empty' "${state_file}" 2> /dev/null || true)
    legacy_outcome=$(jq -r '.outcome // empty' "${state_file}" 2> /dev/null || true)
    legacy_failures=$(jq -r '.consecutive_failures // 0' "${state_file}" 2> /dev/null || echo "0")
    legacy_reject=$(jq -r '.last_reject_reason // empty' "${state_file}" 2> /dev/null || true)
    legacy_open=$(jq -c '.open_rejections // []' "${state_file}" 2> /dev/null || echo '[]')

    jq \
        --arg key "${migration_key}" \
        --arg last_sha "${legacy_sha}" \
        --arg outcome "${legacy_outcome}" \
        --arg last_reject_reason "${legacy_reject}" \
        --argjson consecutive_failures "${legacy_failures}" \
        --argjson open_rejections "${legacy_open}" \
        '
        .targets = (.targets // {}) |
        .targets[$key] = (
            .targets[$key] // {}
            | if $last_sha != "" then .last_sha = $last_sha else . end
            | if $outcome != "" then .outcome = $outcome else . end
            | .consecutive_failures = $consecutive_failures
            | if $last_reject_reason != "" then .last_reject_reason = $last_reject_reason else . end
            | .open_rejections = $open_rejections
        )
        | del(.last_sha, .outcome, .consecutive_failures, .last_reject_reason, .open_rejections)
        ' "${state_file}" > "${state_file}.tmp"
    mv "${state_file}.tmp" "${state_file}"
}

#######################################
# read_target_state: Echo JSON object for one target key
#
# Arguments:
#   $1 - State file path
#   $2 - Target key
#   $3 - Default branch for migration
#
# Global Variables:
#   None
#
# Returns:
#   Target state JSON on stdout
#
#######################################
function read_target_state {
    local state_file="$1"
    local target_key="$2"
    local default_branch="$3"

    migrate_state_targets "${state_file}" "${default_branch}"
    jq -c --arg key "${target_key}" '.targets[$key] // {}' "${state_file}" 2> /dev/null || echo '{}'
}

#######################################
# target_consecutive_failures: Read consecutive_failures for target
#
# Arguments:
#   $1 - Target state JSON
#
# Global Variables:
#   None
#
# Returns:
#   Failure count on stdout
#
#######################################
function target_consecutive_failures {
    local target_state="$1"
    jq -r '.consecutive_failures // 0' <<< "${target_state}"
}

#######################################
# target_last_sha: Resolve last_sha for target with fallback
#
# Arguments:
#   $1 - Target state JSON
#   $2 - Branch ref for git fallback
#
# Global Variables:
#   None
#
# Returns:
#   Commit SHA on stdout
#
#######################################
function target_last_sha {
    local target_state="$1"
    local branch_ref="$2"
    local last_sha

    last_sha=$(jq -r '.last_sha // empty' <<< "${target_state}")
    if [[ -n ${last_sha} ]]; then
        printf '%s' "${last_sha}"
        return 0
    fi

    git checkout -q "${branch_ref}" 2> /dev/null || true
    last_sha=$(git rev-parse --verify HEAD~10 2> /dev/null || git rev-list --max-parents=0 HEAD | head -1)
    printf '%s' "${last_sha}"
}

#######################################
# target_open_rejections_prompt: Format open rejections for prompt injection
#
# Arguments:
#   $1 - Target state JSON
#
# Global Variables:
#   None
#
# Returns:
#   Markdown prompt section on stdout (empty when none)
#
#######################################
function target_open_rejections_prompt {
    local target_state="$1"
    local open_json
    open_json=$(jq -c '.open_rejections // []' <<< "${target_state}")
    if [[ "$(jq 'length' <<< "${open_json}")" -eq 0 ]]; then
        return 0
    fi
    jq -r '.[] | "### Attempt \(.attempt // "-")\n- **Files:** " + (if (.files | length) > 0 then (.files | join(", ")) else "not specified" end) + "\n- **Issue:** \(.issue)\n- **Required fix:** \(.fix)\n"' \
        <<< "${open_json}"
}
