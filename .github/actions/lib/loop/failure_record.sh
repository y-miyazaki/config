#!/bin/bash
#######################################
# Description:
#   Record and export loop step failure diagnostics for run-log metadata.
#
# Usage:
#   source failure_record.sh
#   failure_record_write STAGE MESSAGE FILE
#   failure_record_exists FILE
#   failure_record_export_outputs FILE
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - failure_message redacted and truncated to 500 Unicode codepoints
#   - Latest record wins when multiple failures occur in one action
#
# Dependencies:
#   - bash, jq, openssl
#   - redact.sh in the same directory
#######################################

_LOOP_FAILURE_RECORD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./redact.sh disable=SC1091
source "${_LOOP_FAILURE_RECORD_LIB_DIR}/redact.sh"

#######################################
# failure_record_export_outputs: Export recorded failure to GITHUB_OUTPUT
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file (optional)
#
# Arguments:
#   $1 - Source JSON file path
#
# Outputs:
#   failure_stage and failure_message on GITHUB_OUTPUT when set
#
# Returns:
#   0 on success
#
#######################################
function failure_record_export_outputs {
    local failure_file="${1:?failure_file required}"
    local stage message delim

    if [[ -z ${GITHUB_OUTPUT:-} ]]; then
        return 0
    fi
    if ! failure_record_exists "${failure_file}"; then
        return 0
    fi

    stage="$(jq -r '.failure_stage // empty' "${failure_file}" 2> /dev/null || true)"
    message="$(jq -r '.failure_message // empty' "${failure_file}" 2> /dev/null || true)"

    {
        echo "failure_stage=${stage}"
        delim="FAILURE_MESSAGE_$(openssl rand -hex 8)"
        echo "failure_message<<${delim}"
        printf '%s\n' "${message}"
        echo "${delim}"
    } >> "${GITHUB_OUTPUT}"
}

#######################################
# failure_record_write: Write failure_stage and failure_message JSON
#
# Globals:
#   None
#
# Arguments:
#   $1 - failure_stage identifier
#   $2 - failure_message text
#   $3 - Target JSON file path
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function failure_record_write {
    local stage="${1:?stage required}"
    local message="${2:-}"
    local failure_file="${3:?failure_file required}"
    local redacted truncated

    redacted="$(redact_sensitive_text "${message}")"
    truncated="$(jq -rn --arg m "${redacted}" '$m[0:500]')"
    jq -n \
        --arg failure_stage "${stage}" \
        --arg failure_message "${truncated}" \
        '{failure_stage: $failure_stage, failure_message: $failure_message}' \
        > "${failure_file}"
}

#######################################
# failure_record_exists: Test whether a failure record with a stage exists
#
# Globals:
#   None
#
# Arguments:
#   $1 - Failure JSON file path
#
# Outputs:
#   None
#
# Returns:
#   0 when the file exists and failure_stage is non-empty
#   1 otherwise (missing file, malformed JSON, or empty failure_stage)
#
#######################################
function failure_record_exists {
    local failure_file="${1:?failure_file required}"
    local stage

    if [[ ! -f ${failure_file} ]]; then
        return 1
    fi
    stage="$(jq -r '.failure_stage // empty' "${failure_file}" 2> /dev/null || true)"
    [[ -n ${stage} ]]
}
