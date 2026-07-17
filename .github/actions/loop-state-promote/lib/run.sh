#!/bin/bash
#######################################
# Description:
#   Promote or clear pending loop state entries after a fix PR closes.
#   Updates .loop/state-*.json only on the state push branch (explicit
#   STATE_PUSH_BRANCH, or the repository default branch when unset).
#
# Usage:
#   GH_TOKEN=... PR_NUMBER=... MERGED=true|false bash lib/run.sh
#
# Design Rules:
#   - Merged PRs promote pending.sha to last_sha
#   - Closed-without-merge PRs clear pending only
#   - Never push state commits onto fix-PR heads (avoids [skip ci] pollution)
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
STATE_PUSH_BRANCH="${STATE_PUSH_BRANCH:-}"
OUTCOME=""
WRITE_MODE=""

#######################################
# apply_pending_update: Apply promote or clear_pending jq transform for one target
#
# Arguments:
#   $1 - State temp file path
#   $2 - Target key
#   $3 - ISO timestamp
#   $4 - Outcome string (merged|pr-closed)
#   $5 - Write mode (promote|clear_pending)
#
# Global Variables:
#   PR_NUMBER - Pull request number to match
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
# Arguments:
#   $1 - State push branch
#   $@ - Changed state file paths
#
# Global Variables:
#   PR_NUMBER - Pull request number for commit message
#   WRITE_MODE - promote|clear_pending
#
# Returns:
#   Exits 0 when there is nothing to push
#
#######################################
function commit_changed_state_files {
    local push_branch="$1"
    shift
    local -a changed_files=("$@")

    git add "${changed_files[@]}"
    if git diff --cached --quiet; then
        echo "No state diff to push."
        return 0
    fi

    git commit -m "chore(loop): ${WRITE_MODE} state for PR #${PR_NUMBER} [skip ci]"
    git push origin HEAD:"${push_branch}"
    echo "State ${WRITE_MODE} pushed to ${push_branch} for PR #${PR_NUMBER}."
}

#######################################
# configure_git_auth: Configure git identity and GitHub auth header
#
# Arguments:
#   None
#
# Global Variables:
#   GH_TOKEN - GitHub token
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
# list_state_files: List loop state JSON paths on a branch
#
# Arguments:
#   $1 - Branch name
#
# Global Variables:
#   None
#
# Returns:
#   Newline-separated state file paths on stdout
#
#######################################
function list_state_files {
    local branch="$1"

    git ls-tree -r --name-only "origin/${branch}" -- .loop 2> /dev/null \
        | grep -E '^\.loop/state-[^/]+\.json$' || true
}

#######################################
# validate_state_push_branch: Validate resolved state push branch name
#
# Arguments:
#   None
#
# Global Variables:
#   STATE_PUSH_BRANCH - Branch name set in main before call
#
# Returns:
#   Exits 1 on invalid branch name
#
#######################################
function validate_state_push_branch {
    if ! [[ ${STATE_PUSH_BRANCH} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::Invalid state push branch: ${STATE_PUSH_BRANCH}"
        exit 1
    fi
}

#######################################
# discover_state_push_branches: Resolve the single branch that hosts loop state
#
# Arguments:
#   $1 - Pull request number (unused; kept for call-site compatibility)
#
# Global Variables:
#   STATE_PUSH_BRANCH - Optional explicit branch override
#   GITHUB_REPOSITORY - Repository slug for default-branch lookup
#
# Returns:
#   One branch name on stdout (explicit override or repository default)
#
#######################################
function discover_state_push_branches {
    local _pr="${1:-}"

    if [[ -n ${STATE_PUSH_BRANCH} ]]; then
        printf '%s\n' "${STATE_PUSH_BRANCH}"
        return 0
    fi

    : "${GITHUB_REPOSITORY:?}"
    STATE_PUSH_BRANCH="$(gh repo view "${GITHUB_REPOSITORY}" --json defaultBranchRef --jq '.defaultBranchRef.name')"
    printf '%s\n' "${STATE_PUSH_BRANCH}"
}

#######################################
# process_state_push_branch: Promote or clear pending state on one branch
#
# Arguments:
#   $1 - Branch name
#
# Global Variables:
#   PR_NUMBER - Closed pull request number
#   MERGED - Whether the pull request merged
#   OUTCOME - Set from MERGED flag
#   WRITE_MODE - promote|clear_pending
#
# Returns:
#   Exits 0 when there is nothing to push on this branch
#
#######################################
function process_state_push_branch {
    local push_branch="$1"
    local -a changed_files=()
    local -a state_files=()
    local -a target_keys=()
    local now state_file state_tmp target_key

    STATE_PUSH_BRANCH="${push_branch}"
    validate_state_push_branch

    git fetch origin "${STATE_PUSH_BRANCH}" --prune
    git checkout -B "${STATE_PUSH_BRANCH}" "origin/${STATE_PUSH_BRANCH}"

    mapfile -t state_files < <(list_state_files "${STATE_PUSH_BRANCH}")
    if [[ ${#state_files[@]} -eq 0 ]]; then
        echo "No loop state files found on ${STATE_PUSH_BRANCH}."
        return 0
    fi

    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    for state_file in "${state_files[@]}"; do
        if ! git cat-file -e "origin/${STATE_PUSH_BRANCH}:${state_file}" 2> /dev/null; then
            continue
        fi

        mapfile -t target_keys < <(
            git show "origin/${STATE_PUSH_BRANCH}:${state_file}" \
                | jq -r --argjson pr "${PR_NUMBER}" '.targets // {} | to_entries[] | select(.value.pending.pr == $pr) | .key'
        )
        if [[ ${#target_keys[@]} -eq 0 ]]; then
            continue
        fi

        state_tmp="$(mktemp)"
        git show "origin/${STATE_PUSH_BRANCH}:${state_file}" > "${state_tmp}"
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
        echo "No pending state matched PR #${PR_NUMBER} on ${STATE_PUSH_BRANCH}."
        return 0
    fi

    commit_changed_state_files "${STATE_PUSH_BRANCH}" "${changed_files[@]}"
}

#######################################
# main: Promote or clear pending state for a closed pull request
#
# Arguments:
#   None
#
# Global Variables:
#   MERGED - Whether the pull request merged
#   PR_NUMBER - Closed pull request number
#   STATE_PUSH_BRANCH - Optional branch override for .loop/* state files
#   OUTCOME - Set from MERGED flag
#   WRITE_MODE - promote|clear_pending
#
# Returns:
#   Exits with script status
#
#######################################
function main {
    local -a push_branches=()
    local push_branch

    configure_git_auth

    mapfile -t push_branches < <(discover_state_push_branches "${PR_NUMBER}")
    if [[ ${#push_branches[@]} -eq 0 ]]; then
        echo "No state push branch resolved for PR #${PR_NUMBER}."
        return 0
    fi

    if [[ ${MERGED} == "true" ]]; then
        OUTCOME="merged"
        WRITE_MODE="promote"
    else
        OUTCOME="pr-closed"
        WRITE_MODE="clear_pending"
    fi

    for push_branch in "${push_branches[@]}"; do
        process_state_push_branch "${push_branch}"
    done
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
