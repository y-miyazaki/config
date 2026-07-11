#!/bin/bash
#######################################
# Description: Detect failed CI workflow runs and emit structured findings for loop-ci-sweeper
#
# Usage: ./detect_ci_failures.sh [--scope staged|all|range] [--since <ref>]
#   --scope    Change detection scope (default: range)
#              range: consider failures since <ref> (requires --since)
#   --since    Git ref for range scope (commit SHA from loop state)
#
# Output:
# - JSON object with failures[] and skip boolean
#
# Design Rules:
# - Collect failures via gh API (run list/view) filtered by since ref and ledger
# - Return structured JSON via shared lib/json.sh
# - Exit 0 always (errors reported in JSON status field)
# - Skip runs per CI_SWEEPER_REJECT_RETRY_POLICY and ledger state
# - Source shared helpers from scripts/lib/all.sh (synced via scripts/ai/sync_skill_lib.sh)
#
# Dependencies:
# - bash (POSIX bash, /bin/bash)
# - git
# - gh
# - jq (gh --json parsing only)
#
# Optional environment:
#   CI_SWEEPER_EXCLUDED_WORKFLOWS     Comma-separated workflow names to ignore
#   CI_SWEEPER_HEAD_BRANCH            workflow_run event context (optional)
#   CI_SWEEPER_HEAD_SHA               workflow_run event context (optional)
#   CI_SWEEPER_INCLUDED_WORKFLOWS     Comma-separated allowlist (empty = all non-excluded)
#   CI_SWEEPER_LEDGER_FILE            Path to run ledger JSON (default: .loop/ci-sweeper-run-ledger.json)
#   CI_SWEEPER_REJECT_MAX_RETRIES     Max REJECT retries when policy is limited (default: 3)
#   CI_SWEEPER_REJECT_RETRY_POLICY    block | retry | limited (aliases a/b/c)
#   CI_SWEEPER_RUN_URL                workflow_run event context (optional)
#   CI_SWEEPER_WORKFLOW_NAME          workflow_run event context (optional)
#   CI_SWEEPER_WORKFLOW_RUN_ID        workflow_run event context (optional)
#   DEFAULT_BASE_BRANCH               Fallback branch when checkout context is unavailable
#   DEFAULT_BRANCH                    Alias for DEFAULT_BASE_BRANCH (legacy)
#   GH_TOKEN / GITHUB_TOKEN           GitHub API token
#   SCAN_BRANCH_RUN_LIMIT             Max failed runs to scan per branch (default: 100)
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# shellcheck source=lib/all.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/all.sh"

#######################################
# Global variables
#######################################
SCOPE="range"
SINCE_REF=""
DEFAULT_BRANCH="${DEFAULT_BASE_BRANCH:-${DEFAULT_BRANCH:-main}}"
LEDGER_FILE="${CI_SWEEPER_LEDGER_FILE:-.loop/ci-sweeper-run-ledger.json}"
SCAN_BRANCH_RUN_LIMIT="${SCAN_BRANCH_RUN_LIMIT:-100}"
REJECT_RETRY_POLICY="${CI_SWEEPER_REJECT_RETRY_POLICY:-block}"
REJECT_MAX_RETRIES="${CI_SWEEPER_REJECT_MAX_RETRIES:-3}"

declare -a EXCLUDED_WORKFLOWS=()
declare -a INCLUDED_WORKFLOWS=()
declare -a FAILURES_JSON=()
declare -a IGNORED_JSON=()

#######################################
# show_usage: Display script usage information
#
# Arguments:
#   None
#
# Returns:
#   Exits with code 0
#
# Usage:
#   show_usage
#
#######################################
function show_usage {
    cat << 'EOF'
Usage: detect_ci_failures.sh [--scope staged|all|range] [--since <ref>]

Description:
    Detect failed CI workflow runs for the ci-sweeper loop.

Options:
    --scope    Change detection scope (default: range)
               staged: not used for CI detection (accepted for loop-detect parity)
               all: scan recent failures on the checked-out branch (or CI_SWEEPER_HEAD_BRANCH)
               range: consider failures since <ref> (requires --since)
    --since    Git ref for range scope (commit SHA from loop state)

Examples:
    ./detect_ci_failures.sh --scope range --since abc1234
    ./detect_ci_failures.sh --scope all
EOF
    exit 0
}

#######################################
# parse_arguments: Parse command line arguments
#
# Arguments:
#   $@ - Command line arguments
#
# Global Variables:
#   SCOPE - Detection scope
#   SINCE_REF - Git ref for range scope
#
# Returns:
#   None (calls output_error on invalid input)
#
# Usage:
#   parse_arguments "$@"
#
#######################################
function parse_arguments {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_usage
                ;;
            --scope)
                if [[ $# -lt 2 ]]; then
                    output_error "--scope requires a value"
                fi
                SCOPE="$2"
                shift 2
                ;;
            --since)
                if [[ $# -lt 2 ]]; then
                    output_error "--since requires a value"
                fi
                SINCE_REF="$2"
                shift 2
                ;;
            *)
                output_error "Unknown argument: $1"
                ;;
        esac
    done

    if [[ ${SCOPE} != "staged" && ${SCOPE} != "all" && ${SCOPE} != "range" ]]; then
        output_error "--scope must be staged, all, or range"
    fi

    if [[ ${SCOPE} == "range" && -z ${SINCE_REF} ]]; then
        output_error "--scope range requires --since <ref>"
    fi
}

#######################################
# split_csv_to_array: Split comma-separated values into a named array
#
# Arguments:
#   $1 - Comma-separated string
#   $2 - Name of target array variable
#
# Returns:
#   None
#
# Usage:
#   split_csv_to_array "${csv}" EXCLUDED_WORKFLOWS
#
#######################################
function split_csv_to_array {
    local csv="$1"
    local -n _target="$2"
    _target=()
    [[ -z ${csv} ]] && return
    local item
    local -a raw=()
    IFS=',' read -r -a raw <<< "${csv}"
    for item in "${raw[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        _target+=("${item}")
    done
}

#######################################
# load_workflow_filters: Load included and excluded workflow filters from environment
#
# Arguments:
#   None
#
# Global Variables:
#   EXCLUDED_WORKFLOWS - Populated excluded workflow names
#   INCLUDED_WORKFLOWS - Populated included workflow names
#
# Returns:
#   None
#
# Usage:
#   load_workflow_filters
#
#######################################
function load_workflow_filters {
    local excluded_csv="${CI_SWEEPER_EXCLUDED_WORKFLOWS:-}"
    local included_csv="${CI_SWEEPER_INCLUDED_WORKFLOWS:-}"
    split_csv_to_array "${excluded_csv}" EXCLUDED_WORKFLOWS
    split_csv_to_array "${included_csv}" INCLUDED_WORKFLOWS
}

#######################################
# output_error: Print structured JSON error and exit
#
# Arguments:
#   $1 - Error message
#
# Returns:
#   Exits with code 0
#
# Usage:
#   output_error "gh CLI is required"
#
#######################################
function output_error {
    local message="$1"
    json_object_start
    json_field_string "status" "error" ","
    json_field_string "scope" "${SCOPE}" ","
    json_field_string "since" "${SINCE_REF}" ","
    json_field_bool "skip" "true" ","
    json_field_array "failures" "[]" ","
    json_field_array "ignored" "[]" ","
    json_field_string "message" "${message}" ""
    json_object_end
    exit 0
}

# validate_ledger_file: Ensure ledger path stays under .loop/
#
# Arguments:
#   $1 - Ledger file path
#
# Returns:
#   Exits via output_error when invalid
#
function validate_ledger_file {
    local path="$1"
    local repo_root resolved ledger_root
    if [[ ${path} != .loop/* ]]; then
        output_error "CI_SWEEPER_LEDGER_FILE must be under .loop/ (got: ${path})"
    fi
    repo_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
    ledger_root="$(realpath -m "${repo_root}/.loop")"
    resolved="$(realpath -m "${repo_root}/${path}")"
    if [[ ${resolved} != "${ledger_root}"/* ]]; then
        output_error "CI_SWEEPER_LEDGER_FILE must stay under .loop/ (got: ${path})"
    fi
}

# scan_branch_name: Resolve branch to scan from checkout context
#
# Arguments:
#   None
#
# Returns:
#   Branch name on stdout
#
function scan_branch_name {
    local branch="${CI_SWEEPER_HEAD_BRANCH:-}"
    if [[ -z ${branch} ]]; then
        branch="$(git rev-parse --abbrev-ref HEAD 2> /dev/null || true)"
    fi
    if [[ -z ${branch} || ${branch} == "HEAD" ]]; then
        branch="${DEFAULT_BRANCH}"
    fi
    printf '%s' "${branch}"
}

#######################################
# is_excluded_workflow: Check whether a workflow name is excluded
#
# Arguments:
#   $1 - Workflow display name
#
# Returns:
#   0 if excluded, 1 otherwise
#
# Usage:
#   if is_excluded_workflow "${name}"; then ...
#
#######################################
function is_excluded_workflow {
    local name="$1"
    local excluded
    for excluded in "${EXCLUDED_WORKFLOWS[@]}"; do
        [[ -z ${excluded} ]] && continue
        if [[ ${name} == "${excluded}" ]]; then
            return 0
        fi
    done
    return 1
}

#######################################
# is_included_workflow: Check whether a workflow name passes the allowlist
#
# Arguments:
#   $1 - Workflow display name
#
# Returns:
#   0 if included, 1 otherwise
#
# Usage:
#   if is_included_workflow "${name}"; then ...
#
#######################################
function is_included_workflow {
    local name="$1"
    local included
    if [[ ${#INCLUDED_WORKFLOWS[@]} -eq 0 ]]; then
        return 0
    fi
    for included in "${INCLUDED_WORKFLOWS[@]}"; do
        [[ -z ${included} ]] && continue
        if [[ ${name} == "${included}" ]]; then
            return 0
        fi
    done
    return 1
}

#######################################
# gh_available: Check whether gh and jq are available
#
# Arguments:
#   None
#
# Returns:
#   0 if available, 1 otherwise
#
# Usage:
#   if ! gh_available; then ...
#
#######################################
function gh_available {
    command -v gh > /dev/null 2>&1 && command -v jq > /dev/null 2>&1
}

#######################################
# commit_is_relevant: Check whether a commit is within the since range
#
# Arguments:
#   $1 - Commit SHA
#
# Returns:
#   0 if relevant, 1 otherwise
#
# Usage:
#   if commit_is_relevant "${head_sha}"; then ...
#
#######################################
function commit_is_relevant {
    local head_sha="$1"
    if [[ -z ${SINCE_REF} || -z ${head_sha} ]]; then
        return 0
    fi
    if [[ ${SINCE_REF} == "${head_sha}" ]]; then
        return 0
    fi
    if git merge-base --is-ancestor "${SINCE_REF}" "${head_sha}" 2> /dev/null; then
        return 0
    fi
    return 1
}

#######################################
# ledger_outcome_for_run: Read ledger outcome for a workflow run
#
# Arguments:
#   $1 - Workflow run ID
#
# Returns:
#   Outcome string on stdout, empty when not ledgered
#
# Usage:
#   outcome="$(ledger_outcome_for_run "${run_id}")"
#
#######################################
function ledger_outcome_for_run {
    local run_id="$1"
    if [[ ! -f ${LEDGER_FILE} ]]; then
        return 1
    fi
    jq -r --arg run_id "${run_id}" '.runs[$run_id].outcome // empty' "${LEDGER_FILE}" 2> /dev/null || true
}

#######################################
# ledger_reject_count_for_run: Read reject count for a workflow run
#
# Arguments:
#   $1 - Workflow run ID
#
# Returns:
#   Reject count on stdout
#
# Usage:
#   reject_count="$(ledger_reject_count_for_run "${run_id}")"
#
#######################################
function ledger_reject_count_for_run {
    local run_id="$1"
    if [[ ! -f ${LEDGER_FILE} ]]; then
        printf '0'
        return
    fi
    jq -r --arg run_id "${run_id}" '.runs[$run_id].reject_count // 0' "${LEDGER_FILE}" 2> /dev/null || printf '0'
}

#######################################
# normalize_reject_retry_policy: Normalize policy name and aliases
#
# Arguments:
#   $1 - Policy value
#
# Returns:
#   Normalized policy on stdout
#
# Usage:
#   policy="$(normalize_reject_retry_policy "${REJECT_RETRY_POLICY}")"
#
#######################################
function normalize_reject_retry_policy {
    local policy
    policy="$(printf '%s' "${1:-block}" | tr '[:upper:]' '[:lower:]')"
    case "${policy}" in
        block | retry | limited)
            printf '%s' "${policy}"
            ;;
        a)
            printf 'block'
            ;;
        b)
            printf 'retry'
            ;;
        c)
            printf 'limited'
            ;;
        *)
            printf 'block'
            ;;
    esac
}

#######################################
# should_skip_processed_run: Decide whether a run was already processed per policy
#
# Arguments:
#   $1 - Workflow run ID
#
# Returns:
#   0 if the run should be skipped, 1 otherwise
#
# Usage:
#   if should_skip_processed_run "${run_id}"; then ...
#
#######################################
function should_skip_processed_run {
    local run_id="$1"
    local outcome policy reject_count max_retries
    outcome="$(ledger_outcome_for_run "${run_id}")"
    [[ -z ${outcome} ]] && return 1

    policy="$(normalize_reject_retry_policy "${REJECT_RETRY_POLICY}")"
    case "${policy}" in
        block)
            return 0
            ;;
        retry)
            [[ ${outcome} == "pr-created" ]]
            ;;
        limited)
            if [[ ${outcome} == "pr-created" ]]; then
                return 0
            fi
            if [[ ${outcome} == "rejected" ]]; then
                reject_count="$(ledger_reject_count_for_run "${run_id}")"
                max_retries="${REJECT_MAX_RETRIES}"
                [[ ${reject_count} -ge ${max_retries} ]]
                return $?
            fi
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

#######################################
# classify_failure_type: Classify failure from log excerpt heuristics
#
# Arguments:
#   $1 - Log excerpt
#
# Returns:
#   Failure type on stdout (infra, env, flake, regression)
#
# Usage:
#   failure_type="$(classify_failure_type "${log_excerpt}")"
#
#######################################
function classify_failure_type {
    local log_excerpt="$1"
    if grep -qiE 'timeout|timed out|oom|out of memory|503|502|504|service unavailable|registry|rate limit|waiting for a runner|no runners (available|online|found)|runner (has lost|not found|offline|unavailable)|could not acquire a runner|job was not acquired' <<< "${log_excerpt}"; then
        echo "infra"
    elif grep -qiE '(missing|invalid|not found|cannot find).*(secret|credential|api[_-]?key)|(secret|credential|api[_-]?key).*(missing|invalid|not found)|(AWS_|GITHUB_TOKEN|GH_TOKEN).*(missing|invalid|not set)|permission denied.*/(secrets|credentials)' <<< "${log_excerpt}"; then
        echo "env"
    elif grep -qiE '\b(flake|flaky|intermittent)\b|\b(retries|retrying)\b' <<< "${log_excerpt}"; then
        echo "flake"
    else
        echo "regression"
    fi
}

# sanitize_log_excerpt: Redact likely secrets from CI log text
function sanitize_log_excerpt {
    local excerpt="$1"
    excerpt="$(sed -E 's/gh[pousr]_[A-Za-z0-9_]{20,}/[REDACTED]/g' <<< "${excerpt}")"
    excerpt="$(sed -E 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' <<< "${excerpt}")"
    excerpt="$(sed -E 's/(password|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]\"]+/\1=[REDACTED]/gi' <<< "${excerpt}")"
    excerpt="$(sed -E 's/x-access-token:[A-Za-z0-9._-]+/x-access-token:[REDACTED]/g' <<< "${excerpt}")"
    excerpt="$(sed -E 's/Bearer[[:space:]]+[A-Za-z0-9._-]+/Bearer [REDACTED]/g' <<< "${excerpt}")"
    excerpt="$(sed -E 's/Authorization:[[:space:]]*[^[:space:]\"]+/Authorization: [REDACTED]/gi' <<< "${excerpt}")"
    excerpt="$(sed -E 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED-JWT]/g' <<< "${excerpt}")"
    excerpt="$(sed -E 's/-----BEGIN [A-Z ]+-----[^-]*-----END [A-Z ]+-----/[REDACTED-PEM]/g' <<< "${excerpt}")"
    printf '%s' "${excerpt}"
}

#######################################
# fetch_failed_jobs: Fetch failed jobs for a workflow run
#
# Arguments:
#   $1 - Workflow run ID
#
# Returns:
#   JSON lines for failed jobs on stdout
#
# Usage:
#   fetch_failed_jobs "${run_id}"
#
#######################################
function fetch_failed_jobs {
    local run_id="$1"
    gh run view "${run_id}" --json jobs --jq \
        '.jobs[] | select(.conclusion == "failure") | {name: .name, conclusion: .conclusion, url: .html_url}' \
        2> /dev/null || true
}

#######################################
# fetch_log_excerpt: Fetch truncated failed log excerpt for a job
#
# Arguments:
#   $1 - Workflow run ID
#   $2 - Job name
#
# Returns:
#   Log excerpt on stdout
#
# Usage:
#   log_excerpt="$(fetch_log_excerpt "${run_id}" "${job_name}")"
#
#######################################
function fetch_log_excerpt {
    local run_id="$1"
    local job_name="$2"
    local excerpt
    excerpt="$(gh run view "${run_id}" --log-failed 2> /dev/null | grep -F "${job_name}" | tail -n 80 || true)"
    if [[ -z ${excerpt} ]]; then
        excerpt="$(gh run view "${run_id}" --log-failed 2> /dev/null | tail -n 80 || true)"
    fi
    excerpt="${excerpt:0:4000}"
    excerpt="$(sanitize_log_excerpt "${excerpt}")"
    printf '%s' "${excerpt}"
}

#######################################
# failure_object_json: Build one failure object as JSON
#
# Arguments:
#   $1-$8 - workflow_name, run_id, head_sha, head_branch, run_url, job_name, failure_type, log_excerpt
#
# Returns:
#   JSON object on stdout
#
# Usage:
#   failure_object_json "${workflow_name}" ...
#
#######################################
function failure_object_json {
    local workflow_name="$1"
    local run_id="$2"
    local head_sha="$3"
    local head_branch="$4"
    local run_url="$5"
    local job_name="$6"
    local failure_type="$7"
    local log_excerpt="$8"
    local reason="CI failure in job ${job_name} (${failure_type})"

    cat << EOF
{
  "workflow_name": "$(json_escape "${workflow_name}")",
  "workflow_run_id": "$(json_escape "${run_id}")",
  "head_sha": "$(json_escape "${head_sha}")",
  "head_branch": "$(json_escape "${head_branch}")",
  "job_name": "$(json_escape "${job_name}")",
  "failure_type": "$(json_escape "${failure_type}")",
  "log_excerpt": "$(json_escape "${log_excerpt}")",
  "run_url": "$(json_escape "${run_url}")",
  "source_commit": "$(json_escape "${head_sha}")",
  "reason": "$(json_escape "${reason}")"
}
EOF
}

#######################################
# append_failure: Append one failure object to FAILURES_JSON
#
# Arguments:
#   $1-$8 - workflow_name, run_id, head_sha, head_branch, run_url, job_name, failure_type, log_excerpt
#
# Returns:
#   None
#
# Usage:
#   append_failure "${workflow_name}" ...
#
#######################################
function append_failure {
    local workflow_name="$1"
    local run_id="$2"
    local head_sha="$3"
    local head_branch="$4"
    local run_url="$5"
    local job_name="$6"
    local failure_type="$7"
    local log_excerpt="$8"

    FAILURES_JSON+=("$(failure_object_json "${workflow_name}" "${run_id}" "${head_sha}" "${head_branch}" \
        "${run_url}" "${job_name}" "${failure_type}" "${log_excerpt}")")
}

# ignored_object_json: Build one ignored entry as JSON
#
# Arguments:
#   $1-$6 - workflow_name, run_id, head_branch, job_name, failure_type, reason
#
# Returns:
#   JSON object on stdout
#
function ignored_object_json {
    local workflow_name="$1"
    local run_id="$2"
    local head_branch="$3"
    local job_name="$4"
    local failure_type="$5"
    local reason="$6"

    cat << EOF
{
  "workflow_name": "$(json_escape "${workflow_name}")",
  "workflow_run_id": "$(json_escape "${run_id}")",
  "head_branch": "$(json_escape "${head_branch}")",
  "job_name": "$(json_escape "${job_name}")",
  "failure_type": "$(json_escape "${failure_type}")",
  "reason": "$(json_escape "${reason}")"
}
EOF
}

# append_ignored: Append one ignored entry to IGNORED_JSON
#
# Arguments:
#   $1-$6 - workflow_name, run_id, head_branch, job_name, failure_type, reason
#
# Returns:
#   None
#
function append_ignored {
    local workflow_name="$1"
    local run_id="$2"
    local head_branch="$3"
    local job_name="$4"
    local failure_type="$5"
    local reason="$6"

    IGNORED_JSON+=("$(ignored_object_json "${workflow_name}" "${run_id}" "${head_branch}" \
        "${job_name}" "${failure_type}" "${reason}")")
}

#######################################
# collect_failures_for_run: Collect failures from one workflow run
#
# Arguments:
#   $1-$5 - workflow_name, run_id, head_sha, head_branch, run_url
#
# Returns:
#   None
#
# Usage:
#   collect_failures_for_run "${workflow_name}" ...
#
#######################################
function collect_failures_for_run {
    local workflow_name="$1"
    local run_id="$2"
    local head_sha="$3"
    local head_branch="$4"
    local run_url="$5"
    local ledger_outcome

    if is_excluded_workflow "${workflow_name}" || ! is_included_workflow "${workflow_name}"; then
        append_ignored "${workflow_name}" "${run_id}" "${head_branch}" "-" "-" \
            "excluded workflow filter"
        return 0
    fi

    if should_skip_processed_run "${run_id}"; then
        ledger_outcome="$(ledger_outcome_for_run "${run_id}")"
        append_ignored "${workflow_name}" "${run_id}" "${head_branch}" "-" "-" \
            "ledger: ${ledger_outcome:-processed}"
        return 0
    fi

    if ! commit_is_relevant "${head_sha}"; then
        append_ignored "${workflow_name}" "${run_id}" "${head_branch}" "-" "-" \
            "outside since range"
        return 0
    fi

    local job_line job_name log_excerpt failure_type
    if ! fetch_failed_jobs "${run_id}" | grep -q .; then
        append_failure "${workflow_name}" "${run_id}" "${head_sha}" "${head_branch}" "${run_url}" \
            "unknown" "regression" "Failed workflow run with no failed job metadata."
        return 0
    fi

    while IFS= read -r job_line; do
        [[ -z ${job_line} ]] && continue
        job_name="$(jq -r '.name' <<< "${job_line}")"
        log_excerpt="$(fetch_log_excerpt "${run_id}" "${job_name}")"
        failure_type="$(classify_failure_type "${log_excerpt}")"
        append_failure "${workflow_name}" "${run_id}" "${head_sha}" "${head_branch}" "${run_url}" \
            "${job_name}" "${failure_type}" "${log_excerpt}"
    done < <(fetch_failed_jobs "${run_id}")
}

#######################################
# collect_from_workflow_run_event: Collect failures from workflow_run event env context
#
# Arguments:
#   None
#
# Returns:
#   0 when event context is present, 1 otherwise
#
# Usage:
#   if collect_from_workflow_run_event; then ...
#
#######################################
function collect_from_workflow_run_event {
    local run_id="${CI_SWEEPER_WORKFLOW_RUN_ID:-}"
    local workflow_name="${CI_SWEEPER_WORKFLOW_NAME:-}"
    local head_sha="${CI_SWEEPER_HEAD_SHA:-}"
    local head_branch="${CI_SWEEPER_HEAD_BRANCH:-}"
    local run_url="${CI_SWEEPER_RUN_URL:-}"

    if [[ -z ${run_id} ]]; then
        return 1
    fi

    collect_failures_for_run "${workflow_name}" "${run_id}" "${head_sha}" "${head_branch}" "${run_url}"
}

#######################################
# collect_recent_failures: Collect recent failed runs from the current scan branch
#
# Arguments:
#   None
#
# Returns:
#   None
#
# Usage:
#   collect_recent_failures
#
#######################################
function collect_recent_failures {
    local runs_json run_line run_id workflow_name head_sha head_branch run_url scan_branch
    scan_branch="$(scan_branch_name)"
    runs_json="$(gh run list --branch "${scan_branch}" --status failure --limit "${SCAN_BRANCH_RUN_LIMIT}" --json \
        databaseId,headSha,headBranch,url,workflowName,conclusion 2> /dev/null || echo '[]')"

    while IFS= read -r run_line; do
        [[ -z ${run_line} ]] && continue
        run_id="$(jq -r '.databaseId' <<< "${run_line}")"
        workflow_name="$(jq -r '.workflowName' <<< "${run_line}")"
        head_sha="$(jq -r '.headSha' <<< "${run_line}")"
        head_branch="$(jq -r '.headBranch' <<< "${run_line}")"
        run_url="$(jq -r '.url' <<< "${run_line}")"
        collect_failures_for_run "${workflow_name}" "${run_id}" "${head_sha}" "${head_branch}" "${run_url}"
    done < <(jq -c '.[]' <<< "${runs_json}")
}

#######################################
# failures_array_json: Join failure objects into a JSON array string
#
# Arguments:
#   None
#
# Global Variables:
#   FAILURES_JSON - Source failure objects
#
# Returns:
#   JSON array string on stdout
#
# Usage:
#   failures_array="$(failures_array_json)"
#
#######################################
function failures_array_json {
    local joined=""
    local failure
    if [[ ${#FAILURES_JSON[@]} -eq 0 ]]; then
        printf '%s' "[]"
        return
    fi
    for failure in "${FAILURES_JSON[@]}"; do
        if [[ -n ${joined} ]]; then
            joined+=","
        fi
        joined+="${failure}"
    done
    printf '[%s]' "${joined}"
}

#######################################
# ignored_array_json: Join ignored objects into a JSON array string
#######################################
function ignored_array_json {
    local joined=""
    local ignored
    if [[ ${#IGNORED_JSON[@]} -eq 0 ]]; then
        printf '%s' "[]"
        return
    fi
    for ignored in "${IGNORED_JSON[@]}"; do
        if [[ -n ${joined} ]]; then
            joined+=","
        fi
        joined+="${ignored}"
    done
    printf '[%s]' "${joined}"
}

#######################################
# output_json: Print structured JSON result using lib/json.sh helpers
#
# Arguments:
#   None
#
# Returns:
#   None
#
# Usage:
#   output_json
#
#######################################
function output_json {
    local skip="false"
    local failures_array ignored_array

    if [[ ${#FAILURES_JSON[@]} -eq 0 ]]; then
        skip="true"
    fi

    failures_array="$(failures_array_json)"
    ignored_array="$(ignored_array_json)"

    json_object_start
    json_field_string "status" "ok" ","
    json_field_string "scope" "${SCOPE}" ","
    json_field_string "since" "${SINCE_REF}" ","
    json_field_bool "skip" "${skip}" ","
    json_field_array "failures" "${failures_array}" ","
    json_field_array "ignored" "${ignored_array}" ""
    json_object_end
}

#######################################
# main: Entry point
#
# Arguments:
#   $@ - Command line arguments
#
# Returns:
#   0 always
#
# Usage:
#   main "$@"
#
#######################################
function main {
    parse_arguments "$@"
    validate_ledger_file "${LEDGER_FILE}"
    load_workflow_filters

    if ! gh_available; then
        output_error "gh CLI and jq are required but not installed"
    fi

    if [[ -z ${GH_TOKEN:-} && -z ${GITHUB_TOKEN:-} ]]; then
        output_error "GH_TOKEN or GITHUB_TOKEN is required"
    fi

    export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

    if collect_from_workflow_run_event; then
        :
    else
        collect_recent_failures
    fi

    output_json
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
