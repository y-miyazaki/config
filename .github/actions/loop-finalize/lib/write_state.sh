#!/bin/bash
#######################################
# Description:
#   Write loop state JSON and commit/push to STATE_BRANCH.
#   Environment variables mirror loop-finalize Write State step env vars.
#
# Usage:
#   GITHUB_TOKEN=<token> STATE_BRANCH=main STATE_FILE=... TARGET_KEY=... bash lib/write_state.sh
#
# Design Rules:
#   - state_write_mode controls whether last_sha, pending, or metadata is updated
#   - STATE_BRANCH is required (no default branch fallback)
#   - Prefer direct push to STATE_BRANCH; open auto-merge state PR when push is blocked
#   - PR fallback is refused for advance + pr_pushed (delivery pr_push landed on the
#     PR head; pr_create records pending instead of advance)
#   - Persisted and passed outcomes are read through outcome_normalize (old names)
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
# shellcheck source=../../lib/loop/outcome.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/outcome.sh"
# shellcheck source=../../lib/loop/push_race.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/push_race.sh"
# shellcheck source=../../lib/loop/check_names.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/check_names.sh"
# shellcheck source=../../lib/loop/git_auth.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/git_auth.sh"
# shellcheck source=../../lib/loop/state_pr.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/state_pr.sh"

#######################################
# Global variables
#######################################
REJECT_REASON="${REJECT_REASON:-}"
OPEN_REJECTIONS="${OPEN_REJECTIONS:-[]}"
WRITE_TARGET_STATE="${WRITE_TARGET_STATE:-true}"
FINALIZE_COMMIT_PATHS="${FINALIZE_COMMIT_PATHS:-}"
STATE_BRANCH="${STATE_BRANCH:-}"
TARGET_KEY="${TARGET_KEY:-}"
OUTCOME="${OUTCOME:-}"
SHA="${SHA:-}"
STATE_WRITE_MODE="${STATE_WRITE_MODE:-advance}"
PENDING_PR_NUMBER="${PENDING_PR_NUMBER:-}"
PENDING_PR_URL="${PENDING_PR_URL:-}"
LOOP_NAME="${LOOP_NAME:-}"
STATE_PR_SKIP="${STATE_PR_SKIP:-false}"
# Max retries of a push rejected by a concurrent state write (fetch first / non-fast-forward)
WRITE_STATE_MAX_RETRIES="${WRITE_STATE_MAX_RETRIES:-3}"

READ_BRANCH=""
PUSH_BRANCH=""
STATE_TMP=""
# Extra repo-relative paths committed with the state file (from FINALIZE_COMMIT_PATHS)
STATE_EXTRA_PATHS=()

#######################################
# validate_finalize_commit_path: Reject unsafe finalize commit paths
#
# Globals:
#   None
#
# Arguments:
#   $1 - Repo-relative path candidate
#
# Outputs:
#   Error annotation on stderr when invalid
#
# Returns:
#   0 when valid, 1 otherwise
#
#######################################
function validate_finalize_commit_path {
    local path="$1"

    if [[ ${path} == *".."* ]]; then
        echo "::error::finalize_commit_paths must not contain '..': ${path}" >&2
        return 1
    fi
    if [[ ${path} == /* ]]; then
        echo "::error::finalize_commit_paths must be repo-relative: ${path}" >&2
        return 1
    fi
    if [[ ${path} =~ [[:space:]] ]]; then
        echo "::error::finalize_commit_paths must not contain whitespace: ${path}" >&2
        return 1
    fi
    return 0
}

#######################################
# commit_and_push_state: Commit state paths and push or open fallback PR
#
# Globals:
#   STATE_FILE - Path to state JSON
#   STATE_TMP - Prepared state content
#   PUSH_BRANCH - Git push destination branch
#   READ_BRANCH - STATE_BRANCH for direct push
#   STATE_PR_SKIP - When true, skip PR fallback on push failure
#   STATE_WRITE_MODE - advance|pending|metadata|promote|clear_pending
#   FINALIZE_COMMIT_PATHS - Optional comma-separated extra paths committed with the state file
#   STATE_EXTRA_PATHS - Set from FINALIZE_COMMIT_PATHS; carried across a push retry, merged when a rival changed a JSON object file
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
    local item has_changes path push_err

    mkdir -p "$(dirname "${STATE_FILE}")"
    cp "${STATE_TMP}" "${STATE_FILE}"

    if [[ -n ${FINALIZE_COMMIT_PATHS} ]]; then
        declare -a extra=()
        IFS=',' read -r -a extra <<< "${FINALIZE_COMMIT_PATHS}"
        for item in "${extra[@]}"; do
            item="${item#"${item%%[![:space:]]*}"}"
            item="${item%"${item##*[![:space:]]}"}"
            [[ -z ${item} ]] && continue
            if ! validate_finalize_commit_path "${item}"; then
                return 1
            fi
            paths_to_add+=("${item}")
            STATE_EXTRA_PATHS+=("${item}")
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
    if push_err="$(git push origin HEAD:"${PUSH_BRANCH}" 2>&1)"; then
        echo "State pushed to ${PUSH_BRANCH}."
        return 0
    fi
    echo "${push_err}" >&2

    if push_race_is_error "${push_err}"; then
        if retry_state_write; then
            return 0
        fi
    fi

    if [[ ${STATE_PR_SKIP} == "true" ]]; then
        echo "::warning::Direct push blocked; skipping state PR (state_pr_skip=true)."
        return 0
    fi

    # The state-only PR is not the landed path. Advance mode is reached only by
    # delivery pr_push, whose outcome is pr_pushed. pr_create writes pending mode, so
    # keying this refusal on pr_created would never match and silently disable it.
    if [[ ${STATE_WRITE_MODE} == "advance" && $(outcome_normalize "${OUTCOME}") == "pr_pushed" ]]; then
        echo "::error::Direct push to ${PUSH_BRANCH} blocked and state PR fallback refused: advance mode with pr_pushed outcome. Allow direct push to state_branch (ruleset bypass) for delivery pr_push."
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
#   GITHUB_TOKEN - GitHub token
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
    echo "Direct push blocked; opening state PR."
    loop_open_state_pr "${READ_BRANCH}" "loop/state" \
        "chore(loop): update state [skip ci]" \
        "Automated loop state update (mode: ${STATE_WRITE_MODE}, outcome: ${OUTCOME}, sha: ${SHA})." \
        "State PR"
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
# prepare_open_rejections: Validate OPEN_REJECTIONS and clear it when the outcome ends the rejection chain
#
# Description:
#   Must be called directly, never inside a command substitution: it assigns OPEN_REJECTIONS,
#   and a subshell would drop the assignment (stale rejections persisted, or invalid JSON
#   reaching jq --argjson and aborting the state write).
#
# Globals:
#   OPEN_REJECTIONS - JSON array; reset to [] when invalid or when the outcome is not a rejection
#   OUTCOME - Run outcome
#
# Arguments:
#   None
#
# Outputs:
#   STDERR: warning when open_rejections is not valid JSON
#
# Returns:
#   0 on success
#
#######################################
function prepare_open_rejections {
    local effect

    if ! jq -e . <<< "${OPEN_REJECTIONS}" > /dev/null 2>&1; then
        echo "::warning::open_rejections is not valid JSON; using []" >&2
        OPEN_REJECTIONS='[]'
    fi

    effect="$(outcome_counter_effect "${OUTCOME}")"
    if [[ ${effect} == "reset" || (${effect} == "keep" && ${OUTCOME} != "watch") ]]; then
        OPEN_REJECTIONS='[]'
    fi
}

#######################################
# resolve_consecutive_failures: Compute consecutive_failures for outcome
#
# Globals:
#   TARGET_KEY - Target key in state file
#   STATE_TMP - Current state JSON temp file
#   OUTCOME - Run outcome
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

    case "$(outcome_counter_effect "${OUTCOME}")" in
        increment) echo $((prev_consecutive + 1)) ;;
        keep) echo "${prev_consecutive}" ;;
        *) echo "0" ;;
    esac
}

#######################################
# resolve_consecutive_with_probe: Compute consecutive_failures after the retention prune
#
# Description:
#   The prune cooldown resets an aged terminal target to 0. A rejected or pr_closed
#   run on a target that was already at 3 or more is the probe detect lets through once
#   its circuit breaker is 30 days old: it must keep counting from the stored value so
#   the breaker reopens (3 to 4), not restart at 1. Every other case uses the value
#   computed after the prune, so the cooldown still resets error, watch and approved
#   runs and targets below the trip point.
#
# Globals:
#   OUTCOME - Run outcome (read)
#   STATE_TMP - Pruned state JSON temp file (read)
#   TARGET_KEY - Target key in state file (read)
#
# Arguments:
#   $1 - Count resolved before the prune (rejected and pr_closed give stored + 1)
#
# Outputs:
#   Consecutive failure count on stdout
#
# Returns:
#   0 on success
#
#######################################
function resolve_consecutive_with_probe {
    local pre_prune="$1"

    if [[ $(outcome_counter_effect "${OUTCOME}") == "increment" ]]; then
        if [[ ${pre_prune} =~ ^[0-9]+$ && ${pre_prune} -ge 4 ]]; then
            echo "${pre_prune}"
            return 0
        fi
    fi
    resolve_consecutive_failures
}

#######################################
# carry_extra_paths_begin: Save the extra paths of the local state commit before a retry reset
#
# Description:
#   An extra path that is unchanged on the remote since the local commit's parent is carried as is.
#   One that a rival changed is carried only as a merge: both versions must be JSON objects, and
#   objects merge key by key (a ledger keyed by run ID or path). A key that both sides set to
#   different values, or a non-object file, is a conflict, because overwriting either side would
#   lose a ledger entry.
#
# Globals:
#   STATE_EXTRA_PATHS - Extra repo-relative paths committed with the state file
#   PUSH_BRANCH - Remote branch the retry resets to
#
# Arguments:
#   $1 - Directory that receives one saved copy per extra path
#
# Outputs:
#   Notice or warning on stdout
#
# Returns:
#   0 when every extra path is saved (as is, or merged with the remote version);
#   1 when a rival-changed path cannot be merged
#
#######################################
function carry_extra_paths_begin {
    local save_dir="$1"
    local path base_blob remote_blob index=0 remote_file merged

    for path in "${STATE_EXTRA_PATHS[@]}"; do
        base_blob="$(git rev-parse --verify --quiet "HEAD~1:${path}" 2> /dev/null || true)"
        remote_blob="$(git rev-parse --verify --quiet "origin/${PUSH_BRANCH}:${path}" 2> /dev/null || true)"
        if git cat-file -e "HEAD:${path}" 2> /dev/null; then
            git show "HEAD:${path}" > "${save_dir}/${index}"
        fi
        if [[ ${base_blob} != "${remote_blob}" ]]; then
            if [[ -z ${remote_blob} || ! -f "${save_dir}/${index}" ]]; then
                echo "::warning::${path} changed on ${PUSH_BRANCH} during the push race; not overwriting it."
                return 1
            fi
            remote_file="${save_dir}/${index}.remote"
            git show "origin/${PUSH_BRANCH}:${path}" > "${remote_file}"
            # shellcheck disable=SC2016  # jq program, not shell
            if ! merged="$(jq -s '
                def merge($a; $b):
                  if ($a | type) == "object" and ($b | type) == "object" then
                    reduce ($b | keys_unsorted[]) as $k ($a;
                      .[$k] = (if has($k) then merge(.[$k]; $b[$k]) else $b[$k] end))
                  elif $a == $b then $a
                  else error("conflict")
                  end;
                merge(.[0]; .[1])' "${remote_file}" "${save_dir}/${index}" 2> /dev/null)"; then
                echo "::warning::${path} changed on ${PUSH_BRANCH} during the push race and cannot be merged; not overwriting it."
                return 1
            fi
            printf '%s\n' "${merged}" > "${save_dir}/${index}"
            echo "Merged ${path} with the version pushed during the race."
        fi
        index=$((index + 1))
    done
}

#######################################
# carry_extra_paths_end: Restore saved extra paths and stage them after the retry reset
#
# Globals:
#   STATE_EXTRA_PATHS - Extra repo-relative paths committed with the state file
#
# Arguments:
#   $1 - Directory written by carry_extra_paths_begin
#
# Outputs:
#   None
#
# Returns:
#   0 always
#
#######################################
function carry_extra_paths_end {
    local save_dir="$1"
    local path index=0

    for path in "${STATE_EXTRA_PATHS[@]}"; do
        if [[ -f "${save_dir}/${index}" ]]; then
            mkdir -p "$(dirname "${path}")"
            cp "${save_dir}/${index}" "${path}"
            git add "${path}"
        fi
        index=$((index + 1))
    done
}

#######################################
# retry_state_write: Rebuild the state write on the latest remote and push again
#
# Globals:
#   WRITE_STATE_MAX_RETRIES - Max retries
#   READ_BRANCH - Branch fetched before each retry
#   PUSH_BRANCH - Branch reset to its remote tip and pushed
#   STATE_TMP - Replaced with a fresh temp file on each retry
#   STATE_FILE - State file path
#   WRITE_TARGET_STATE - When true, the target update is re-applied
#
# Arguments:
#   None
#
# Outputs:
#   Retry progress on stdout; git push stderr on stderr when a push fails
#
# Returns:
#   0 when pushed or nothing left to commit; 1 when retries are exhausted or the
#   push failed for a reason other than a race
#
#######################################
function retry_state_write {
    local attempt consecutive now push_err pre_prune_consecutive carry_dir=""

    if [[ ${#STATE_EXTRA_PATHS[@]} -gt 0 ]]; then
        carry_dir="$(mktemp -d)"
    fi
    for ((attempt = 1; attempt <= WRITE_STATE_MAX_RETRIES; attempt++)); do
        echo "Push race detected; retry ${attempt}/${WRITE_STATE_MAX_RETRIES}"
        git fetch origin "${READ_BRANCH}"
        if [[ -n ${carry_dir} ]] && ! carry_extra_paths_begin "${carry_dir}"; then
            rm -rf "${carry_dir}"
            return 1
        fi
        git reset --hard "origin/${PUSH_BRANCH}"
        rm -f "${STATE_TMP}" "${STATE_TMP}.next"
        load_state_tmp
        pre_prune_consecutive=""
        if [[ ${WRITE_TARGET_STATE} == "true" ]]; then
            prepare_open_rejections
            pre_prune_consecutive="$(resolve_consecutive_failures)"
        fi
        prune_targets_by_retention "${STATE_TMP}"
        now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        if [[ ${WRITE_TARGET_STATE} == "true" ]]; then
            consecutive="$(resolve_consecutive_with_probe "${pre_prune_consecutive}")"
            write_target_state "${now}" "${consecutive}"
        fi

        mkdir -p "$(dirname "${STATE_FILE}")"
        cp "${STATE_TMP}" "${STATE_FILE}"
        git add "${STATE_FILE}"
        if [[ -n ${carry_dir} ]]; then
            carry_extra_paths_end "${carry_dir}"
        fi
        if git diff --cached --quiet; then
            echo "No state changes to commit."
            [[ -z ${carry_dir} ]] || rm -rf "${carry_dir}"
            return 0
        fi
        git commit -m "chore(loop): update state [skip ci]"
        if push_err="$(git push origin HEAD:"${PUSH_BRANCH}" 2>&1)"; then
            echo "State pushed to ${PUSH_BRANCH}."
            [[ -z ${carry_dir} ]] || rm -rf "${carry_dir}"
            return 0
        fi
        echo "${push_err}" >&2
        if ! push_race_is_error "${push_err}"; then
            [[ -z ${carry_dir} ]] || rm -rf "${carry_dir}"
            return 1
        fi
    done
    [[ -z ${carry_dir} ]] || rm -rf "${carry_dir}"
    return 1
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
    if ! check_names_branch "${READ_BRANCH}"; then
        echo "::error::Invalid state read branch: ${READ_BRANCH}"
        exit 1
    fi
    if ! check_names_branch "${PUSH_BRANCH}"; then
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
        echo "::error::target_key is required for loop-finalize state write"
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
        return 0
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
        return 0
    fi
    apply_state_patch "${now}" "${consecutive}" "promote"
}

#######################################
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
# validate_state_file_path: Reject unsafe state file paths
#
# Globals:
#   STATE_FILE - State file path to validate
#
# Arguments:
#   None
#
# Outputs:
#   Error annotation on stderr when invalid
#
# Returns:
#   0 when valid, 1 otherwise
#
#######################################
function validate_state_file_path {
    if ! check_names_state_file "${STATE_FILE}"; then
        echo "::error::state_file must match .loop/state-<name>.json (no '..')" >&2
        return 1
    fi
    return 0
}

#######################################
# main: Write loop state and push to STATE_BRANCH
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
    local now consecutive pre_prune_consecutive

    : "${STATE_FILE:?}"

    validate_state_file_path || exit 1

    loop_git_configure_auth

    if [[ -z ${STATE_BRANCH} ]]; then
        echo "::error::state_branch is required"
        exit 1
    fi
    READ_BRANCH="${STATE_BRANCH}"
    PUSH_BRANCH="${READ_BRANCH}"

    validate_branches
    validate_required_inputs

    load_state_tmp
    # Count before pruning too: the 30-day cooldown in prune_targets resets an aged
    # terminal target to 0, which would erase the failures of the run detect let through
    # after the breaker cooldown (see resolve_consecutive_with_probe)
    pre_prune_consecutive=""
    if [[ ${WRITE_TARGET_STATE} == "true" ]]; then
        prepare_open_rejections
        pre_prune_consecutive="$(resolve_consecutive_failures)"
    fi
    prune_targets_by_retention "${STATE_TMP}"
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    if [[ ${WRITE_TARGET_STATE} == "true" ]]; then
        consecutive="$(resolve_consecutive_with_probe "${pre_prune_consecutive}")"
        write_target_state "${now}" "${consecutive}"
    fi

    commit_and_push_state
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
