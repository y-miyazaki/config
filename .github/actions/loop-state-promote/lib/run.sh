#!/bin/bash
#######################################
# Description:
#   Promote or clear pending loop state entries after a fix PR closes.
#   Updates .loop/state-*.json only on the state branch (STATE_BRANCH, required).
#
# Usage:
#   GITHUB_TOKEN=... PR_NUMBER=... MERGED=true|false STATE_BRANCH=... bash lib/run.sh
#
# Design Rules:
#   - Merged PRs promote pending.sha to last_sha
#   - Closed-without-merge PRs clear pending and add the pr_closed effect to consecutive_failures
#   - Never push state commits onto fix-PR heads (avoids [skip ci] pollution)
#   - Prefer direct push to branch_state; open auto-merge state PR when push is blocked
#   - A push that loses a race is replayed on the latest state (up to PROMOTE_MAX_RETRIES attempts)
#   - A close without merge counts as a failure through the outcome mapping table (lib/loop/outcome.sh)
#
# Output:
#   Commits updated state files to branch_state when matches exist
#
# Dependencies:
#   - bash, git, jq, gh
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
MERGED="${MERGED:-false}"
PR_NUMBER="${PR_NUMBER:?}"
STATE_BRANCH="${STATE_BRANCH:-}"
STATE_PR_SKIP="${STATE_PR_SKIP:-false}"
OUTCOME=""
WRITE_MODE=""
# Replays of the state update after a lost push race (the state PR fallback follows the last one)
PROMOTE_ATTEMPT=1
PROMOTE_MAX_RETRIES="${PROMOTE_MAX_RETRIES:-3}"
PUSH_RACE_RETRY_STATUS=75

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/loop/check_names.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/check_names.sh"
# shellcheck source=../../lib/loop/git_auth.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/git_auth.sh"
# shellcheck source=../../lib/loop/outcome.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/outcome.sh"
# shellcheck source=../../lib/loop/push_race.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/push_race.sh"
# shellcheck source=../../lib/loop/state_pr.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/state_pr.sh"

#######################################
# apply_pending_update: Apply promote or clear_pending jq transform for one target
#
# Globals:
#   PR_NUMBER - Pull request number to match
#
# Arguments:
#   $1 - State temp file path
#   $2 - Target key
#   $3 - ISO timestamp
#   $4 - Outcome string (pr_merged|pr_closed)
#   $5 - Write mode (promote|clear_pending)
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function apply_pending_update {
    local state_tmp="$1"
    local target_key="$2"
    local now="$3"
    local outcome="$4"
    local write_mode="$5"

    case "${write_mode}" in
        promote)
            jq \
                --arg key "${target_key}" \
                --argjson pr "${PR_NUMBER}" \
                --arg last_run "${now}" \
                --arg outcome "${outcome}" \
                '
                .targets = (.targets // {}) |
                .targets[$key] = (
                  (.targets[$key] // {})
                  | if (.pending.pr // -1) != $pr then . else
                      .last_sha = .pending.sha
                      | del(.pending)
                      | .last_run = $last_run
                      | .outcome = $outcome
                      | .consecutive_failures = 0
                      | .open_rejections = []
                    end
                )
                ' "${state_tmp}" > "${state_tmp}.next"
            ;;
        clear_pending)
            jq \
                --arg effect "$(outcome_counter_effect "${outcome}")" \
                --arg key "${target_key}" \
                --argjson pr "${PR_NUMBER}" \
                --arg last_run "${now}" \
                --arg outcome "${outcome}" \
                '
                .targets = (.targets // {}) |
                .targets[$key] = (
                  (.targets[$key] // {})
                  | if (.pending.pr // -1) != $pr then . else
                      del(.pending)
                      | .last_run = $last_run
                      | .outcome = $outcome
                      | .consecutive_failures = (
                          if $effect == "increment" then ((.consecutive_failures // 0) + 1)
                          elif $effect == "reset" then 0
                          else (.consecutive_failures // 0)
                          end
                        )
                    end
                )
                ' "${state_tmp}" > "${state_tmp}.next"
            ;;
    esac
    mv "${state_tmp}.next" "${state_tmp}"
}

#######################################
# commit_changed_state_files: Commit and push modified state files
#
# Globals:
#   PR_NUMBER - Pull request number for commit message
#   WRITE_MODE - promote|clear_pending
#   PROMOTE_ATTEMPT, PROMOTE_MAX_RETRIES - Replay counters
#   PUSH_RACE_RETRY_STATUS - Status returned when the caller should replay
#
# Arguments:
#   $1 - State push branch
#   $@ - Changed state file paths
#
# Outputs:
#   None
#
# Returns:
#   0 when pushed, skipped or handed to the state PR fallback; PUSH_RACE_RETRY_STATUS when the push
#   lost a race and attempts remain (the caller replays the update on the latest state)
#
#######################################
function commit_changed_state_files {
    local push_branch="$1"
    shift
    local -a changed_files=("$@")
    local push_err

    git add "${changed_files[@]}"
    if git diff --cached --quiet; then
        echo "No state diff to push."
        return 0
    fi

    git commit -m "chore(loop): ${WRITE_MODE} state for PR #${PR_NUMBER} [skip ci]"
    if push_err="$(git push origin HEAD:"${push_branch}" 2>&1)"; then
        echo "State ${WRITE_MODE} pushed to ${push_branch} for PR #${PR_NUMBER}."
        return 0
    fi
    echo "${push_err}" >&2

    # A push that lost a race is replayed: the caller fetches the latest state and applies
    # the update again, so a concurrent state write is never overwritten
    if push_race_is_error "${push_err}" && [[ ${PROMOTE_ATTEMPT} -lt ${PROMOTE_MAX_RETRIES} ]]; then
        return "${PUSH_RACE_RETRY_STATUS}"
    fi

    if [[ ${STATE_PR_SKIP} == "true" ]]; then
        echo "::warning::Direct push blocked; skipping state PR (state_pr_skip=true)."
        return 0
    fi

    open_state_pr_fallback "${push_branch}"
}

#######################################
# open_state_pr_fallback: Open auto-merge state PR when direct push is blocked
#
# Globals:
#   PR_NUMBER - Closed pull request number
#   WRITE_MODE - promote|clear_pending
#   GITHUB_TOKEN - GitHub token (used implicitly by gh)
#   GITHUB_REPOSITORY - owner/repo for gh pr create --repo
#   GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT - Uniquely name the state promote branch
#
# Arguments:
#   $1 - Base branch for the state PR
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 when state branch push fails
#
#######################################
function open_state_pr_fallback {
    local push_branch="$1"

    echo "Direct push blocked; opening state promote PR."
    loop_open_state_pr "${push_branch}" "loop/state-promote" \
        "chore(loop): ${WRITE_MODE} state for PR #${PR_NUMBER} [skip ci]" \
        "Automated loop state ${WRITE_MODE} after PR #${PR_NUMBER} closed." \
        "State promote PR"
}

#######################################
# list_state_files: List loop state JSON paths on a branch
#
# Globals:
#   None
#
# Arguments:
#   $1 - Branch name
#
# Outputs:
#   Newline-separated state file paths on stdout
#
# Returns:
#   0 on success
#
#######################################
function list_state_files {
    local branch="$1"

    local path
    while IFS= read -r path; do
        if check_names_state_file "${path}"; then
            printf '%s\n' "${path}"
        fi
    done < <(git ls-tree -r --name-only "origin/${branch}" -- .loop 2> /dev/null || true)
}

#######################################
# validate_state_push_branch: Validate resolved state push branch name
#
# Globals:
#   STATE_BRANCH - Branch name set before call
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
function validate_state_push_branch {
    if ! check_names_branch "${STATE_BRANCH}"; then
        echo "::error::Invalid state push branch: ${STATE_BRANCH}"
        exit 1
    fi
}

#######################################
# process_state_push_branch: Promote or clear pending state on one branch
#
# Globals:
#   PR_NUMBER - Closed pull request number
#   OUTCOME - Finalize outcome recorded on matching pending targets
#   WRITE_MODE - promote|clear_pending
#
# Arguments:
#   $1 - Branch name
#
# Outputs:
#   None
#
# Returns:
#   0 when there is nothing to push on this branch or the update landed; PUSH_RACE_RETRY_STATUS when
#   the push lost a race and attempts remain
#
#######################################
function process_state_push_branch {
    local push_branch="$1"
    local -a changed_files=()
    local -a state_files=()
    local -a target_keys=()
    local now state_file state_tmp target_key

    STATE_BRANCH="${push_branch}"
    validate_state_push_branch

    git fetch origin "${STATE_BRANCH}" --prune
    git checkout -B "${STATE_BRANCH}" "origin/${STATE_BRANCH}"

    mapfile -t state_files < <(list_state_files "${STATE_BRANCH}")
    if [[ ${#state_files[@]} -eq 0 ]]; then
        echo "No loop state files found on ${STATE_BRANCH}."
        return 0
    fi

    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    for state_file in "${state_files[@]}"; do
        if ! git cat-file -e "origin/${STATE_BRANCH}:${state_file}" 2> /dev/null; then
            continue
        fi

        mapfile -t target_keys < <(
            git show "origin/${STATE_BRANCH}:${state_file}" \
                | jq -r --argjson pr "${PR_NUMBER}" '.targets // {} | to_entries[] | select(.value.pending.pr == $pr) | .key'
        )
        if [[ ${#target_keys[@]} -eq 0 ]]; then
            continue
        fi

        state_tmp="$(mktemp)"
        git show "origin/${STATE_BRANCH}:${state_file}" > "${state_tmp}"
        for target_key in "${target_keys[@]}"; do
            apply_pending_update "${state_tmp}" "${target_key}" "${now}" "${OUTCOME}" "${WRITE_MODE}"
            echo "Updated ${state_file} target ${target_key} (${WRITE_MODE})."
        done

        mkdir -p "$(dirname "${state_file}")"
        cp "${state_tmp}" "${state_file}"
        rm -f "${state_tmp}"
        changed_files+=("${state_file}")
    done

    if [[ ${#changed_files[@]} -eq 0 ]]; then
        echo "No pending state matched PR #${PR_NUMBER} on ${STATE_BRANCH}."
        return 0
    fi

    commit_changed_state_files "${STATE_BRANCH}" "${changed_files[@]}"
}

#######################################
# main: Promote or clear pending state for a closed pull request
#
# Globals:
#   MERGED - Whether the pull request merged
#   PR_NUMBER - Closed pull request number
#   STATE_BRANCH - Required branch hosting .loop/* state files
#   OUTCOME - Set from MERGED flag
#   WRITE_MODE - promote|clear_pending
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
    : "${STATE_BRANCH:?STATE_BRANCH is required}"

    loop_git_configure_auth

    if [[ ${MERGED} == "true" ]]; then
        OUTCOME="pr_merged"
        WRITE_MODE="promote"
    else
        OUTCOME="pr_closed"
        WRITE_MODE="clear_pending"
    fi

    local rc
    for ((PROMOTE_ATTEMPT = 1; PROMOTE_ATTEMPT <= PROMOTE_MAX_RETRIES; PROMOTE_ATTEMPT++)); do
        rc=0
        process_state_push_branch "${STATE_BRANCH}" || rc=$?
        if [[ ${rc} -ne ${PUSH_RACE_RETRY_STATUS} ]]; then
            return "${rc}"
        fi
        echo "Push race detected; replaying state ${WRITE_MODE} (${PROMOTE_ATTEMPT}/${PROMOTE_MAX_RETRIES})"
    done
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
