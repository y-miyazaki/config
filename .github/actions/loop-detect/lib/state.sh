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
# snapshot_state_from_branch: Copy the state file as it is on the state branch to a stable path
#
# Description:
#   Per-target state is authoritative on the state branch (write_state and loop-state-promote read
#   origin/<state_branch>). Detect switches the working tree to each target branch or PR head, where
#   the tracked copy of the state file is stale, so it snapshots the state branch once before any
#   checkout and reads the snapshot. A missing file on the branch leaves the destination absent so
#   migrate_state_targets creates the default; a failed fetch falls back to the local copy.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Repo-relative state file path
#   $2 - State branch name
#   $3 - Destination path (removed first)
#
# Outputs:
#   STDOUT: error annotation for an invalid branch name, warning when the fetch fails
#
# Returns:
#   0 on success (including a missing state file); 1 when the branch name is invalid
#
#######################################
function snapshot_state_from_branch {
    local state_file="$1"
    local branch="$2"
    local dest="$3"

    if ! check_names_branch "${branch}"; then
        echo "::error::Invalid state branch: ${branch}"
        return 1
    fi
    rm -f "${dest}"
    if git fetch origin "${branch}" > /dev/null 2>&1; then
        if git cat-file -e "origin/${branch}:${state_file}" 2> /dev/null; then
            git show "origin/${branch}:${state_file}" > "${dest}"
        fi
        return 0
    fi
    echo "::warning::loop-detect/state: could not fetch ${branch}; reading the local ${state_file}"
    if [[ -f ${state_file} ]]; then
        cp "${state_file}" "${dest}"
    fi
    return 0
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
#   $3 - verify_reachable (true | empty): when true, a stored sha that is not a
#        commit in this checkout falls back like a missing sha, with a warning
#
# Outputs:
#   Commit SHA on stdout; the unreachable-sha warning on stderr
#
# Returns:
#   0 on success
#
#######################################
function target_last_sha {
    local target_state="$1"
    local branch_ref="$2"
    local verify_reachable="${3:-}"
    local last_sha

    last_sha=$(jq -r '.last_sha // empty' <<< "${target_state}")
    if [[ -n ${last_sha} ]]; then
        if [[ ${verify_reachable} != "true" ]] || git cat-file -e "${last_sha}^{commit}" 2> /dev/null; then
            printf '%s' "${last_sha}"
            return 0
        fi
        echo "::warning::loop-detect: stored last_sha ${last_sha} is not reachable; falling back to HEAD~10" >&2
    fi

    git checkout -q "${branch_ref}" 2> /dev/null || true
    last_sha=$(git rev-parse --verify HEAD~10 2> /dev/null || git rev-list --max-parents=0 HEAD | head -1)
    printf '%s' "${last_sha}"
}

#######################################
# target_state_apply_merged_pending: Treat a merged pending fix PR as promoted
#
# Description:
#   loop-state-promote promotes pending to last_sha only for a PR that carries the loop label. A
#   merged pending PR whose label was removed would leave last_sha behind, so detect would scan the
#   range the PR already covered. This function applies the promotion to the in-memory state only
#   (detect never writes state): last_sha becomes pending.sha and pending is dropped.
#
# Globals:
#   GITHUB_TOKEN - Used for the live PR state lookup
#
# Arguments:
#   $1 - Target state JSON
#
# Outputs:
#   Target state JSON on stdout (promoted when the pending PR is MERGED, unchanged otherwise)
#
# Returns:
#   0 always
#
#######################################
function target_state_apply_merged_pending {
    local target_state="$1"
    local pending_pr pr_state

    if ! jq -e '(.pending.pr | type) == "number" and (.pending.sha | type) == "string"' <<< "${target_state}" > /dev/null 2>&1; then
        printf '%s' "${target_state}"
        return 0
    fi
    if [[ -z ${GITHUB_TOKEN:-} ]] || ! command -v gh > /dev/null 2>&1; then
        printf '%s' "${target_state}"
        return 0
    fi

    pending_pr="$(jq -r '.pending.pr' <<< "${target_state}")"
    pr_state="$(gh pr view "${pending_pr}" --json state --jq '.state' 2> /dev/null || true)"
    if [[ ${pr_state} == "MERGED" ]]; then
        echo "::notice::Pending PR #${pending_pr} is MERGED; promoting pending.sha to last_sha for this run" >&2
        jq -c '.last_sha = .pending.sha | del(.pending)' <<< "${target_state}"
        return 0
    fi
    printf '%s' "${target_state}"
}

#######################################
# target_pending_blocks_detect: Return 0 when an open pending fix PR blocks detect
#
# Globals:
#   GITHUB_TOKEN - Used for live PR state lookup when pending.pr is set
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
    local pending_pr pr_state github_token

    if ! jq -e '(.pending.pr | type) == "number"' <<< "${target_state}" > /dev/null 2>&1; then
        return 1
    fi

    pending_pr="$(jq -r '.pending.pr' <<< "${target_state}")"
    github_token="${GITHUB_TOKEN:-}"
    if [[ -z ${github_token} ]] || ! command -v gh > /dev/null 2>&1; then
        echo "::warning::Pending PR #${pending_pr} present but gh/token unavailable; blocking detect"
        return 0
    fi

    export GITHUB_TOKEN="${github_token}"
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
