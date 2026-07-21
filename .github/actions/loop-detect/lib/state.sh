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
# Globals:
#   None
#
# Arguments:
#   $1 - State file path
#   $2 - Default branch for migration key
#
# Outputs:
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
# Globals:
#   None
#
# Arguments:
#   $1 - State file path
#   $2 - Target key
#   $3 - Default branch for migration
#
# Outputs:
#   Target state JSON on stdout
#
# Returns:
#   0 on success
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
# Globals:
#   None
#
# Arguments:
#   $1 - Target state JSON
#
# Outputs:
#   Failure count on stdout
#
# Returns:
#   0 on success
#
#######################################
function target_consecutive_failures {
    local target_state="$1"
    jq -r '.consecutive_failures // 0' <<< "${target_state}"
}

#######################################
# target_last_sha: Resolve last_sha for target with fallback
#
# Globals:
#   None
#
# Arguments:
#   $1 - Target state JSON
#   $2 - Branch ref for git fallback
#
# Outputs:
#   Commit SHA on stdout
#
# Returns:
#   0 on success
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
# target_pending_blocks_detect: Return 0 when an open pending fix PR blocks detect
#
# Globals:
#   GH_TOKEN / GITHUB_TOKEN - Used for live PR state lookup when pending.pr is set
#
# Arguments:
#   $1 - Target state JSON
#
# Outputs:
#   None
#
# Returns:
#   0 when pending.pr refers to an OPEN PR (or PR state cannot be resolved),
#   1 when pending is absent or the PR is CLOSED/MERGED (stale cursor)
#
#######################################
function target_pending_blocks_detect {
    local target_state="$1"
    local pending_pr pr_state gh_token

    if ! jq -e '(.pending.pr | type) == "number"' <<< "${target_state}" > /dev/null 2>&1; then
        return 1
    fi

    pending_pr="$(jq -r '.pending.pr' <<< "${target_state}")"
    gh_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [[ -z ${gh_token} ]] || ! command -v gh > /dev/null 2>&1; then
        echo "::warning::Pending PR #${pending_pr} present but gh/token unavailable; blocking detect"
        return 0
    fi

    export GH_TOKEN="${gh_token}"
    pr_state="$(gh pr view "${pending_pr}" --json state --jq '.state' 2> /dev/null || true)"
    case "${pr_state}" in
        OPEN)
            return 0
            ;;
        CLOSED | MERGED)
            echo "::warning::Pending PR #${pending_pr} is ${pr_state}; treating pending as stale (promote should clear it)"
            return 1
            ;;
        *)
            echo "::warning::Pending PR #${pending_pr} state unresolved (${pr_state:-empty}); blocking detect"
            return 0
            ;;
    esac
}

#######################################
# target_open_rejections_prompt: Format open rejections for prompt injection
#
# Globals:
#   None
#
# Arguments:
#   $1 - Target state JSON
#
# Outputs:
#   Markdown prompt section on stdout (empty when none)
#
# Returns:
#   0 on success
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
