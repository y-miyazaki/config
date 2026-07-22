#!/bin/bash
#######################################
# Description:
#   Write loop state JSON and commit/push to LOOP_STATE_PUSH_BRANCH.
#   Environment variables mirror loop-state-write composite action inputs.
#
# Usage:
#   GH_TOKEN=... STATE_FILE=... TARGET_KEY=... bash lib/run.sh
#
# Design Rules:
#   - state_write_mode controls whether last_sha, pending, or metadata is updated
#   - Prefer direct push to branch_state; open auto-merge state PR when push is blocked
#   - PR fallback is blocked for advance + pr-created (use pending mode for L2 open_pr)
#
# Output:
#   Commits state (and optional additional paths) to the resolved push branch
#
# Dependencies:
#   - bash, git, jq, gh, openssl
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prune_targets.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/prune_targets.sh"

#######################################
# Global variables
#######################################
REJECT_REASON="${REJECT_REASON:-}"
OPEN_REJECTIONS="${OPEN_REJECTIONS:-[]}"
WRITE_TARGET_STATE="${WRITE_TARGET_STATE:-true}"
ADDITIONAL_COMMIT_PATHS="${ADDITIONAL_COMMIT_PATHS:-}"
STATE_PUSH_BRANCH="${STATE_PUSH_BRANCH:-}"
BASE_BRANCH="${BASE_BRANCH:-main}"
TARGET_KEY="${TARGET_KEY:-}"
OUTCOME="${OUTCOME:-}"
SHA="${SHA:-}"
STATE_WRITE_MODE="${STATE_WRITE_MODE:-advance}"
PENDING_PR_NUMBER="${PENDING_PR_NUMBER:-}"
PENDING_PR_URL="${PENDING_PR_URL:-}"
LOOP_NAME="${LOOP_NAME:-}"
SKIP_STATE_PR="${SKIP_STATE_PR:-false}"

READ_BRANCH=""
PUSH_BRANCH=""
STATE_TMP=""

#######################################
# commit_and_push_state: Commit state paths and push or open fallback PR
#
# Globals:
#   STATE_FILE - Path to state JSON
#   STATE_TMP - Prepared state content
#   PUSH_BRANCH - Git push destination branch
#   READ_BRANCH - branch_state for direct push
#   SKIP_STATE_PR - When true, skip PR fallback on push failure
#   STATE_WRITE_MODE - advance|pending|metadata|promote|clear_pending
#   ADDITIONAL_COMMIT_PATHS - Optional comma-separated extra paths
#   SHA - Cursor SHA for PR body text
#   OUTCOME - Outcome for PR body text
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 0 when there is nothing to commit or push succeeds
#
#######################################
function commit_and_push_state {
    local -a paths_to_add=("${STATE_FILE}")
    local item has_changes path

    mkdir -p "$(dirname "${STATE_FILE}")"
    cp "${STATE_TMP}" "${STATE_FILE}"

    if [[ -n ${ADDITIONAL_COMMIT_PATHS} ]]; then
        declare -a extra=()
        IFS=',' read -r -a extra <<< "${ADDITIONAL_COMMIT_PATHS}"
        for item in "${extra[@]}"; do
            item="${item#"${item%%[![:space:]]*}"}"
            item="${item%"${item##*[![:space:]]}"}"
            [[ -z ${item} ]] && continue
            paths_to_add+=("${item}")
        done
    fi

    has_changes="false"
    for path in "${paths_to_add[@]}"; do
        if ! git diff --quiet "${path}" 2> /dev/null || [[ -n $(git status --porcelain "${path}") ]]; then
            has_changes="true"
            break
        fi
    done
    if [[ ${has_changes} != "true" ]]; then
        echo "No state changes to commit."
        return 0
    fi

    for path in "${paths_to_add[@]}"; do
        if [[ -e ${path} ]] || [[ -n $(git status --porcelain "${path}") ]]; then
            git add "${path}" || true
        fi
    done
    git commit -m "chore(loop): update state [skip ci]"
    if git push origin HEAD:"${PUSH_BRANCH}" 2> /dev/null; then
        echo "State pushed to ${PUSH_BRANCH}."
        return 0
    fi

    if [[ ${SKIP_STATE_PR} == "true" ]]; then
        echo "::warning::Direct push blocked; skipping state PR (skip_state_pr=true)."
        return 0
    fi

    if [[ ${STATE_WRITE_MODE} == "advance" && ${OUTCOME} == "pr-created" ]]; then
        echo "::error::Direct push to ${PUSH_BRANCH} blocked and state PR fallback refused: advance mode with pr-created outcome. Use state_write_mode=pending for L2 open_pr."
        exit 1
    fi

    open_state_pr_fallback
}

#######################################
# open_state_pr_fallback: Open auto-merge state PR when direct push is blocked
#
# Globals:
#   READ_BRANCH - PR base branch
#   SHA - Cursor SHA for PR body
#   OUTCOME - Outcome for PR body
#   GH_TOKEN - GitHub token
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 when state branch push fails
#
#######################################
function open_state_pr_fallback {
    local state_branch pr_url

    echo "Direct push blocked; opening state PR."
    state_branch="loop/state-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-$(openssl rand -hex 4)"
    git checkout -B "${state_branch}"
    if ! git push origin "${state_branch}"; then
        echo "::error::Failed to push state branch ${state_branch}"
        exit 1
    fi
    pr_url=$(gh pr create \
        --repo "${GITHUB_REPOSITORY}" \
        --base "${READ_BRANCH}" \
        --head "${state_branch}" \
        --title "chore(loop): update state [skip ci]" \
        --body "Automated loop state update (mode: ${STATE_WRITE_MODE}, outcome: ${OUTCOME}, sha: ${SHA}).")
    if gh pr merge "${pr_url}" --auto --delete-branch --squash 2> /dev/null; then
        echo "State PR queued for auto-merge: ${pr_url}"
    elif gh pr merge "${pr_url}" --delete-branch --squash 2> /dev/null; then
        echo "State PR merged: ${pr_url}"
    else
        echo "::warning::State PR requires manual merge: ${pr_url}"
    fi
}

#######################################
# configure_git_auth: Configure git identity and GitHub auth header
#
# Globals:
#   GH_TOKEN - GitHub token for push and gh CLI
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function configure_git_auth {
    : "${GH_TOKEN:?}"

    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GH_TOKEN}" | base64 -w0)"
}

#######################################
# load_state_tmp: Fetch branches and load state JSON into STATE_TMP
#
# Globals:
#   STATE_TMP - Set to temp file path with loaded JSON
#   READ_BRANCH - Branch used to read existing state
#   PUSH_BRANCH - Branch used for checkout before commit
#   STATE_FILE - State file path
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function load_state_tmp {
    STATE_TMP="$(mktemp)"
    trap 'rm -f "${STATE_TMP}"' EXIT

    git fetch origin "${READ_BRANCH}" --prune

    if git show "origin/${READ_BRANCH}:${STATE_FILE}" > "${STATE_TMP}" 2> /dev/null; then
        :
    elif [[ -f ${STATE_FILE} ]]; then
        cp "${STATE_FILE}" "${STATE_TMP}"
    else
        echo '{"targets":{}}' > "${STATE_TMP}"
    fi

    if ! jq -e '.targets' "${STATE_TMP}" > /dev/null 2>&1; then
        echo '{"targets":{}}' > "${STATE_TMP}"
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/${PUSH_BRANCH}"; then
        git checkout -B "${PUSH_BRANCH}" "origin/${PUSH_BRANCH}"
    else
        git checkout -B "${PUSH_BRANCH}" "origin/${READ_BRANCH}" 2> /dev/null || git checkout -B "${PUSH_BRANCH}"
    fi
}

#######################################
# resolve_consecutive_failures: Compute consecutive_failures for outcome
#
# Globals:
#   TARGET_KEY - Target key in state file
#   STATE_TMP - Current state JSON temp file
#   OUTCOME - Run outcome
#   OPEN_REJECTIONS - JSON array; may be reset
#
# Arguments:
#   None
#
# Outputs:
#   Consecutive failure count on stdout
#
# Returns:
#   0 on success
#
#######################################
function resolve_consecutive_failures {
    local prev_consecutive

    prev_consecutive="$(jq -r --arg key "${TARGET_KEY}" '.targets[$key].consecutive_failures // 0' "${STATE_TMP}" 2> /dev/null || echo "0")"
    if ! jq -e . <<< "${OPEN_REJECTIONS}" > /dev/null 2>&1; then
        echo "::warning::open_rejections is not valid JSON; using []"
        OPEN_REJECTIONS='[]'
    fi

    case "${OUTCOME}" in
        rejected | pr-closed)
            echo $((prev_consecutive + 1))
            ;;
        watch | error | escalated)
            if [[ ${OUTCOME} != "watch" ]]; then
                OPEN_REJECTIONS='[]'
            fi
            echo "${prev_consecutive}"
            ;;
        *)
            OPEN_REJECTIONS='[]'
            echo "0"
            ;;
    esac
}

#######################################
# validate_branches: Validate read and push branch names
#
# Globals:
#   READ_BRANCH - Set before call in main
#   PUSH_BRANCH - Set before call in main
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 on invalid branch name
#
#######################################
function validate_branches {
    if ! [[ ${READ_BRANCH} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::Invalid state read branch: ${READ_BRANCH}"
        exit 1
    fi
    if ! [[ ${PUSH_BRANCH} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::Invalid state push branch: ${PUSH_BRANCH}"
        exit 1
    fi
}

#######################################
# validate_required_inputs: Validate required env for target state writes
#
# Globals:
#   TARGET_KEY - Required target key
#   WRITE_TARGET_STATE - When true, outcome and mode-specific fields are required
#   OUTCOME - Run outcome
#   SHA - Cursor SHA
#   STATE_WRITE_MODE - advance|pending|metadata|promote|clear_pending
#   PENDING_PR_NUMBER - Required for pending/promote/clear_pending
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 when required input is missing
#
#######################################
function validate_required_inputs {
    if [[ -z ${TARGET_KEY} ]]; then
        echo "::error::target_key is required for loop-state-write"
        exit 1
    fi

    if [[ ${WRITE_TARGET_STATE} != "true" ]]; then
        return 0
    fi

    if [[ -z ${OUTCOME} ]]; then
        echo "::error::outcome is required when write_target_state=true"
        exit 1
    fi
    if [[ ${STATE_WRITE_MODE} != "promote" && ${STATE_WRITE_MODE} != "clear_pending" && -z ${SHA} ]]; then
        echo "::error::sha is required when state_write_mode=${STATE_WRITE_MODE}"
        exit 1
    fi
    if [[ ${STATE_WRITE_MODE} == "pending" && -z ${PENDING_PR_NUMBER} ]]; then
        echo "::error::pending_pr_number is required when state_write_mode=pending"
        exit 1
    fi
    if [[ ${STATE_WRITE_MODE} == "promote" || ${STATE_WRITE_MODE} == "clear_pending" ]]; then
        if [[ -z ${PENDING_PR_NUMBER} ]]; then
            echo "::error::pending_pr_number is required when state_write_mode=${STATE_WRITE_MODE}"
            exit 1
        fi
    fi
}

#######################################
# apply_state_patch: Apply a fixed-mode target update and atomically rewrite STATE_TMP
#
# Globals:
#   STATE_TMP - State JSON temp file
#   TARGET_KEY - Target key
#   OUTCOME - Run outcome
#   REJECT_REASON - Optional rejection reason
#   OPEN_REJECTIONS - JSON array
#   SHA - Cursor SHA (advance/pending)
#   PENDING_PR_NUMBER - Pending PR number (clear_pending/pending/promote)
#   PENDING_PR_URL - Pending PR URL (pending)
#   LOOP_NAME - Loop name (pending)
#
# Arguments:
#   $1 - ISO timestamp
#   $2 - consecutive_failures value
#   $3 - Mode: advance|clear_pending|metadata|pending|promote
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 on invalid mode
#
#######################################
function apply_state_patch {
    local now="$1"
    local consecutive="$2"
    local mode="$3"

    case "${mode}" in
        advance | clear_pending | metadata | pending | promote) ;;
        *)
            echo "::error::Invalid apply_state_patch mode: ${mode}"
            exit 1
            ;;
    esac

    # shellcheck disable=SC2016  # jq filter; $vars are bound via --arg/--argjson below
    jq \
        --arg mode "${mode}" \
        --arg key "${TARGET_KEY}" \
        --arg last_run "${now}" \
        --arg outcome "${OUTCOME}" \
        --arg last_reject_reason "${REJECT_REASON}" \
        --arg sha "${SHA:-}" \
        --arg pending_pr "${PENDING_PR_NUMBER:-0}" \
        --arg pending_pr_url "${PENDING_PR_URL:-}" \
        --arg loop_name "${LOOP_NAME:-}" \
        --arg created_at "${now}" \
        --argjson pr "${PENDING_PR_NUMBER:--1}" \
        --argjson consecutive_failures "${consecutive}" \
        --argjson open_rejections "${OPEN_REJECTIONS}" \
        '
        .targets = (.targets // {}) |
        .targets[$key] = (
          (.targets[$key] // {})
          | if $mode == "advance" then
              .last_sha = $sha | del(.pending)
            elif $mode == "clear_pending" then
              if (.pending.pr // -1) != $pr then . else del(.pending) end
            elif $mode == "pending" then
              .pending = {
                sha: $sha,
                pr: ($pending_pr | tonumber),
                pr_url: (if $pending_pr_url != "" then $pending_pr_url else null end),
                loop_name: (if $loop_name != "" then $loop_name else null end),
                created_at: $created_at
              }
            elif $mode == "promote" then
              if (.pending.pr // -1) != $pr then . else .last_sha = .pending.sha | del(.pending) end
            else
              .
            end
          | .last_run = $last_run
          | .outcome = $outcome
          | .consecutive_failures = $consecutive_failures
          | .open_rejections = $open_rejections
          | if $last_reject_reason != "" then .last_reject_reason = $last_reject_reason else . end
        )
        ' "${STATE_TMP}" > "${STATE_TMP}.next"
    mv "${STATE_TMP}.next" "${STATE_TMP}"
}

#######################################
# write_state_advance: Set last_sha and clear pending
#
# Globals:
#   STATE_TMP - State JSON temp file
#   TARGET_KEY - Target key
#   SHA - Cursor SHA
#   OUTCOME - Run outcome
#   REJECT_REASON - Optional rejection reason
#   OPEN_REJECTIONS - JSON array
#
# Arguments:
#   $1 - ISO timestamp
#   $2 - consecutive_failures value
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function write_state_advance {
    local now="$1"
    local consecutive="$2"

    apply_state_patch "${now}" "${consecutive}" "advance"
}

#######################################
# write_state_clear_pending: Clear pending without advancing last_sha
#
# Globals:
#   STATE_TMP - State JSON temp file
#   TARGET_KEY - Target key
#   PENDING_PR_NUMBER - Pending PR number that must match
#
# Arguments:
#   $1 - ISO timestamp
#   $2 - consecutive_failures value
#
# Outputs:
#   Skip message to stdout when pending PR does not match
#
# Returns:
#   Exits 0 when no matching pending entry exists
#
#######################################
function write_state_clear_pending {
    local now="$1"
    local consecutive="$2"

    if ! jq -e --arg key "${TARGET_KEY}" --argjson pr "${PENDING_PR_NUMBER}" \
        '.targets[$key].pending.pr == $pr' "${STATE_TMP}" > /dev/null 2>&1; then
        echo "No matching pending entry for ${TARGET_KEY} PR #${PENDING_PR_NUMBER}; skipping clear."
        exit 0
    fi
    apply_state_patch "${now}" "${consecutive}" "clear_pending"
}

#######################################
# write_state_metadata: Update outcome metadata without changing last_sha
#
# Globals:
#   None beyond apply_state_patch
#
# Arguments:
#   $1 - ISO timestamp
#   $2 - consecutive_failures value
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function write_state_metadata {
    local now="$1"
    local consecutive="$2"

    apply_state_patch "${now}" "${consecutive}" "metadata"
}

#######################################
# write_state_pending: Record pending cursor without advancing last_sha
#
# Globals:
#   SHA, PENDING_PR_NUMBER, PENDING_PR_URL, LOOP_NAME
#
# Arguments:
#   $1 - ISO timestamp
#   $2 - consecutive_failures value
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function write_state_pending {
    local now="$1"
    local consecutive="$2"

    apply_state_patch "${now}" "${consecutive}" "pending"
}

#######################################
# write_state_promote: Promote pending.sha to last_sha
#
# Globals:
#   STATE_TMP - State JSON temp file
#   TARGET_KEY - Target key
#   PENDING_PR_NUMBER - Pending PR number that must match
#
# Arguments:
#   $1 - ISO timestamp
#   $2 - consecutive_failures value
#
# Outputs:
#   Skip message to stdout when pending PR does not match
#
# Returns:
#   Exits 0 when no matching pending entry exists
#
#######################################
function write_state_promote {
    local now="$1"
    local consecutive="$2"

    if ! jq -e --arg key "${TARGET_KEY}" --argjson pr "${PENDING_PR_NUMBER}" \
        '.targets[$key].pending.pr == $pr' "${STATE_TMP}" > /dev/null 2>&1; then
        echo "No matching pending entry for ${TARGET_KEY} PR #${PENDING_PR_NUMBER}; skipping promote."
        exit 0
    fi
    apply_state_patch "${now}" "${consecutive}" "promote"
}

# write_target_state: Dispatch state write by state_write_mode
#
# Globals:
#   STATE_WRITE_MODE - advance|pending|metadata|promote|clear_pending
#
# Arguments:
#   $1 - ISO timestamp
#   $2 - consecutive_failures value
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 on invalid state_write_mode
#
#######################################
function write_target_state {
    local now="$1"
    local consecutive="$2"

    case "${STATE_WRITE_MODE}" in
        advance)
            write_state_advance "${now}" "${consecutive}"
            ;;
        pending)
            write_state_pending "${now}" "${consecutive}"
            ;;
        metadata)
            write_state_metadata "${now}" "${consecutive}"
            ;;
        promote)
            write_state_promote "${now}" "${consecutive}"
            ;;
        clear_pending)
            write_state_clear_pending "${now}" "${consecutive}"
            ;;
        *)
            echo "::error::Invalid state_write_mode: ${STATE_WRITE_MODE}"
            exit 1
            ;;
    esac
}

#######################################
# main: Write loop state and push to branch_state
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits with script status
#
#######################################
function main {
    local now consecutive

    : "${STATE_FILE:?}"

    configure_git_auth

    READ_BRANCH="${STATE_PUSH_BRANCH:-${BASE_BRANCH}}"
    PUSH_BRANCH="${READ_BRANCH}"

    validate_branches
    validate_required_inputs

    load_state_tmp
    prune_targets_by_retention "${STATE_TMP}"
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    if [[ ${WRITE_TARGET_STATE} == "true" ]]; then
        consecutive="$(resolve_consecutive_failures)"
        write_target_state "${now}" "${consecutive}"
    fi

    commit_and_push_state
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
