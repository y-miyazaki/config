#!/bin/bash
#######################################
# Description: Multi-branch loop detection for loop-detect action
#
# Usage: bash lib/detect.sh
#
# Output:
# - Writes should_run, skip_reason, target_matrix to GITHUB_OUTPUT
#
# Design Rules:
# - Enumerates integration branches and optional PR heads
# - Invokes detect_script once per scan context (caller never re-runs)
# - Assembles target_matrix with prompt and verifier_context per cell
#
# Dependencies:
# - bash, git, jq, openssl
# - gh (when LOOP_PULL_REQUESTS=true)
#
# Optional environment:
#   DETECT_SCRIPT, STATE_FILE, LOOP_NAME, BASE_BRANCH, SKILL_NAME, LEVEL, ALLOWLIST
#   LOOP_INTEGRATION_BRANCHES, LOOP_PULL_REQUESTS, LOOP_BRANCH_MATCH, LOOP_PRIORITY
#   LOOP_FINALIZE_INTEGRATION, LOOP_FINALIZE_PULL_REQUEST, LOOP_MAX_TARGETS_PER_SCHEDULE
#   LOOP_PR_EXCLUDE, LOOP_PR_INCLUDE_BOTS, PROMPT_INSTRUCTIONS, BUDGET_FILE, RUN_LOG_FILE
#   GH_TOKEN / GITHUB_TOKEN
#######################################

set -euo pipefail
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_init.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_init.sh"

# Environment supplied by loop-detect composite action (validated in main).
BASE_BRANCH="${BASE_BRANCH-}"
DETECT_SCRIPT="${DETECT_SCRIPT-}"
STATE_FILE="${STATE_FILE-}"

#######################################
# append_integration_candidate: Scan one integration branch
#
# Arguments:
#   $1 - Branch name
#
# Global Variables:
#   CANDIDATES_JSON - Appended when actionable work is found
#   STATE_FILE, BASE_BRANCH, DETECT_SCRIPT, SKILL_NAME, LEVEL, ALLOWLIST
#   PROMPT_INSTRUCTIONS, LOOP_FINALIZE_INTEGRATION
#
# Returns:
#   None
#
#######################################
function append_integration_candidate {
    local branch="$1"
    local target_key="integration:${branch}"
    local target_state last_sha current_sha detect_result verifier_context prompt_text open_prompt consecutive
    local target_json candidate

    checkout_context "${branch}" || return 0

    target_state="$(read_target_state "${STATE_FILE}" "${target_key}" "${BASE_BRANCH}")"
    consecutive="$(target_consecutive_failures "${target_state}")"
    if target_circuit_breaker_open "${consecutive}"; then
        echo "::warning::Circuit breaker open for ${target_key}"
        CIRCUIT_BREAKER_BLOCKED=$((CIRCUIT_BREAKER_BLOCKED + 1))
        return 0
    fi

    last_sha="$(target_last_sha "${target_state}" "${branch}")"
    current_sha="$(git rev-parse HEAD)"
    export CI_SWEEPER_HEAD_BRANCH="${branch}"
    export DEFAULT_BASE_BRANCH="${BASE_BRANCH}"
    detect_result="$(bash "${DETECT_SCRIPT}" --scope range --since "${last_sha}")"

    if detect_result_skip "${detect_result}"; then
        return 0
    fi

    open_prompt="$(target_open_rejections_prompt "${target_state}")"
    verifier_context="$(build_verifier_context_from_result "${detect_result}")"
    prompt_text="$(build_prompt_text \
        "${SKILL_NAME}" "${LEVEL}" "${ALLOWLIST}" "${PROMPT_INSTRUCTIONS}" \
        "${last_sha}" "${current_sha}" "${detect_result}" "${open_prompt}" "${consecutive}")"

    target_json="$(jq -nc \
        --arg mode "integration" \
        --arg key "${target_key}" \
        --arg from_branch "${branch}" \
        --arg from_ref "${current_sha}" \
        --arg to_branch "${branch}" \
        --arg finalize "${LOOP_FINALIZE_INTEGRATION}" \
        '{
            mode: $mode,
            key: $key,
            from: {branch: $from_branch, ref: $from_ref},
            to: {branch: $to_branch},
            finalize: $finalize
        }')"
    target_json="$(enrich_target_json_with_ci_context "${target_json}" "${detect_result}")"

    candidate="$(jq -nc \
        --argjson target_json "${target_json}" \
        --arg prompt "${prompt_text}" \
        --arg verifier_context "${verifier_context}" \
        --argjson result "${detect_result}" \
        '{target_json: $target_json, prompt: $prompt, verifier_context: $verifier_context, result: $result}')"

    CANDIDATES_JSON+=("${candidate}")
}

#######################################
# append_pull_request_candidate: Scan one open pull request head
#
# Arguments:
#   $1 - PR JSON object
#
# Global Variables:
#   CANDIDATES_JSON - Appended when actionable work is found
#   STATE_FILE, BASE_BRANCH, DETECT_SCRIPT, SKILL_NAME, LEVEL, ALLOWLIST
#   PROMPT_INSTRUCTIONS, LOOP_FINALIZE_PULL_REQUEST
#
# Returns:
#   None
#
#######################################
function append_pull_request_candidate {
    local pr_json="$1"
    local pr_number head_branch head_ref base_branch target_key target_state last_sha current_sha
    local detect_result verifier_context prompt_text open_prompt consecutive candidate target_json

    pr_number=$(jq -r '.number' <<< "${pr_json}")
    head_branch=$(jq -r '.headRefName' <<< "${pr_json}")
    head_ref=$(jq -r '.headRefOid' <<< "${pr_json}")
    base_branch=$(jq -r '.baseRefName' <<< "${pr_json}")
    target_key="pull_request:${pr_number}"

    checkout_context "${head_branch}" "${head_ref}" || return 0

    target_state="$(read_target_state "${STATE_FILE}" "${target_key}" "${BASE_BRANCH}")"
    consecutive="$(target_consecutive_failures "${target_state}")"
    if target_circuit_breaker_open "${consecutive}"; then
        echo "::warning::Circuit breaker open for ${target_key}"
        CIRCUIT_BREAKER_BLOCKED=$((CIRCUIT_BREAKER_BLOCKED + 1))
        return 0
    fi

    last_sha="$(target_last_sha "${target_state}" "${head_branch}")"
    current_sha="$(git rev-parse HEAD)"
    export CI_SWEEPER_HEAD_BRANCH="${head_branch}"
    export DEFAULT_BASE_BRANCH="${BASE_BRANCH}"
    detect_result="$(bash "${DETECT_SCRIPT}" --scope range --since "${last_sha}")"

    if detect_result_skip "${detect_result}"; then
        return 0
    fi

    open_prompt="$(target_open_rejections_prompt "${target_state}")"
    verifier_context="$(build_verifier_context_from_result "${detect_result}")"
    prompt_text="$(build_prompt_text \
        "${SKILL_NAME}" "${LEVEL}" "${ALLOWLIST}" "${PROMPT_INSTRUCTIONS}" \
        "${last_sha}" "${current_sha}" "${detect_result}" "${open_prompt}" "${consecutive}")"

    target_json="$(jq -nc \
        --arg mode "pull_request" \
        --arg key "${target_key}" \
        --arg from_branch "${head_branch}" \
        --arg from_ref "${current_sha}" \
        --arg to_branch "${head_branch}" \
        --argjson pr_number "${pr_number}" \
        --arg base_branch "${base_branch}" \
        --arg finalize "${LOOP_FINALIZE_PULL_REQUEST}" \
        '{
            mode: $mode,
            key: $key,
            from: {branch: $from_branch, ref: $from_ref},
            to: {branch: $to_branch, pr_number: $pr_number},
            base: {branch: $base_branch},
            finalize: $finalize
        }')"
    target_json="$(enrich_target_json_with_ci_context "${target_json}" "${detect_result}")"

    candidate="$(jq -nc \
        --argjson target_json "${target_json}" \
        --arg prompt "${prompt_text}" \
        --arg verifier_context "${verifier_context}" \
        --argjson result "${detect_result}" \
        '{target_json: $target_json, prompt: $prompt, verifier_context: $verifier_context, result: $result}')"

    CANDIDATES_JSON+=("${candidate}")
}

#######################################
# apply_peer_active_filter: Drop candidates blocked by peer acting_on
#
# Arguments:
#   $1 - Current epoch seconds
#
# Global Variables:
#   CANDIDATES_JSON - Filtered in place
#   FILTERED_CANDIDATES_JSON - Scratch array
#
# Returns:
#   None
#
#######################################
function apply_peer_active_filter {
    local now_epoch="$1"
    local candidate target_key

    FILTERED_CANDIDATES_JSON=()
    for candidate in "${CANDIDATES_JSON[@]}"; do
        target_key=$(jq -r '.target_json.key' <<< "${candidate}")
        if acting_on_is_active "${target_key}" "${now_epoch}"; then
            echo "::warning::Peer loop active on ${target_key}"
            continue
        fi
        FILTERED_CANDIDATES_JSON+=("${candidate}")
    done
    CANDIDATES_JSON=("${FILTERED_CANDIDATES_JSON[@]}")
}

#######################################
# apply_target_cap: Cap candidates at LOOP_MAX_TARGETS_PER_SCHEDULE
#
# Arguments:
#   $1 - Maximum targets per schedule
#
# Global Variables:
#   CANDIDATES_JSON - Truncated in place when over cap
#
# Returns:
#   None
#
#######################################
function apply_target_cap {
    local max_targets="$1"
    local -a capped=()
    local i

    if [[ ${#CANDIDATES_JSON[@]} -le ${max_targets} ]]; then
        return 0
    fi

    for ((i = 0; i < max_targets; i++)); do
        capped+=("${CANDIDATES_JSON[$i]}")
    done
    CANDIDATES_JSON=("${capped[@]}")
}

#######################################
# checkout_context: Fetch and checkout branch at optional ref
#
# Arguments:
#   $1 - Branch name
#   $2 - Optional ref (default: origin/branch)
#
# Global Variables:
#   None
#
# Returns:
#   0 on success, 1 on invalid branch name
#
#######################################
function checkout_context {
    local branch="$1"
    local ref="${2:-}"

    if ! [[ ${branch} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::Invalid branch name: ${branch}"
        return 1
    fi

    git fetch origin "${branch}" --prune > /dev/null 2>&1 || true
    if [[ -n ${ref} ]]; then
        git checkout -q "${ref}" 2> /dev/null || git checkout -q -B "${branch}" "origin/${branch}" 2> /dev/null
    else
        git checkout -q -B "${branch}" "origin/${branch}" 2> /dev/null || git checkout -q "${branch}"
    fi
}

#######################################
# enrich_target_json_with_ci_context: Add CI failure fields to target_json
#
# Arguments:
#   $1 - Base target_json object string
#   $2 - Detect script JSON result
#
# Global Variables:
#   None
#
# Returns:
#   Enriched target_json on stdout
#
#######################################
function enrich_target_json_with_ci_context {
    local target_json="$1"
    local detect_result="$2"

    if ! jq -e '.failures[0]' <<< "${detect_result}" > /dev/null 2>&1; then
        printf '%s' "${target_json}"
        return 0
    fi

    jq -c \
        --argjson base "${target_json}" \
        --arg workflow_run_id "$(jq -r '.failures[0].workflow_run_id // empty' <<< "${detect_result}")" \
        --arg workflow_name "$(jq -r '.failures[0].workflow_name // empty' <<< "${detect_result}")" \
        --arg head_sha "$(jq -r '.failures[0].head_sha // empty' <<< "${detect_result}")" \
        '$base
        | if $workflow_run_id != "" then .workflow_run_id = $workflow_run_id else . end
        | if $workflow_name != "" then .workflow_name = $workflow_name else . end
        | if $head_sha != "" then .head_sha = $head_sha else . end'
}

#######################################
# detect_result_skip: Return 0 when detect script JSON indicates skip
#
# Arguments:
#   $1 - Detect script JSON result
#
# Global Variables:
#   None
#
# Returns:
#   0 when skip is true, 1 otherwise
#
#######################################
function detect_result_skip {
    local result="$1"
    local skip_val
    skip_val=$(echo "${result}" | jq -r 'if (.skip | type) == "boolean" then (.skip | tostring) else "true" end' 2> /dev/null || echo "true")
    [[ ${skip_val} == "true" ]]
}

#######################################
# validate_branch_match: Return 0 when LOOP_BRANCH_MATCH is valid
#
# Arguments:
#   None
#
# Global Variables:
#   LOOP_BRANCH_MATCH - Match mode under validation
#
# Returns:
#   0 when valid, 1 otherwise
#
#######################################
function validate_branch_match {
    case "${LOOP_BRANCH_MATCH}" in
        list | glob | regex) return 0 ;;
        *)
            echo "::error::Invalid LOOP_BRANCH_MATCH: ${LOOP_BRANCH_MATCH}"
            return 1
            ;;
    esac
}

#######################################
# write_legacy_outputs: Backward-compatible single-target outputs
#
# Arguments:
#   $1 - target_matrix JSON array string
#
# Global Variables:
#   GITHUB_OUTPUT, STATE_FILE, BASE_BRANCH
#
# Returns:
#   None
#
#######################################
function write_legacy_outputs {
    local target_matrix_json="$1"
    local first last_sha current_sha consecutive target_key target_state

    if [[ ${target_matrix_json} == "[]" ]]; then
        {
            echo "last_sha="
            echo "current_sha=$(git rev-parse HEAD 2> /dev/null || echo "")"
            echo "consecutive_failures=0"
            echo "prompt="
        } >> "${GITHUB_OUTPUT}"
        return 0
    fi

    first=$(jq -c '.[0]' <<< "${target_matrix_json}")
    last_sha=$(jq -r '.result.since // .result.commit_range // empty' <<< "${first}")
    current_sha=$(jq -r '.target_json.from.ref' <<< "${first}")
    target_key=$(jq -r '.target_json.key' <<< "${first}")
    target_state="$(read_target_state "${STATE_FILE}" "${target_key}" "${BASE_BRANCH}")"
    consecutive="$(target_consecutive_failures "${target_state}")"

    {
        echo "last_sha=${last_sha}"
        echo "current_sha=${current_sha}"
        echo "consecutive_failures=${consecutive}"
        local delim
        delim="PROMPT_$(openssl rand -hex 8)"
        echo "prompt<<${delim}"
        jq -r '.prompt' <<< "${first}"
        echo "${delim}"
    } >> "${GITHUB_OUTPUT}"
}

#######################################
# main: Entry point for loop-detect
#
# Arguments:
#   None
#
# Global Variables:
#   CANDIDATES_JSON, INTEGRATION_BRANCHES, OPEN_PRS_JSON - Populated during run
#
# Returns:
#   None
#
#######################################
function main {
    : "${DETECT_SCRIPT:?}"
    : "${STATE_FILE:?}"
    : "${LOOP_NAME:?}"
    : "${BASE_BRANCH:?}"
    : "${SKILL_NAME:?}"
    : "${LEVEL:?}"
    : "${ALLOWLIST:?}"

    local should_run="false"
    local skip_reason="none"
    local target_matrix_json="[]"
    local now_epoch branch pr_json gh_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    local pre_peer_count pre_cap_count

    mkdir -p "$(dirname "${STATE_FILE}")"
    migrate_state_targets "${STATE_FILE}" "${BASE_BRANCH}"

    if ! validate_branch_match; then
        write_detect_outputs "false" "config_error" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

    if budget_exceeded "${LOOP_NAME}" "${BUDGET_FILE}" "${RUN_LOG_FILE}" \
        "${BUDGET_MAX_RUNS_PER_DAY}" "${BUDGET_MAX_TOKENS_PER_DAY}"; then
        write_detect_outputs "false" "budget" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

    resolve_integration_branches "${LOOP_INTEGRATION_BRANCHES}" "${BASE_BRANCH}"
    list_open_prs "${LOOP_PR_EXCLUDE}" "${LOOP_PR_INCLUDE_BOTS}" "${gh_token}" || {
        write_detect_outputs "false" "config_error" "[]"
        write_legacy_outputs "[]"
        return 0
    }

    if [[ ${#INTEGRATION_BRANCHES[@]} -eq 0 && ${#OPEN_PRS_JSON[@]} -eq 0 ]]; then
        write_detect_outputs "false" "no_changes" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

    for branch in "${INTEGRATION_BRANCHES[@]}"; do
        append_integration_candidate "${branch}"
    done

    for pr_json in "${OPEN_PRS_JSON[@]}"; do
        append_pull_request_candidate "${pr_json}"
    done

    if [[ ${#CANDIDATES_JSON[@]} -eq 0 ]]; then
        if [[ ${CIRCUIT_BREAKER_BLOCKED} -gt 0 ]]; then
            write_detect_outputs "false" "circuit_breaker" "[]"
        else
            write_detect_outputs "false" "no_changes" "[]"
        fi
        write_legacy_outputs "[]"
        return 0
    fi

    sort_candidates_by_priority

    now_epoch=$(date -u +%s)
    pre_peer_count=${#CANDIDATES_JSON[@]}
    apply_peer_active_filter "${now_epoch}"

    if [[ ${#CANDIDATES_JSON[@]} -eq 0 && ${pre_peer_count} -gt 0 ]]; then
        write_detect_outputs "false" "peer_active" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

    pre_cap_count=${#CANDIDATES_JSON[@]}
    apply_target_cap "${LOOP_MAX_TARGETS_PER_SCHEDULE}"
    if [[ ${pre_cap_count} -gt ${LOOP_MAX_TARGETS_PER_SCHEDULE} ]]; then
        skip_reason="target_budget"
    fi

    target_matrix_json="$(printf '%s\n' "${CANDIDATES_JSON[@]}" | jq -sc '.')"
    should_run="true"

    write_detect_outputs "${should_run}" "${skip_reason}" "${target_matrix_json}"
    write_legacy_outputs "${target_matrix_json}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
