#!/bin/bash
#######################################
# Description:
#   Append loop run log entry and commit/push to base branch.
#   Environment variables mirror loop-run-log composite action inputs.
#
# Usage:
#   LOOP_NAME=... OUTCOME=... TOKEN=... bash lib/run.sh
#
# Design Rules:
#   - Sources append.sh for JSONL build, prune, and push helpers
#   - tokens_estimate is always recorded; usage object is optional measured data
#
# Output:
#   Appends one JSONL line to RUN_LOG_FILE; optional entry_json on GITHUB_OUTPUT
#
# Dependencies:
#   - bash, git, jq, gh, openssl
#   - append.sh in the same directory
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./append.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/append.sh"

#######################################
# Global variables
#######################################
ATTEMPTS="${ATTEMPTS:-}"
BASE_BRANCH="${BASE_BRANCH:-}"
DURATION_S_INPUT="${DURATION_S_INPUT:-}"
HAS_CHANGES="${HAS_CHANGES:-}"
LOOP_NAME="${LOOP_NAME:-}"
OUTCOME="${OUTCOME:-}"
RUN_LOG_FILE="${RUN_LOG_FILE:-.loop/loop-run-log.md}"
RUN_STARTED_AT="${RUN_STARTED_AT:-}"
SKIP_REASON="${SKIP_REASON:-none}"
TOKEN="${TOKEN:-}"
TOKENS_ESTIMATE="${TOKENS_ESTIMATE:-52000}"
USAGE_JSON="${USAGE_JSON:-}"
VERDICT="${VERDICT:-}"
WORKFLOW_RUN="${WORKFLOW_RUN:-}"

#######################################
# append_run_log_entry: Build JSON entry and append to run log file
#
# Arguments:
#   $1 - Duration in seconds
#
# Global Variables:
#   RUN_LOG_FILE - Target run log path
#   ATTEMPTS, HAS_CHANGES, LOOP_NAME, OUTCOME, SKIP_REASON, TOKENS_ESTIMATE
#   VERDICT, WORKFLOW_RUN, USAGE_JSON - Entry fields
#
# Returns:
#   Entry JSON on stdout
#
#######################################
function append_run_log_entry {
    local duration_s="$1"
    local entry_json

    entry_json="$(loop_run_log_build_entry \
        "${ATTEMPTS}" \
        "${duration_s}" \
        "${HAS_CHANGES}" \
        "${LOOP_NAME}" \
        "${OUTCOME}" \
        "${SKIP_REASON}" \
        "${TOKENS_ESTIMATE}" \
        "${VERDICT}" \
        "${WORKFLOW_RUN}" \
        "${USAGE_JSON}")"
    loop_run_log_append_entry "${RUN_LOG_FILE}" "${entry_json}"
    printf '%s' "${entry_json}"
}

#######################################
# resolve_duration_s: Resolve run duration from explicit input or start time
#
# Arguments:
#   None
#
# Global Variables:
#   DURATION_S_INPUT - Optional explicit duration
#   RUN_STARTED_AT - Optional ISO start timestamp
#
# Returns:
#   Duration seconds on stdout
#
#######################################
function resolve_duration_s {
    if [[ -n ${DURATION_S_INPUT} ]]; then
        printf '%s' "${DURATION_S_INPUT}"
        return 0
    fi
    loop_run_log_compute_duration "${RUN_STARTED_AT}"
}

#######################################
# validate_required_inputs: Validate required loop-run-log environment
#
# Arguments:
#   None
#
# Global Variables:
#   LOOP_NAME - Required loop identifier
#   OUTCOME - Required run outcome
#   TOKEN - Required GitHub token for push
#
# Returns:
#   Exits 1 when required input is missing
#
#######################################
function validate_required_inputs {
    : "${LOOP_NAME:?}"
    : "${OUTCOME:?}"
    : "${TOKEN:?}"
}

#######################################
# write_entry_json_output: Write entry_json multiline output when GITHUB_OUTPUT is set
#
# Arguments:
#   $1 - JSON entry string
#
# Global Variables:
#   GITHUB_OUTPUT - Optional GitHub Actions output file path
#
# Returns:
#   None
#
#######################################
function write_entry_json_output {
    local entry_json="$1"
    local delim

    if [[ -z ${GITHUB_OUTPUT:-} ]]; then
        return 0
    fi

    delim="ENTRY_JSON_$(openssl rand -hex 8)"
    {
        echo "entry_json<<${delim}"
        echo "${entry_json}"
        echo "${delim}"
    } >> "${GITHUB_OUTPUT}"
}

#######################################
# main: Append run log entry and push to base branch
#
# Arguments:
#   None
#
# Global Variables:
#   BASE_BRANCH - Branch for commit and PR fallback
#
# Returns:
#   Exits with script status
#
#######################################
function main {
    local duration_s entry_json

    validate_required_inputs
    duration_s="$(resolve_duration_s)"
    entry_json="$(append_run_log_entry "${duration_s}")"
    loop_run_log_commit_and_push "${BASE_BRANCH}" "${RUN_LOG_FILE}" "${TOKEN}"
    write_entry_json_output "${entry_json}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
