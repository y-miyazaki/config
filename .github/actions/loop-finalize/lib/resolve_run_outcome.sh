#!/bin/bash
#######################################
# Description:
#   Resolve the run-log outcome and, when no failure was recorded yet, record the
#   failure stage that explains it. Runs as the last decision step of loop-finalize.
#
# Usage:
#   ACTION_STATUS=success AGENT_RESULT=success DELIVERED_OUTCOME=unchanged \
#   LOOP_FAILURE_FILE=... [AGENT_FAILURE_STAGE=... AGENT_FAILURE_MESSAGE=...] \
#   [GITHUB_OUTPUT=...] bash lib/resolve_run_outcome.sh
#
# Design Rules:
#   - Failure stage precedence: existing finalize record > agent stage and message >
#     agent_execute (agent_result is neither success nor skipped) > finalize
#     (ACTION_STATUS is not success, or the delivered outcome is empty)
#   - Outcome is error when ACTION_STATUS is not success, the delivered outcome is
#     empty, or a failure record exists; otherwise the delivered outcome as is
#   - Outcome is resolved before the agent stage is recorded (a recorded agent stage
#     must not turn a successful run into error)
#   - Records via loop_failure_record only; the export to GITHUB_OUTPUT is done by
#     export_failure_diag.sh (no export here)
#
# Output:
#   Optional GITHUB_OUTPUT key: outcome
#
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../lib/loop/failure_record.sh disable=SC1091
source "${SCRIPT_DIR}/../../lib/loop/failure_record.sh"

#######################################
# Global variables
#######################################
ACTION_STATUS="${ACTION_STATUS:-}"
AGENT_FAILURE_MESSAGE="${AGENT_FAILURE_MESSAGE:-}"
AGENT_FAILURE_STAGE="${AGENT_FAILURE_STAGE:-}"
AGENT_RESULT="${AGENT_RESULT:-}"
DELIVERED_OUTCOME="${DELIVERED_OUTCOME:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"
LOOP_FAILURE_FILE="${LOOP_FAILURE_FILE:-}"


#######################################
# record_run_failure: Record one failure stage unless a record already exists
#
# Globals:
#   None
#
# Arguments:
#   $1 - Failure JSON file path
#   $2 - Agent job result
#   $3 - Agent failure stage
#   $4 - Agent failure message
#   $5 - Composite action status
#   $6 - Delivered outcome
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#######################################
function record_run_failure {
    local failure_file="${1:?failure_file required}"
    local agent_result="${2:-}"
    local agent_stage="${3:-}"
    local agent_message="${4:-}"
    local action_status="${5:-}"
    local delivered_outcome="${6:-}"
    local stage=""

    if loop_failure_recorded "${failure_file}"; then
        return 0
    fi

    if [[ -n ${agent_stage} ]]; then
        stage="${agent_stage}"
    else
        case "${agent_result}" in
            success | skipped) ;;
            *) stage="agent_execute" ;;
        esac
    fi
    if [[ -z ${stage} && (${action_status} != "success" || -z ${delivered_outcome}) ]]; then
        stage="finalize"
    fi

    if [[ -n ${stage} ]]; then
        loop_failure_record "${stage}" "${agent_message}" "${failure_file}"
    fi
    return 0
}

#######################################
# resolve_run_outcome: Print the run-log outcome
#
# Globals:
#   None
#
# Arguments:
#   $1 - Composite action status
#   $2 - Delivered outcome
#   $3 - Failure JSON file path
#
# Outputs:
#   Outcome on stdout
#
# Returns:
#   0 on success
#######################################
function resolve_run_outcome {
    local action_status="${1:-}"
    local delivered_outcome="${2:-}"
    local failure_file="${3:?failure_file required}"

    if [[ ${action_status} != "success" || -z ${delivered_outcome} ]] || loop_failure_recorded "${failure_file}"; then
        echo "error"
    else
        echo "${delivered_outcome}"
    fi
    return 0
}

#######################################
# main: Resolve the outcome, then record the failure stage
#
# Globals:
#   ACTION_STATUS, AGENT_FAILURE_MESSAGE, AGENT_FAILURE_STAGE, AGENT_RESULT,
#   DELIVERED_OUTCOME, GITHUB_OUTPUT, LOOP_FAILURE_FILE
#
# Arguments:
#   None
#
# Outputs:
#   outcome=<value> on GITHUB_OUTPUT when set
#
# Returns:
#   0 on success, 1 when LOOP_FAILURE_FILE is empty
#######################################
function main {
    local outcome

    if [[ -z ${LOOP_FAILURE_FILE} ]]; then
        echo "::error::LOOP_FAILURE_FILE is required" >&2
        return 1
    fi

    outcome="$(resolve_run_outcome "${ACTION_STATUS}" "${DELIVERED_OUTCOME}" "${LOOP_FAILURE_FILE}")"
    record_run_failure "${LOOP_FAILURE_FILE}" "${AGENT_RESULT}" "${AGENT_FAILURE_STAGE}" \
        "${AGENT_FAILURE_MESSAGE}" "${ACTION_STATUS}" "${DELIVERED_OUTCOME}"

    if [[ -n ${GITHUB_OUTPUT} ]]; then
        echo "outcome=${outcome}" >> "${GITHUB_OUTPUT}"
    fi
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
