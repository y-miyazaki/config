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
# - Pins DETECT_SCRIPT to an absolute path before any target checkout
# - Scopes watch lists when LOOP_SCOPED_HEAD_BRANCH or workflow_run event head is set
# - Invokes detect_script once per scan context (caller never re-runs)
# - Assembles target_matrix with prompt and verifier_context per cell
#
# Dependencies:
# - bash, git, jq, openssl
# - gh (when LOOP_PR_ENABLED=true)
#
# Optional environment:
#   DETECT_SCRIPT, STATE_FILE, LOOP_NAME, BASE_BRANCH, SKILL_NAME, LEVEL, ALLOWLIST
#   LOOP_INTEGRATION_BRANCHES, LOOP_PR_ENABLED, LOOP_BRANCH_MATCH, LOOP_PRIORITY
#   DELIVERY, GIT_FINALIZE_INTEGRATION, GIT_FINALIZE_PULL_REQUEST, GIT_LANDING_INTEGRATION, GIT_LANDING_PULL_REQUEST
#   LOOP_MAX_TARGETS_PER_SCHEDULE
#   LOOP_PR_EXCLUDE, LOOP_PR_INCLUDE_BOTS, LOOP_PR_ENABLED, PROMPT_INSTRUCTIONS, BUDGET_FILE, RUN_LOG_FILE
#   LOOP_SCOPED_HEAD_BRANCH - when set, only scan this integration branch / PR head
#   CI_SWEEPER_WORKFLOW_RUN_ID + CI_SWEEPER_EVENT_HEAD_BRANCH - workflow_run scope fallback
#   GH_TOKEN / GITHUB_TOKEN
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load initialization library
# shellcheck source=./_init.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_init.sh"

#######################################
# Global variables
#######################################
# Environment supplied by loop-detect composite action (validated in main).
BASE_BRANCH="${BASE_BRANCH-}"
DETECT_SCRIPT="${DETECT_SCRIPT-}"
STATE_FILE="${STATE_FILE-}"

#######################################
# resolve_detect_script_path: Pin DETECT_SCRIPT to an absolute path
#
# Must run before any target checkout. Relative detect scripts otherwise resolve
# against the watched branch worktree (stale PR heads can ship older detect logic).
#
# Globals:
#   DETECT_SCRIPT - Updated in place to an absolute path
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success; non-zero when the script cannot be resolved
#
#######################################
function resolve_detect_script_path {
    local resolved

    if [[ -z ${DETECT_SCRIPT} ]]; then
        log_detect_error "DETECT_SCRIPT is empty"
        return 1
    fi

    if [[ ${DETECT_SCRIPT} == /* ]]; then
        resolved="${DETECT_SCRIPT}"
    else
        resolved="$(pwd)/${DETECT_SCRIPT}"
    fi

    if [[ ! -f ${resolved} ]]; then
        log_detect_error "DETECT_SCRIPT not found: ${resolved}"
        return 1
    fi

    # Prefer realpath when available so checkout symlinks do not re-bind the script.
    if command -v realpath > /dev/null 2>&1; then
        resolved="$(realpath "${resolved}")"
    else
        resolved="$(cd "$(dirname "${resolved}")" && pwd)/$(basename "${resolved}")"
    fi

    if [[ ! -f ${resolved} ]]; then
        log_detect_error "DETECT_SCRIPT not found after resolve: ${resolved}"
        return 1
    fi

    DETECT_SCRIPT="${resolved}"
    log_detect_notice "detect-script" "pinned" "path=${DETECT_SCRIPT}"
}

#######################################
# resolve_scoped_head_branch: Head branch that scopes watch enumeration
#
# workflow_run dogfood sets CI_SWEEPER_WORKFLOW_RUN_ID + CI_SWEEPER_EVENT_HEAD_BRANCH.
# Callers may also set LOOP_SCOPED_HEAD_BRANCH explicitly (wins).
# Empty result = scan all resolved integration branches / open PRs (schedule).
#
# Globals:
#   LOOP_SCOPED_HEAD_BRANCH, CI_SWEEPER_WORKFLOW_RUN_ID, CI_SWEEPER_EVENT_HEAD_BRANCH
#
# Arguments:
#   None
#
# Outputs:
#   Scoped branch name on stdout (may be empty)
#
# Returns:
#   0 on success
#
#######################################
function resolve_scoped_head_branch {
    local scoped="${LOOP_SCOPED_HEAD_BRANCH:-}"

    if [[ -n ${scoped} ]]; then
        printf '%s' "${scoped}"
        return 0
    fi

    if [[ -n ${CI_SWEEPER_WORKFLOW_RUN_ID:-} ]]; then
        # Prefer EVENT_HEAD_BRANCH (stable); never CI_SWEEPER_HEAD_BRANCH (rewritten per scan).
        printf '%s' "${CI_SWEEPER_EVENT_HEAD_BRANCH:-}"
        return 0
    fi

    printf ''
}

#######################################
# require_scoped_head_for_workflow_run: Fail closed when workflow_run lacks a head
#
# A workflow_run id without a scoped head would otherwise fall through to a full
# watch-list scan (integration + all open PRs). Refuse that fan-out.
#
# Globals:
#   CI_SWEEPER_WORKFLOW_RUN_ID - when set, scoped head is required
#
# Arguments:
#   $1 - Scoped head branch from resolve_scoped_head_branch
#
# Outputs:
#   None
#
# Returns:
#   0 when safe to continue; 1 when detect should abort with config_error
#
#######################################
function require_scoped_head_for_workflow_run {
    local scoped_head="$1"

    if [[ -z ${CI_SWEEPER_WORKFLOW_RUN_ID:-} ]]; then
        return 0
    fi
    if [[ -n ${scoped_head} ]]; then
        return 0
    fi

    log_detect_error \
        "workflow_run scope incomplete: CI_SWEEPER_WORKFLOW_RUN_ID is set but scoped head is empty (set CI_SWEEPER_EVENT_HEAD_BRANCH or LOOP_SCOPED_HEAD_BRANCH)"
    return 1
}

#######################################
# apply_scoped_head_filter: Keep only watch targets matching the failed head
#
# Use cases:
# - workflow_run on main → only integration:main (do not fan out to open PRs)
# - workflow_run on PR head → only that pull_request target
# - empty scoped head → no-op (schedule / workflow_dispatch full scan)
#
# Globals:
#   INTEGRATION_BRANCHES, OPEN_PRS_JSON - Filtered in place
#
# Arguments:
#   $1 - Scoped head branch (empty = no-op)
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function apply_scoped_head_filter {
    local scoped_head="$1"
    local -a kept_branches=()
    local -a kept_prs=()
    local branch pr_json head_ref

    if [[ -z ${scoped_head} ]]; then
        return 0
    fi

    for branch in "${INTEGRATION_BRANCHES[@]+"${INTEGRATION_BRANCHES[@]}"}"; do
        if [[ ${branch} == "${scoped_head}" ]]; then
            kept_branches+=("${branch}")
        fi
    done
    INTEGRATION_BRANCHES=()
    if [[ ${#kept_branches[@]} -gt 0 ]]; then
        INTEGRATION_BRANCHES=("${kept_branches[@]}")
    fi

    for pr_json in "${OPEN_PRS_JSON[@]+"${OPEN_PRS_JSON[@]}"}"; do
        head_ref="$(jq -r '.headRefName // empty' <<< "${pr_json}")"
        if [[ ${head_ref} == "${scoped_head}" ]]; then
            kept_prs+=("${pr_json}")
        fi
    done
    OPEN_PRS_JSON=()
    if [[ ${#kept_prs[@]} -gt 0 ]]; then
        OPEN_PRS_JSON=("${kept_prs[@]}")
    fi

    log_detect_notice "scoped-head" "${scoped_head}" \
        "integration=${#INTEGRATION_BRANCHES[@]} pull_request=${#OPEN_PRS_JSON[@]}"
}

#######################################
# build_integration_target_json: Build target JSON for integration mode
#
# Globals:
#   None
#
# Arguments:
#   $1 - target_key
#   $2 - branch name
#   $3 - current SHA
#   $4 - finalize action
#
# Outputs:
#   Target JSON to stdout
#
# Returns:
#   0 on success
#
#######################################
function build_integration_target_json {
    local target_key="$1"
    local branch="$2"
    local current_sha="$3"
    local finalize="$4"

    jq -nc \
        --arg mode "integration" \
        --arg key "${target_key}" \
        --arg from_branch "${branch}" \
        --arg from_ref "${current_sha}" \
        --arg to_branch "${branch}" \
        --arg finalize "${finalize}" \
        '{
            mode: $mode,
            key: $key,
            from: {branch: $from_branch, ref: $from_ref},
            to: {branch: $to_branch},
            finalize: $finalize
        }'
}

#######################################
# build_pull_request_target_json: Build target JSON for pull_request mode
#
# Globals:
#   None
#
# Arguments:
#   $1 - target_key
#   $2 - head branch
#   $3 - current SHA
#   $4 - finalize action
#   $5 - PR number
#   $6 - base branch
#
# Outputs:
#   Target JSON to stdout
#
# Returns:
#   0 on success
#
#######################################
function build_pull_request_target_json {
    local target_key="$1"
    local head_branch="$2"
    local current_sha="$3"
    local finalize="$4"
    local pr_number="$5"
    local base_branch="$6"

    jq -nc \
        --arg mode "pull_request" \
        --arg key "${target_key}" \
        --arg from_branch "${head_branch}" \
        --arg from_ref "${current_sha}" \
        --arg to_branch "${head_branch}" \
        --argjson pr_number "${pr_number}" \
        --arg base_branch "${base_branch}" \
        --arg finalize "${finalize}" \
        '{
            mode: $mode,
            key: $key,
            from: {branch: $from_branch, ref: $from_ref},
            to: {branch: $to_branch, pr_number: $pr_number},
            base: {branch: $base_branch},
            finalize: $finalize
        }'
}

#######################################
# append_detect_candidate: Shared detect/checkout/circuit/pending candidate pipeline
#
# Globals:
#   CANDIDATES_JSON - Candidate JSON strings appended on success
#   CIRCUIT_BREAKER_BLOCKED - Incremented when circuit breaker is open
#   PENDING_PR_BLOCKED - Incremented when pending PR blocks detect
#   STATE_FILE - Loop state JSON path
#   BASE_BRANCH - Default base branch
#   DETECT_SCRIPT - Detect script path
#   SKILL_NAME, LEVEL, ALLOWLIST, PROMPT_INSTRUCTIONS - Prompt inputs
#
# Arguments:
#   $1 - Target key
#   $2 - Head branch name
#   $3 - Optional checkout ref (empty string to omit)
#   $4 - Finalize mode
#   $5 - Optional accept-log extra text
#   $6 - Target JSON builder function name
#   $7+ - Extra args forwarded to the builder after common args
#
# Outputs:
#   Warning/notice annotations via helper loggers
#
# Returns:
#   None (returns early on checkout/circuit/pending/skip failures)
#
#######################################
function append_detect_candidate {
    local target_key="$1"
    local head_branch="$2"
    local checkout_ref="${3:-}"
    local finalize="$4"
    local accept_log_extra="${5:-}"
    local target_json_builder="$6"
    shift 6
    local builder_args=("$@")
    local target_state last_sha current_sha detect_result verifier_context prompt_text open_prompt consecutive pending_pr
    local target_json candidate

    if [[ -n $checkout_ref ]]; then
        checkout_context "${head_branch}" "${checkout_ref}" || return 0
    else
        checkout_context "${head_branch}" || return 0
    fi

    target_state="$(read_target_state "${STATE_FILE}" "${target_key}" "${BASE_BRANCH}")"
    consecutive="$(target_consecutive_failures "${target_state}")"
    if target_circuit_breaker_open "${consecutive}"; then
        echo "::warning::Circuit breaker open for ${target_key}"
        CIRCUIT_BREAKER_BLOCKED=$((CIRCUIT_BREAKER_BLOCKED + 1))
        return 0
    fi

    if target_pending_blocks_detect "${target_state}"; then
        pending_pr=$(jq -r '.pending.pr // empty' <<< "${target_state}")
        echo "::warning::Pending PR #${pending_pr} blocks detect for ${target_key}"
        PENDING_PR_BLOCKED=$((PENDING_PR_BLOCKED + 1))
        return 0
    fi

    last_sha="$(target_last_sha "${target_state}" "${head_branch}")"
    current_sha="$(git rev-parse HEAD)"
    export CI_SWEEPER_HEAD_BRANCH="${head_branch}"
    export DEFAULT_BASE_BRANCH="${BASE_BRANCH}"
    detect_result="$(bash "${DETECT_SCRIPT}" --scope range --since "${last_sha}")"

    if detect_result_skip "${detect_result}"; then
        log_detect_notice "skip" "${target_key}" \
            "detect skip=true failures=$(jq -r '.failures|length // 0' <<< "${detect_result}") ignored=$(jq -r '.ignored|length // 0' <<< "${detect_result}") ignored_reasons=$(jq -r '[.ignored[]?.reason // empty] | join("; ")' <<< "${detect_result}")"
        return 0
    fi

    open_prompt="$(target_open_rejections_prompt "${target_state}")"
    verifier_context="$(build_verifier_context_from_result "${detect_result}")"

    target_json="$("${target_json_builder}" "${target_key}" "${head_branch}" "${current_sha}" "${finalize}" "${builder_args[@]}")"
    target_json="$(enrich_target_json_with_ci_context "${target_json}" "${detect_result}")"
    target_json="$(enrich_target_json_with_detect_fields "${target_json}" "${detect_result}")"

    local report_file
    local may_edit="${MAY_EDIT:-}"
    local write_target="${WRITE_TARGET:-}"

    report_file="$(jq -r '.report_file // ""' <<< "${detect_result}" 2> /dev/null || echo "")"
    prompt_text="$(build_prompt_text \
        "${SKILL_NAME}" "${LEVEL}" "${ALLOWLIST}" "${PROMPT_INSTRUCTIONS}" \
        "${last_sha}" "${current_sha}" "${detect_result}" "${open_prompt}" "${consecutive}" \
        "${may_edit}" "${write_target}" "${report_file}")"

    candidate="$(build_loop_candidate_json \
        "${target_key}" "${target_json}" "${prompt_text}" "${verifier_context}" "${detect_result}")" \
        || return 0

    if [[ -n $accept_log_extra ]]; then
        log_detect_notice "accept" "${target_key}" \
            "failures=$(jq -r '.failures|length // 0' <<< "${detect_result}") failure_types=$(jq -r '[.failures[]?.failure_type // empty] | unique | join(",")' <<< "${detect_result}") ${accept_log_extra}"
    else
        log_detect_notice "accept" "${target_key}" \
            "failures=$(jq -r '.failures|length // 0' <<< "${detect_result}") failure_types=$(jq -r '[.failures[]?.failure_type // empty] | unique | join(",")' <<< "${detect_result}")"
    fi
    CANDIDATES_JSON+=("${candidate}")
}

#######################################
# append_integration_candidate: Scan one integration branch
#
# Globals:
#   GIT_FINALIZE_INTEGRATION - Git landing strategy for integration targets (derived from delivery)
#
# Arguments:
#   $1 - Branch name
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function append_integration_candidate {
    local branch="$1"
    append_detect_candidate \
        "integration:${branch}" \
        "${branch}" \
        "" \
        "${GIT_FINALIZE_INTEGRATION:-open_pr}" \
        "" \
        build_integration_target_json \
        "${branch}"
}

#######################################
# append_pull_request_candidate: Scan one open pull request head
#
# Globals:
#   GIT_FINALIZE_PULL_REQUEST - Git landing strategy for pull request targets (derived from delivery)
#
# Arguments:
#   $1 - PR JSON object
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function append_pull_request_candidate {
    local pr_json="$1"
    local pr_number head_branch head_ref base_branch

    pr_number=$(jq -r '.number' <<< "${pr_json}")
    head_branch=$(jq -r '.headRefName' <<< "${pr_json}")
    head_ref=$(jq -r '.headRefOid' <<< "${pr_json}")
    base_branch=$(jq -r '.baseRefName' <<< "${pr_json}")

    append_detect_candidate \
        "pull_request:${pr_number}" \
        "${head_branch}" \
        "${head_ref}" \
        "${GIT_FINALIZE_PULL_REQUEST:-open_pr}" \
        "head=${head_branch}" \
        build_pull_request_target_json \
        "${pr_number}" \
        "${base_branch}"
}

#######################################
# apply_target_cap: Cap candidates at LOOP_MAX_TARGETS_PER_SCHEDULE
#
# Globals:
#   CANDIDATES_JSON - Truncated in place when over cap
#
# Arguments:
#   $1 - Maximum targets per schedule
#
# Outputs:
#   None
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
# build_loop_candidate_json: Assemble one matrix cell from detect payloads
#
# Globals:
#   None
#
# Arguments:
#   $1 - Target key (for logs)
#   $2 - target_json object string
#   $3 - Prompt text
#   $4 - Verifier context markdown
#   $5 - Detect script JSON result
#
# Outputs:
#   Candidate JSON to stdout; non-zero when assembly fails
#
# Returns:
#   0 on success
#
#######################################
function build_loop_candidate_json {
    local target_key="$1"
    local target_json="$2"
    local prompt_text="$3"
    local verifier_context="$4"
    local detect_result="$5"
    local candidate jq_stderr target_file result_file prompt_file verifier_file

    log_detect_notice "candidate" "${target_key}" \
        "target_json_bytes=${#target_json} detect_bytes=${#detect_result}"

    if [[ -z ${target_json} ]]; then
        log_detect_error "build_loop_candidate_json(${target_key}): target_json is empty after enrich"
        return 1
    fi
    if ! jq -e . <<< "${target_json}" > /dev/null 2>&1; then
        log_detect_json_invalid "build_loop_candidate_json(${target_key})" "target_json" "${target_json}"
        return 1
    fi
    if ! jq -e . <<< "${detect_result}" > /dev/null 2>&1; then
        log_detect_json_invalid "build_loop_candidate_json(${target_key})" "detect_result" "${detect_result}"
        return 1
    fi

    target_file="$(mktemp)"
    result_file="$(mktemp)"
    prompt_file="$(mktemp)"
    verifier_file="$(mktemp)"
    jq_stderr="$(mktemp)"
    printf '%s' "${target_json}" > "${target_file}"
    printf '%s' "${detect_result}" > "${result_file}"
    printf '%s' "${prompt_text}" > "${prompt_file}"
    printf '%s' "${verifier_context}" > "${verifier_file}"

    candidate="$(jq -n \
        --slurpfile target_json "${target_file}" \
        --rawfile prompt "${prompt_file}" \
        --rawfile verifier_context "${verifier_file}" \
        --slurpfile result "${result_file}" \
        '{target_json: $target_json[0], prompt: $prompt, verifier_context: $verifier_context, result: $result[0]}' \
        2> "${jq_stderr}")" || {
        log_detect_error "build_loop_candidate_json(${target_key}): jq assembly failed (target_json_bytes=${#target_json}, detect_bytes=${#detect_result}, prompt_bytes=${#prompt_text}, verifier_bytes=${#verifier_context}): $(tr -d '\n\r' < "${jq_stderr}")"
        rm -f "${target_file}" "${result_file}" "${prompt_file}" "${verifier_file}" "${jq_stderr}"
        return 1
    }
    rm -f "${target_file}" "${result_file}" "${prompt_file}" "${verifier_file}" "${jq_stderr}"

    if [[ -z ${candidate} ]] || ! jq -e . <<< "${candidate}" > /dev/null 2>&1; then
        log_detect_json_invalid "build_loop_candidate_json(${target_key})" "candidate_output" "${candidate}"
        return 1
    fi

    printf '%s' "${candidate}"
}

#######################################
# checkout_context: Fetch and checkout branch at optional ref
#
# Globals:
#   CHECKOUT_FAILED - Incremented on fetch or checkout failure
#
# Arguments:
#   $1 - Branch name
#   $2 - Optional ref (default: origin/branch)
#
# Outputs:
#   Warning/error annotations to stdout
#
# Returns:
#   0 on success, 1 on invalid branch name, fetch exhaustion, or checkout failure
#
#######################################
function checkout_context {
    local branch="$1"
    local ref="${2:-}"
    local attempt
    local fetch_ok=false

    if ! [[ ${branch} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::Invalid branch name: ${branch}"
        return 1
    fi

    for attempt in 1 2 3; do
        if git fetch origin "${branch}" --prune > /dev/null 2>&1; then
            fetch_ok=true
            break
        fi
        if [[ ${attempt} -lt 3 ]]; then
            sleep 1
        fi
    done

    if [[ ${fetch_ok} != "true" ]]; then
        echo "::warning::loop-detect/checkout: fetch failed for branch ${branch} after 3 attempts"
        CHECKOUT_FAILED=$((CHECKOUT_FAILED + 1))
        return 1
    fi

    if [[ -n ${ref} ]]; then
        if git checkout -q "${ref}" 2> /dev/null || git checkout -q -B "${branch}" "origin/${branch}" 2> /dev/null; then
            return 0
        fi
        echo "::warning::loop-detect/checkout: checkout failed for ${branch} ref ${ref}"
        CHECKOUT_FAILED=$((CHECKOUT_FAILED + 1))
        return 1
    fi

    if git checkout -q -B "${branch}" "origin/${branch}" 2> /dev/null || git checkout -q "${branch}" 2> /dev/null; then
        return 0
    fi

    echo "::warning::loop-detect/checkout: checkout failed for branch ${branch}"
    CHECKOUT_FAILED=$((CHECKOUT_FAILED + 1))
    return 1
}

#######################################
# detect_result_skip: Return 0 when detect script JSON indicates skip
#
# Globals:
#   None
#
# Arguments:
#   $1 - Detect script JSON result
#
# Outputs:
#   None
#
# Returns:
#   0 when skip is true, 1 otherwise
#
#######################################
function detect_result_skip {
    local result="$1"
    local skip_val
    if ! jq -e . <<< "${result}" > /dev/null 2>&1; then
        log_detect_json_invalid "detect_result_skip" "detect_script_output" "${result}"
        return 1
    fi
    skip_val=$(jq -r 'if (.skip | type) == "boolean" then (.skip | tostring) else "true" end' <<< "${result}")
    [[ ${skip_val} == "true" ]]
}

#######################################
# enrich_target_json_with_ci_context: Add CI failure fields to target_json
#
# Globals:
#   None
#
# Arguments:
#   $1 - Base target_json object string
#   $2 - Detect script JSON result
#
# Outputs:
#   Enriched target_json on stdout
#
# Returns:
#   0 on success
#
#######################################
function enrich_target_json_with_ci_context {
    local target_json="$1"
    local detect_result="$2"
    local enriched jq_stderr base_file detect_file

    if ! jq -e '.failures[0]' <<< "${detect_result}" > /dev/null 2>&1; then
        printf '%s' "${target_json}"
        return 0
    fi

    if ! jq -e . <<< "${target_json}" > /dev/null 2>&1; then
        log_detect_json_invalid "enrich_target_json_with_ci_context" "target_json" "${target_json}"
        return 1
    fi
    if ! jq -e . <<< "${detect_result}" > /dev/null 2>&1; then
        log_detect_json_invalid "enrich_target_json_with_ci_context" "detect_result" "${detect_result}"
        printf '%s' "${target_json}"
        return 0
    fi

    log_detect_notice "enrich" "ci-context" \
        "base_bytes=${#target_json} detect_bytes=${#detect_result}"

    base_file="$(mktemp)"
    detect_file="$(mktemp)"
    jq_stderr="$(mktemp)"
    printf '%s' "${target_json}" > "${base_file}"
    printf '%s' "${detect_result}" > "${detect_file}"

    enriched="$(jq -n \
        --slurpfile base "${base_file}" \
        --slurpfile detect "${detect_file}" \
        '($detect[0].failures[0] // {}) as $f
         | $base[0]
         | if ($f.workflow_run_id // "") != "" then .workflow_run_id = ($f.workflow_run_id | tostring) else . end
         | if ($f.workflow_name // "") != "" then .workflow_name = $f.workflow_name else . end
         | if ($f.head_sha // "") != "" then .head_sha = $f.head_sha else . end' \
        2> "${jq_stderr}")" || {
        log_detect_error "enrich_target_json_with_ci_context: jq enrich failed (base_bytes=${#target_json}, detect_bytes=${#detect_result}): $(tr -d '\n\r' < "${jq_stderr}")"
        rm -f "${base_file}" "${detect_file}" "${jq_stderr}"
        printf '%s' "${target_json}"
        return 0
    }
    rm -f "${base_file}" "${detect_file}" "${jq_stderr}"

    if [[ -z ${enriched} ]] || ! jq -e . <<< "${enriched}" > /dev/null 2>&1; then
        log_detect_json_invalid "enrich_target_json_with_ci_context" "enriched_output" "${enriched}"
        log_detect_error "enrich_target_json_with_ci_context: using base target_json after enrich failure"
        printf '%s' "${target_json}"
        return 0
    fi

    log_detect_notice "enrich" "ok" \
        "workflow_run_id=$(jq -r '.workflow_run_id // "-"' <<< "${enriched}")"
    printf '%s' "${enriched}"
}

#######################################
# enrich_target_json_with_detect_fields: Add detect-owned fields to target_json
#
# Globals:
#   None
#
# Arguments:
#   $1 - Base target_json object string
#   $2 - Detect script JSON result
#
# Outputs:
#   Enriched target_json on stdout
#
# Returns:
#   0 on success
#
#######################################
function enrich_target_json_with_detect_fields {
    local target_json="$1"
    local detect_result="$2"
    local report_file

    if ! jq -e . <<< "${target_json}" > /dev/null 2>&1; then
        log_detect_json_invalid "enrich_target_json_with_detect_fields" "target_json" "${target_json}"
        return 1
    fi

    report_file="$(jq -r '.report_file // ""' <<< "${detect_result}" 2> /dev/null || echo "")"
    if [[ -z ${report_file} ]]; then
        printf '%s' "${target_json}"
        return 0
    fi

    jq -c --arg rf "${report_file}" '. + {report_file: $rf}' <<< "${target_json}"
}

#######################################
# resolve_git_finalize_strategies: Map delivery to git finalize modes
#
# Globals:
#   DELIVERY, GIT_LANDING_INTEGRATION, GIT_LANDING_PULL_REQUEST - Read
#   GIT_FINALIZE_INTEGRATION, GIT_FINALIZE_PULL_REQUEST - Set on success
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success; 1 when delivery or git_landing values are invalid
#
#######################################
function resolve_git_finalize_strategies {
    case "${DELIVERY}" in
        open_pr)
            GIT_FINALIZE_INTEGRATION="${GIT_LANDING_INTEGRATION:-open_pr}"
            GIT_FINALIZE_PULL_REQUEST="${GIT_LANDING_PULL_REQUEST:-open_pr}"
            case "${GIT_FINALIZE_INTEGRATION}" in
                open_pr | push) ;;
                *)
                    echo "::error::git_landing_integration must be open_pr or push (got: ${GIT_FINALIZE_INTEGRATION})" >&2
                    return 1
                    ;;
            esac
            case "${GIT_FINALIZE_PULL_REQUEST}" in
                open_pr | push_head) ;;
                *)
                    echo "::error::git_landing_pull_request must be open_pr or push_head (got: ${GIT_FINALIZE_PULL_REQUEST})" >&2
                    return 1
                    ;;
            esac
            ;;
        none | log | issue | notion)
            GIT_FINALIZE_INTEGRATION="none"
            GIT_FINALIZE_PULL_REQUEST="none"
            ;;
        *)
            echo "::error::delivery must be log|issue|notion|open_pr|none (got: ${DELIVERY})" >&2
            return 1
            ;;
    esac
}

#######################################
# resolve_loop_write_contract: Resolve and validate loop write/delivery contract
#
# Globals:
#   MAY_EDIT, WRITE_TARGET, DELIVERY, LEVEL - Read and updated in place
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success; 1 when validation fails
#
#######################################
function resolve_loop_write_contract {
    MAY_EDIT="${MAY_EDIT:-}"
    WRITE_TARGET="${WRITE_TARGET:-}"
    DELIVERY="${DELIVERY:-open_pr}"

    if [[ -z ${MAY_EDIT} ]]; then
        echo "::error::may_edit is required; set may_edit on the caller" >&2
        return 1
    fi

    if ! declare -f validate_loop_write_contract > /dev/null 2>&1; then
        _loop_action_lib="$(cd "${SCRIPT_DIR}/../../lib/loop" && pwd)"
        # shellcheck source=../../lib/loop/validate_loop_write_contract.sh disable=SC1091
        source "${_loop_action_lib}/validate_loop_write_contract.sh"
    fi

    if ! validate_loop_write_contract "${MAY_EDIT}" "${WRITE_TARGET}" "${DELIVERY}" "${LEVEL}"; then
        return 1
    fi

    resolve_git_finalize_strategies
}

#######################################
# log_detect_error: Emit a GitHub Actions error annotation
#
# Globals:
#   None
#
# Arguments:
#   $1 - Message
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function log_detect_error {
    echo "::error::loop-detect: $*" >&2
}

#######################################
# log_detect_json_invalid: Log JSON validation failure with jq diagnostics
#
# Globals:
#   None
#
# Arguments:
#   $1 - Context (function or stage name)
#   $2 - Label for the invalid payload (e.g. detect_result)
#   $3 - Raw JSON string that failed validation
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function log_detect_json_invalid {
    local context="$1"
    local label="$2"
    local json="$3"
    local jq_err preview

    jq_err="$(jq -e . <<< "${json}" 2>&1 > /dev/null || true)"
    jq_err="$(tr -d '\n\r' <<< "${jq_err}")"
    preview="$(printf '%.120s' "${json}" | tr -d '\n\r\t')"
    log_detect_error \
        "${context}: ${label} is not valid JSON (bytes=${#json}, jq_error=${jq_err:-unknown}, preview=${preview})"
}

#######################################
# log_detect_notice: Emit a GitHub Actions notice for detect diagnostics
#
# Globals:
#   None
#
# Arguments:
#   $1 - Stage name
#   $2 - Target key or scope
#   $3 - Detail text
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function log_detect_notice {
    local stage="$1"
    local scope="$2"
    local detail="$3"
    echo "::notice title=loop-detect/${stage}::${scope}: ${detail}" >&2
}

#######################################
# validate_branch_match: Return 0 when LOOP_BRANCH_MATCH is valid
#
# Globals:
#   LOOP_BRANCH_MATCH - Match mode under validation
#
# Arguments:
#   None
#
# Outputs:
#   None
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
# write_empty_candidates_outputs: Emit skip outputs when no candidates remain
#
# Globals:
#   CHECKOUT_FAILED - Checkout failure count
#   CIRCUIT_BREAKER_BLOCKED - Circuit breaker block count
#   PENDING_PR_BLOCKED - Pending PR block count
#   GITHUB_OUTPUT - Written via write_detect_outputs / write_legacy_outputs
#
# Arguments:
#   None
#
# Outputs:
#   Skip reason outputs to GITHUB_OUTPUT
#
# Returns:
#   None
#
#######################################
function write_empty_candidates_outputs {
    if [[ ${CIRCUIT_BREAKER_BLOCKED} -gt 0 ]]; then
        write_detect_outputs "false" "circuit_breaker" "[]"
    elif [[ ${PENDING_PR_BLOCKED} -gt 0 ]]; then
        write_detect_outputs "false" "pending_pr" "[]"
    elif [[ ${CHECKOUT_FAILED} -gt 0 ]]; then
        write_detect_outputs "false" "checkout_failed" "[]"
    else
        write_detect_outputs "false" "no_changes" "[]"
    fi
    write_legacy_outputs "[]"
}

#######################################
# write_legacy_outputs: Backward-compatible single-target outputs
#
# Globals:
#   GITHUB_OUTPUT, STATE_FILE, BASE_BRANCH
#
# Arguments:
#   $1 - target_matrix JSON array string
#
# Outputs:
#   None
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
# Globals:
#   CANDIDATES_JSON, INTEGRATION_BRANCHES, OPEN_PRS_JSON - Populated during run
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
function main {
    : "${DETECT_SCRIPT:?}"
    : "${STATE_FILE:?}"
    : "${LOOP_NAME:?}"
    : "${BASE_BRANCH:?}"
    : "${SKILL_NAME:?}"
    : "${LEVEL:?}"
    : "${ALLOWLIST:?}"

    if ! resolve_loop_write_contract; then
        write_detect_outputs "false" "config_error" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

    local should_run="false"
    local skip_reason="none"
    local target_matrix_json="[]"
    local branch pr_json gh_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    local pre_cap_count
    local scoped_head
    CHECKOUT_FAILED=0

    # Pin detect script before any target checkout (stale PR trees must not supply it).
    if ! resolve_detect_script_path; then
        write_detect_outputs "false" "config_error" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

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

    scoped_head="$(resolve_scoped_head_branch)"
    if ! require_scoped_head_for_workflow_run "${scoped_head}"; then
        write_detect_outputs "false" "config_error" "[]"
        write_legacy_outputs "[]"
        return 0
    fi
    apply_scoped_head_filter "${scoped_head}"

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
        write_empty_candidates_outputs
        return 0
    fi

    sort_candidates_by_priority

    pre_cap_count=${#CANDIDATES_JSON[@]}
    apply_target_cap "${LOOP_MAX_TARGETS_PER_SCHEDULE}"
    if [[ ${pre_cap_count} -gt ${LOOP_MAX_TARGETS_PER_SCHEDULE} ]]; then
        skip_reason="target_budget"
    fi

    local handoff_dir="${RUNNER_TEMP:-/tmp}/loop-handoff"
    local full_matrix_json candidate slim_candidate
    local -a slim_candidates=()

    full_matrix_json="$(printf '%s\n' "${CANDIDATES_JSON[@]}" | jq -sc '.')"
    loop_handoff_write_bundle "${handoff_dir}" "${CANDIDATES_JSON[@]}"

    for candidate in "${CANDIDATES_JSON[@]}"; do
        slim_candidate="$(shrink_matrix_candidate_for_output "${candidate}")"
        slim_candidates+=("${slim_candidate}")
    done
    target_matrix_json="$(printf '%s\n' "${slim_candidates[@]}" | jq -sc '.')"
    should_run="true"

    log_detect_notice "matrix" "${LOOP_NAME}" \
        "should_run=true count=${#CANDIDATES_JSON[@]} keys=$(jq -r '[.[].target_json.key] | join(",")' <<< "${target_matrix_json}") skip_reason=${skip_reason} pr_enabled=${LOOP_PR_ENABLED} max_targets=${LOOP_MAX_TARGETS_PER_SCHEDULE} handoff_dir=${handoff_dir}"

    write_detect_outputs "${should_run}" "${skip_reason}" "${target_matrix_json}"
    write_legacy_outputs "${full_matrix_json}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
