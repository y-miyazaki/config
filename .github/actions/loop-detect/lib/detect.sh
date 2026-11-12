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
# - Scopes watch lists when LOOP_SCOPED_HEAD_BRANCH, DETECT_PR_NUMBER, or workflow_run event head is set
# - Validates level/delivery inputs first; a validation failure exits 1 (fails the job)
# - delivery pr_push without a PR number skips with skip_reason=pr_number_missing (exit 0)
# - Every target kind must be allowed by delivery (validate_delivery_target)
# - Invokes detect_script once per scan context (caller never re-runs)
# - Assembles target_matrix with prompt and verifier_context per cell
# - DETECT_ITEMS=true gates and orders result.items per item key; the branch key is not consulted
# - Detect-script boundary: coupled only on the success-path interface (exit 0, valid JSON,
#   skip flag, fields consumed for matrix/prompt). On non-zero exit, echo stdout verbatim and
#   fail — do not interpret skill error JSON (status, message, schema). Multi-target scans
#   fail fast: a later-target detect failure exits before write_detect_outputs.
#
# Dependencies:
# - bash, git, jq, openssl
# - gh (when DETECT_PR_ENABLED=true)
#
# Required environment:
#   DETECT_SCRIPT, STATE_FILE, LOOP_NAME, STATE_BRANCH, AGENT_MAKER_SKILL_NAME
#   LEVEL, DELIVERY (no defaults; validated by validate_detect_inputs)
#
# Optional environment:
#   AGENT_EDIT_TARGET, AGENT_EDIT_ALLOWLIST, AGENT_EDIT_DENYLIST, AGENT_UNCHANGED_VERDICT (level-keyed; validated)
#   AGENT_MAKER_INSTRUCTIONS
#   DETECT_BRANCH_MATCH (empty = no integration targets), DETECT_BRANCH_MATCH_MODE, DETECT_PRIORITY
#   DETECT_MAX_TARGETS, DETECT_PR_ENABLED, DETECT_PR_DENYLIST, DETECT_PR_BOT_ALLOWLIST, DETECT_PR_NUMBER
#   DETECT_ITEMS - true: one integration:<branch>#<key> candidate per result.items element (single branch, no PR scan)
#   BUDGET_FILE, RUN_LOG_FILE
#   LOOP_SCOPED_HEAD_BRANCH - when set, only scan this integration branch / PR head
#   CI_SWEEPER_WORKFLOW_RUN_ID + CI_SWEEPER_EVENT_HEAD_BRANCH - workflow_run scope fallback
#   GITHUB_TOKEN
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
STATE_BRANCH="${STATE_BRANCH-}"
DETECT_SCRIPT="${DETECT_SCRIPT-}"
# KEY=VALUE entries from detect_env_json, filled by loop_build_detect_env_args (detect_env.sh).
LOOP_DETECT_ENV_ARGS=()
STATE_FILE="${STATE_FILE-}"

#######################################
# record_skip_detail: Keep the first skip detail of the run for the run log
#
# Globals:
#   SKIP_DETAIL - Set when empty
#
# Arguments:
#   $1 - Detail text (one line is built from it)
#
# Outputs:
#   None
#
# Returns:
#   0 always
#
#######################################
function record_skip_detail {
    if [[ -z ${SKIP_DETAIL:-} ]]; then
        SKIP_DETAIL="$(admission_skip_detail "${1:-}")"
    fi
}

#######################################
# resolve_detect_script_path: Pin DETECT_SCRIPT to an absolute path
#
# Must run before any target checkout. Relative detect scripts otherwise resolve
# against the watched branch worktree (stale PR heads can ship older detect logic).
#
# Globals:
#   DETECT_SCRIPT - Updated in place to an absolute path; empty is left empty (built-in range detect)
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
        log_detect_notice "detect-script" "builtin" "range detect (detect_script omitted)"
        return 0
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
# apply_scoped_pr_number_filter: Keep only the named PR; drop integration watch
#
# Human comment loops (github-pr-revise) must not fan out to main or other PRs.
# Empty number is a no-op so schedule loops are unchanged.
#
# Globals:
#   INTEGRATION_BRANCHES, OPEN_PRS_JSON - Filtered in place
#
# Arguments:
#   $1 - Pull request number (empty = no-op)
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function apply_scoped_pr_number_filter {
    local scoped_pr="$1"
    local -a kept_prs=()
    local pr_json number

    if [[ -z ${scoped_pr} ]] || [[ ${scoped_pr} == "0" ]]; then
        return 0
    fi

    INTEGRATION_BRANCHES=()

    for pr_json in "${OPEN_PRS_JSON[@]+"${OPEN_PRS_JSON[@]}"}"; do
        number="$(jq -r '.number // empty' <<< "${pr_json}")"
        if [[ ${number} == "${scoped_pr}" ]]; then
            kept_prs+=("${pr_json}")
        fi
    done
    OPEN_PRS_JSON=()
    if [[ ${#kept_prs[@]} -gt 0 ]]; then
        OPEN_PRS_JSON=("${kept_prs[@]}")
    fi

    log_detect_notice "scoped-pr" "${scoped_pr}" \
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

    jq -nc \
        --arg mode "integration" \
        --arg key "${target_key}" \
        --arg from_branch "${branch}" \
        --arg from_ref "${current_sha}" \
        --arg to_branch "${branch}" \
        '{
            mode: $mode,
            key: $key,
            from: {branch: $from_branch, ref: $from_ref},
            to: {branch: $to_branch}
        }'
}

#######################################
# build_item_target_json: Build integration target JSON for one result.items element
#
# Globals:
#   None
#
# Arguments:
#   $1 - Item target key (integration:<branch>#<key>)
#   $2 - branch name
#   $3 - current SHA
#   $4 - Entity JSON ({kind, number}; "null" or empty to omit)
#
# Outputs:
#   Target JSON to stdout
#
# Returns:
#   0 on success
#
#######################################
function build_item_target_json {
    local target_key="$1"
    local branch="$2"
    local current_sha="$3"
    local entity_json="${4:-null}"

    build_integration_target_json "${target_key}" "${branch}" "${current_sha}" \
        | jq -c --argjson entity "${entity_json:-null}" 'if $entity == null then . else .entity = $entity end'
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
#   $4 - PR number
#   $5 - base branch
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
    local pr_number="$4"
    local base_branch="$5"

    jq -nc \
        --arg mode "pull_request" \
        --arg key "${target_key}" \
        --arg from_branch "${head_branch}" \
        --arg from_ref "${current_sha}" \
        --arg to_branch "${head_branch}" \
        --argjson pr_number "${pr_number}" \
        --arg base_branch "${base_branch}" \
        '{
            mode: $mode,
            key: $key,
            from: {branch: $from_branch, ref: $from_ref},
            to: {branch: $to_branch, pr_number: $pr_number},
            base: {branch: $base_branch}
        }'
}

#######################################
# append_detect_candidate: Shared detect/checkout/circuit/pending candidate pipeline
# Order: checkout -> target state gate -> detect script -> assemble_detect_candidate.
#
# Globals:
#   CANDIDATES_JSON - Candidate JSON strings appended on success
#   CIRCUIT_BREAKER_BLOCKED - Incremented when circuit breaker is open
#   PENDING_PR_BLOCKED - Incremented when pending PR blocks detect
#   STATE_FILE - Loop state JSON path
#   STATE_BRANCH - State branch; exported to the detect script as STATE_BRANCH
#   DETECT_SCRIPT - Detect script path
#   AGENT_MAKER_SKILL_NAME, LEVEL, AGENT_EDIT_ALLOWLIST, AGENT_EDIT_TARGET, AGENT_MAKER_INSTRUCTIONS - Prompt inputs
#
# Arguments:
#   $1 - Target key
#   $2 - Head branch name
#   $3 - Optional checkout ref (empty string to omit)
#   $4 - Optional accept-log extra text
#   $5 - Target JSON builder function name
#   $6+ - Extra args forwarded to the builder after common args
#
# Outputs:
#   Warning/notice annotations via helper loggers
#
# Returns:
#   None (returns early on checkout/circuit/pending/skip failures; exits detect phase on detect-script failure)
#
#######################################
function append_detect_candidate {
    local target_key="$1"
    local head_branch="$2"
    local checkout_ref="${3:-}"
    local accept_log_extra="${4:-}"
    local target_json_builder="$5"
    shift 5
    local builder_args=("$@")
    local target_state last_sha current_sha detect_result verifier_context consecutive
    local verify_reachable=""

    if [[ -n $checkout_ref ]]; then
        checkout_context "${head_branch}" "${checkout_ref}" || return 0
    else
        checkout_context "${head_branch}" || return 0
    fi

    target_state="$(target_state_apply_merged_pending "$(read_target_state "${STATE_FILE}" "${target_key}" "${STATE_BRANCH}")")"
    consecutive="$(target_consecutive_failures "${target_state}")"
    if target_state_blocks_candidate "${target_key}" "${target_state}" "${consecutive}"; then
        return 0
    fi

    # Only the built-in range detect needs a reachable last_sha; custom detect scripts keep theirs.
    [[ -z ${DETECT_SCRIPT} ]] && verify_reachable="true"
    last_sha="$(target_last_sha "${target_state}" "${head_branch}" "${verify_reachable}")"
    current_sha="$(git rev-parse HEAD)"
    export CI_SWEEPER_HEAD_BRANCH="${head_branch}"
    export STATE_BRANCH
    detect_result="$(invoke_detect_script "${last_sha}" "${target_key}")"

    if detect_result_skip "${detect_result}"; then
        record_skip_detail "${target_key}: $(jq -r '.message // "detect skip=true"' <<< "${detect_result}")"
        log_detect_notice "skip" "${target_key}" \
            "detect skip=true failures=$(jq -r '.failures|length // 0' <<< "${detect_result}") ignored=$(jq -r '.ignored|length // 0' <<< "${detect_result}") ignored_reasons=$(jq -r '[.ignored[]?.reason // empty] | join("; ")' <<< "${detect_result}")"
        return 0
    fi

    if gate_blocks_candidate "${target_key}" "$(jq -c '.result.gate // null' <<< "${detect_result}")" "${target_state}"; then
        return 0
    fi

    verifier_context="$(build_verifier_context_from_result "${detect_result}")"
    assemble_detect_candidate \
        "${target_key}" "${head_branch}" "${current_sha}" "${last_sha}" "${target_state}" "${consecutive}" \
        "${detect_result}" "${verifier_context}" "${accept_log_extra}" "${target_json_builder}" "${builder_args[@]}"
}

#######################################
# append_integration_candidate: Scan one integration branch
#
# Globals:
#   None
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
        "" \
        build_integration_target_json \
        "${branch}"
}

#######################################
# append_items_candidates: Scan one integration branch in items mode (one candidate per result.items element)
# Order: checkout -> detect script -> extract_items -> per-item state gate -> order by last_run
# -> assemble_detect_candidate per item. The branch key integration:<branch> is never read.
#
# Globals:
#   CANDIDATES_JSON - Candidate JSON strings appended per unblocked item
#   CIRCUIT_BREAKER_BLOCKED, PENDING_PR_BLOCKED - Incremented per blocked item
#   STATE_FILE, STATE_BRANCH, DETECT_SCRIPT - Read
#
# Arguments:
#   $1 - Integration branch name
#
# Outputs:
#   Warning/notice annotations; ::error:: on stderr when the detect result is not a valid items result
#
# Returns:
#   0 on success or skip (including checkout failure); 1 when result.items is missing, invalid, or has
#   duplicate keys; the detect script exit status when it fails (main then fails the job)
#
#######################################
function append_items_candidates {
    local branch="$1"
    local detect_result items_json item_json key item_key item_state consecutive last_sha current_sha
    local item_result verifier_context entity_json
    local unblocked_json='[]'

    checkout_context "${branch}" || return 0

    # The branch key is not used in items mode: the detect script gets the HEAD~10 fallback range.
    last_sha="$(target_last_sha '{}' "${branch}" "")"
    current_sha="$(git rev-parse HEAD)"
    export CI_SWEEPER_HEAD_BRANCH="${branch}"
    export STATE_BRANCH
    detect_result="$(invoke_detect_script "${last_sha}" "integration:${branch}")" || return

    if detect_result_skip "${detect_result}"; then
        record_skip_detail "integration:${branch}: $(jq -r '.message // "detect skip=true"' <<< "${detect_result}")"
        log_detect_notice "skip" "integration:${branch}" "detect skip=true (items mode)"
        return 0
    fi

    items_json="$(extract_items "$(jq -c '.result // {}' <<< "${detect_result}")")" || return 1
    if [[ -z ${items_json} ]]; then
        log_detect_error "detect_items is true but the detect result has no result.items (branch=${branch})"
        return 1
    fi
    if [[ "$(jq 'length' <<< "${items_json}")" -eq 0 ]]; then
        log_detect_notice "skip" "integration:${branch}" "result.items is empty (items mode)"
        return 0
    fi

    while IFS= read -r item_json; do
        key="$(jq -r '.key' <<< "${item_json}")"
        item_key="$(item_target_key "${branch}" "${key}")"
        item_state="$(target_state_apply_merged_pending "$(read_target_state "${STATE_FILE}" "${item_key}" "${STATE_BRANCH}")")"
        consecutive="$(target_consecutive_failures "${item_state}")"
        if target_state_blocks_candidate "${item_key}" "${item_state}" "${consecutive}"; then
            continue
        fi
        if gate_blocks_candidate "${item_key}" "$(jq -c '.gate // null' <<< "${item_json}")" "${item_state}"; then
            continue
        fi
        unblocked_json="$(jq -c --argjson item "${item_json}" '. + [$item]' <<< "${unblocked_json}")"
    done < <(jq -c '.[]' <<< "${items_json}")

    unblocked_json="$(order_items_by_last_run "${STATE_FILE}" "${branch}" "${unblocked_json}")" || return 1

    while IFS= read -r item_json; do
        key="$(jq -r '.key' <<< "${item_json}")"
        item_key="$(item_target_key "${branch}" "${key}")"
        item_state="$(target_state_apply_merged_pending "$(read_target_state "${STATE_FILE}" "${item_key}" "${STATE_BRANCH}")")"
        consecutive="$(target_consecutive_failures "${item_state}")"
        last_sha="$(target_last_sha "${item_state}" "${branch}" "")"
        item_result="$(item_result_json "${item_json}")" || return 1
        verifier_context="$(jq -r '.verifier_context // "" | strings' <<< "${item_json}")"
        if [[ -z ${verifier_context} ]]; then
            verifier_context="$(build_verifier_context_from_result "$(jq -c '.context // {}' <<< "${item_json}")")"
        fi
        entity_json="$(jq -c '.entity | if type == "object" then {kind, number} | with_entries(select(.value != null)) else null end' <<< "${item_json}")"
        assemble_detect_candidate \
            "${item_key}" "${branch}" "${current_sha}" "${last_sha}" "${item_state}" "${consecutive}" \
            "${item_result}" "${verifier_context}" "" build_item_target_json "${entity_json}"
    done < <(jq -c '.[]' <<< "${unblocked_json}")
}

#######################################
# append_pull_request_candidate: Scan one open pull request head
#
# Globals:
#   None
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
        "head=${head_branch}" \
        build_pull_request_target_json \
        "${pr_number}" \
        "${base_branch}"
}

#######################################
# apply_target_cap: Cap candidates at DETECT_MAX_TARGETS
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
# assemble_detect_candidate: Build one candidate from a detect result and append it
#
# Globals:
#   CANDIDATES_JSON - Candidate JSON strings appended on success
#   AGENT_MAKER_SKILL_NAME, LEVEL, AGENT_EDIT_ALLOWLIST, AGENT_EDIT_TARGET, AGENT_MAKER_INSTRUCTIONS - Prompt inputs
#
# Arguments:
#   $1 - Target key
#   $2 - Head branch name
#   $3 - Current SHA
#   $4 - Last SHA (prompt Last SHA and integration from.since)
#   $5 - Target state JSON (open rejections)
#   $6 - Consecutive failure count
#   $7 - Detect result JSON stored as the candidate result
#   $8 - Verifier context markdown
#   $9 - Optional accept-log extra text
#   $10 - Target JSON builder function name
#   $11+ - Extra args forwarded to the builder after common args
#
# Outputs:
#   Notice annotations via helper loggers
#
# Returns:
#   0 (a candidate that fails assembly is dropped)
#
#######################################
function assemble_detect_candidate {
    local target_key="$1"
    local head_branch="$2"
    local current_sha="$3"
    local last_sha="$4"
    local target_state="$5"
    local consecutive="$6"
    local detect_result="$7"
    local verifier_context="$8"
    local accept_log_extra="${9:-}"
    local target_json_builder="${10}"
    shift 10
    local builder_args=("$@")
    local prompt_text open_prompt target_json candidate

    open_prompt="$(target_open_rejections_prompt "${target_state}")"

    target_json="$("${target_json_builder}" "${target_key}" "${head_branch}" "${current_sha}" "${builder_args[@]}")"
    target_json="$(jq -c --arg since "${last_sha}" 'if .mode == "integration" then .from.since = $since else . end' <<< "${target_json}")"
    target_json="$(enrich_target_json_with_ci_context "${target_json}" "${detect_result}")"

    prompt_text="$(build_prompt_text \
        "${AGENT_MAKER_SKILL_NAME}" "${LEVEL}" "${AGENT_EDIT_ALLOWLIST:-}" "${AGENT_MAKER_INSTRUCTIONS:-}" \
        "${last_sha}" "${current_sha}" "${detect_result}" "${open_prompt}" "${consecutive}" \
        "${AGENT_EDIT_TARGET:-}" "")"

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
# build_loop_candidate_json: Assemble one matrix cell from detect payloads
#
# Globals:
#   None
#
# Arguments:
#   $1 - Target key (for logs)
#   $2 - target_json object string
#   $3 - Prompt text
#   $4 - Checker context markdown
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
        printf '%s' "${target_json}"
        return 0
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
# invoke_detect_script: Run DETECT_SCRIPT; fatal failures exit the detect phase
#
# Globals:
#   DETECT_SCRIPT - Detect script path; empty runs the built-in range_detect
#   STATE_FILE, RUN_LOG_FILE - Excluded from the built-in range detect
#
# Arguments:
#   $1 - since ref for --scope range
#   $2 - target key for error context (optional)
#
# Outputs:
#   Detect JSON on stdout when successful; on failure, detect stdout echoed to stderr then exit
#
# Returns:
#   0 on success; on failure logs context, echoes detect stdout to stderr, then exit (never continues)
#
#######################################
function invoke_detect_script {
    local last_sha="$1"
    local target_key="${2:-}"
    local detect_status=0
    local detect_result

    if [[ -z ${DETECT_SCRIPT} ]]; then
        detect_result="$(range_detect "${last_sha}" "$(git rev-parse HEAD)" "${STATE_FILE}" "${RUN_LOG_FILE:-}")" || detect_status=$?
    else
        detect_result="$(env "${LOOP_DETECT_ENV_ARGS[@]}" bash "${DETECT_SCRIPT}" --scope range --since "${last_sha}")" || detect_status=$?
    fi
    # set -e: without ||, a non-zero detect exit aborts before we can log context or echo stdout to stderr.

    if [[ ${detect_status} -ne 0 ]]; then
        if [[ -n ${target_key} ]]; then
            log_detect_error "detect script failed target=${target_key} script=${DETECT_SCRIPT} since=${last_sha}"
        else
            log_detect_error "detect script failed script=${DETECT_SCRIPT} since=${last_sha}"
        fi
        if [[ -n ${detect_result} ]]; then
            printf '%s\n' "${detect_result}" >&2
        fi
        exit "${detect_status}"
    fi

    printf '%s' "${detect_result}"
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
# gate_blocks_candidate: Return 0 when the admission gate refuses the facts of a detect result
#
# Description:
#   A detect result without a gate is not evaluated. A refusal is counted per candidate and the
#   first refusal reason becomes the skip_reason when no candidate remains.
#
# Globals:
#   GATE_BLOCKED - Incremented on a refusal
#   GATE_BLOCK_REASON - Set to the first refusal reason
#
# Arguments:
#   $1 - Target key (for the log line)
#   $2 - Gate JSON (the detect result gate object; empty or null for none)
#   $3 - Target state JSON
#
# Outputs:
#   ::notice:: line on a refusal
#
# Returns:
#   0 when the gate refuses, 1 when it admits or there is no gate
#
#######################################
function gate_blocks_candidate {
    local target_key="$1"
    local gate_json="${2:-}"
    local target_state="${3:-}"
    local verdict reason detail

    if [[ -z ${gate_json} || ${gate_json} == "null" ]]; then
        return 1
    fi
    verdict="$(admission_evaluate "${gate_json}" "${target_state}")"
    if [[ $(jq -r '.admit' <<< "${verdict}") == "true" ]]; then
        return 1
    fi
    reason="$(jq -r '.skip_reason' <<< "${verdict}")"
    detail="$(jq -r '.detail' <<< "${verdict}")"
    echo "::notice::admission refused ${target_key}: ${reason} (${detail})"
    GATE_BLOCKED=$((GATE_BLOCKED + 1))
    if [[ -z ${GATE_BLOCK_REASON} ]]; then
        GATE_BLOCK_REASON="${reason}"
    fi
    record_skip_detail "${target_key}: ${detail}"
    return 0
}

#######################################
# target_state_blocks_candidate: Return 0 when circuit breaker or pending PR blocks a target
#
# Globals:
#   CIRCUIT_BREAKER_BLOCKED - Incremented when circuit breaker is open
#   PENDING_PR_BLOCKED - Incremented when pending PR blocks detect
#
# Arguments:
#   $1 - Target key (for warnings)
#   $2 - Target state JSON
#   $3 - Consecutive failure count
#
# Outputs:
#   Warning annotations on stdout
#
# Returns:
#   0 when the target is blocked, 1 otherwise
#
#######################################
function target_state_blocks_candidate {
    local target_key="$1"
    local target_state="$2"
    local consecutive="$3"
    local pending_pr

    if admission_circuit_breaker_open "${consecutive}" "$(jq -r '.last_run // empty' <<< "${target_state}")"; then
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
    return 1
}

#######################################
# validate_branch_match: Return 0 when DETECT_BRANCH_MATCH_MODE is valid
#
# Globals:
#   DETECT_BRANCH_MATCH_MODE - Match mode under validation
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
    case "${DETECT_BRANCH_MATCH_MODE}" in
        list | glob | regex) return 0 ;;
        *)
            echo "::error::Invalid DETECT_BRANCH_MATCH_MODE: ${DETECT_BRANCH_MATCH_MODE}"
            return 1
            ;;
    esac
}

#######################################
# validate_candidate_targets: Fail when a candidate target kind is not allowed by delivery
#
# Globals:
#   CANDIDATES_JSON - Candidate JSON strings (read)
#   DELIVERY - Declared delivery (read)
#
# Arguments:
#   None
#
# Outputs:
#   Error annotation on stderr for the first rejected target
#
# Returns:
#   0 when every target is allowed; 1 otherwise
#
#######################################
function validate_candidate_targets {
    local candidate target_json

    for candidate in "${CANDIDATES_JSON[@]+"${CANDIDATES_JSON[@]}"}"; do
        target_json="$(jq -c '.target_json' <<< "${candidate}")"
        validate_delivery_target "${DELIVERY}" "${target_json}" || return 1
    done
    return 0
}

#######################################
# validate_detect_inputs: Validate level-keyed inputs and delivery against the detect settings
#
# Globals:
#   LEVEL, DELIVERY - Decision inputs (read; no defaults)
#   AGENT_EDIT_TARGET, AGENT_EDIT_ALLOWLIST, AGENT_EDIT_DENYLIST, AGENT_UNCHANGED_VERDICT - Read
#   AGENT_ENGINE, AGENT_TOOL_DENYLIST - Read (optional; denylist needs L2/L3 and claude)
#   FINALIZE_SCRIPT, FINALIZE_LABEL_ALLOWLIST, FINALIZE_ISSUE_LIMIT - Read (optional)
#   DETECT_PR_ENABLED, DETECT_BRANCH_MATCH, DETECT_BRANCH_MATCH_MODE, DETECT_ITEMS - Read
#
# Arguments:
#   None
#
# Outputs:
#   Error annotation on stderr for the first invalid input
#
# Returns:
#   0 when valid; 1 when invalid
#
#######################################
function validate_detect_inputs {
    validate_loop_write_contract \
        "${LEVEL:-}" "${DELIVERY:-}" "${AGENT_EDIT_TARGET:-}" \
        "${AGENT_EDIT_ALLOWLIST:-}" "${AGENT_EDIT_DENYLIST:-}" "${AGENT_UNCHANGED_VERDICT:-}" \
        "${FINALIZE_SCRIPT:-}" "${FINALIZE_LABEL_ALLOWLIST:-}" || return 1
    validate_finalize_issue_limit "${DELIVERY:-}" "${FINALIZE_ISSUE_LIMIT:-}" || return 1
    validate_agent_tool_denylist "${LEVEL:-}" "${AGENT_ENGINE:-}" "${AGENT_TOOL_DENYLIST:-}" || return 1
    validate_delivery_value "${DELIVERY:-}" || return 1
    validate_delivery_detect_config "${DELIVERY:-}" "${DETECT_PR_ENABLED:-}" "${DETECT_BRANCH_MATCH:-}" || return 1
    validate_detect_items_config || return 1
    return 0
}

#######################################
# validate_detect_items_config: Validate the detect_items preconditions
# Items mode needs exactly one literal integration branch (list or glob mode, no comma,
# newline, or pattern characters) and no PR head scan, so the detect script runs once.
#
# Globals:
#   DETECT_ITEMS, DETECT_BRANCH_MATCH, DETECT_BRANCH_MATCH_MODE, DETECT_PR_ENABLED, DETECT_SCRIPT - Read
#
# Arguments:
#   None
#
# Outputs:
#   Error annotation on stderr when invalid
#
# Returns:
#   0 when valid or items mode is off; 1 when invalid
#
#######################################
function validate_detect_items_config {
    local branch_match="${DETECT_BRANCH_MATCH:-}"
    local trimmed

    case "${DETECT_ITEMS:-}" in
        "" | false) return 0 ;;
        true) ;;
        *)
            echo "::error::detect_items must be true or false (got: ${DETECT_ITEMS})" >&2
            return 1
            ;;
    esac

    if [[ -z ${DETECT_SCRIPT:-} ]]; then
        echo "::error::detect_items true requires detect_script (the built-in range detect never emits result.items)" >&2
        return 1
    fi
    if [[ ${DETECT_PR_ENABLED:-} == "true" ]]; then
        echo "::error::detect_items true requires detect_pr_enabled false" >&2
        return 1
    fi
    if [[ ${DETECT_BRANCH_MATCH_MODE:-} != "list" && ${DETECT_BRANCH_MATCH_MODE:-} != "glob" ]]; then
        echo "::error::detect_items true requires detect_branch_match_mode list or glob (got: ${DETECT_BRANCH_MATCH_MODE:-})" >&2
        return 1
    fi
    trimmed="${branch_match#"${branch_match%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ ! ${trimmed} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "::error::detect_items true requires detect_branch_match to name exactly one branch (got: ${branch_match})" >&2
        return 1
    fi
    return 0
}

#######################################
# write_empty_candidates_outputs: Emit skip outputs when no candidates remain
#
# Globals:
#   CHECKOUT_FAILED - Checkout failure count
#   CIRCUIT_BREAKER_BLOCKED - Circuit breaker block count
#   PENDING_PR_BLOCKED - Pending PR block count
#   GATE_BLOCKED, GATE_BLOCK_REASON - Admission gate refusal count and first reason
#   SKIP_DETAIL - First skip detail (published with a skip)
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
    elif [[ ${GATE_BLOCKED} -gt 0 ]]; then
        write_detect_outputs "false" "${GATE_BLOCK_REASON}" "[]"
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
#   GITHUB_OUTPUT, STATE_FILE, STATE_BRANCH
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
    target_state="$(read_target_state "${STATE_FILE}" "${target_key}" "${STATE_BRANCH}")"
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
#   DETECT_ITEMS - true routes integration branches through append_items_candidates
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success or skip; 1 when input or target validation fails, or items mode
#   gets a missing or invalid result.items
#
#######################################
function main {
    : "${STATE_FILE:?}"
    : "${LOOP_NAME:?}"
    : "${STATE_BRANCH:?}"
    : "${AGENT_MAKER_SKILL_NAME:?}"

    # A configuration error fails the job instead of skipping (no outputs written).
    if ! validate_detect_inputs; then
        return 1
    fi
    # shellcheck source=../../lib/loop/detect_env.sh disable=SC1091
    source "${SCRIPT_DIR}/../../lib/loop/detect_env.sh"
    if ! loop_build_detect_env_args "${DETECT_ENV_JSON:-}"; then
        return 1
    fi

    # 0 is the workflow_call sentinel for "no PR number".
    if [[ ${DETECT_PR_NUMBER:-} == "0" ]]; then
        DETECT_PR_NUMBER=""
    fi
    if delivery_requires_pr_number_skip "${DELIVERY}" "${DETECT_PR_NUMBER:-}"; then
        log_detect_notice "skip" "${LOOP_NAME}" "delivery=pr_push without detect_pr_number"
        write_detect_outputs "false" "pr_number_missing" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

    local should_run="false"
    local skip_reason="none"
    local target_matrix_json="[]"
    local branch pr_json github_token="${GITHUB_TOKEN:-}"
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
    migrate_state_targets "${STATE_FILE}" "${STATE_BRANCH}"

    if ! validate_branch_match; then
        write_detect_outputs "false" "config_error" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

    if admission_budget_exceeded "${LOOP_NAME}" "${BUDGET_FILE:-.loop/loop-budget.json}" "${RUN_LOG_FILE:-.loop/loop-run-log.md}" \
        "${BUDGET_MAX_RUNS_PER_DAY:-}" "${BUDGET_MAX_TOKENS_PER_DAY:-}"; then
        write_detect_outputs "false" "budget" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

    resolve_integration_branches "${DETECT_BRANCH_MATCH:-}"
    list_open_prs "${DETECT_PR_DENYLIST}" "${DETECT_PR_BOT_ALLOWLIST}" "${github_token}" || {
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
    apply_scoped_pr_number_filter "${DETECT_PR_NUMBER:-}"

    if [[ ${#INTEGRATION_BRANCHES[@]} -eq 0 && ${#OPEN_PRS_JSON[@]} -eq 0 ]]; then
        write_detect_outputs "false" "no_changes" "[]"
        write_legacy_outputs "[]"
        return 0
    fi

    for branch in "${INTEGRATION_BRANCHES[@]}"; do
        if [[ ${DETECT_ITEMS} == "true" ]]; then
            # A missing or invalid result.items fails the job (items mode was declared).
            append_items_candidates "${branch}" || return 1
        else
            append_integration_candidate "${branch}"
        fi
    done

    for pr_json in "${OPEN_PRS_JSON[@]}"; do
        append_pull_request_candidate "${pr_json}"
    done

    if [[ ${#CANDIDATES_JSON[@]} -eq 0 ]]; then
        write_empty_candidates_outputs
        return 0
    fi

    if ! validate_candidate_targets; then
        return 1
    fi

    sort_candidates_by_priority

    pre_cap_count=${#CANDIDATES_JSON[@]}
    apply_target_cap "${DETECT_MAX_TARGETS}"
    if [[ ${pre_cap_count} -gt ${DETECT_MAX_TARGETS} ]]; then
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
        "should_run=true count=${#CANDIDATES_JSON[@]} keys=$(jq -r '[.[].target_json.key] | join(",")' <<< "${target_matrix_json}") skip_reason=${skip_reason} delivery=${DELIVERY} detect_pr_enabled=${DETECT_PR_ENABLED} detect_max_targets=${DETECT_MAX_TARGETS} handoff_dir=${handoff_dir}"

    write_detect_outputs "${should_run}" "${skip_reason}" "${target_matrix_json}"
    write_legacy_outputs "${full_matrix_json}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
