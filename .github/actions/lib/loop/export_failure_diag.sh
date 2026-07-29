#!/bin/bash
#######################################
# Description:
#   Export loop failure diagnostics to GITHUB_OUTPUT when recorded.
#
# Usage:
#   LOOP_FAILURE_FILE=/path/to/failure.json bash export_failure_diag.sh
#   STATUS_DIR=/path/to/status bash export_failure_diag.sh
#
# Design Rules:
#   - Reads JSON written by loop_failure_record
#   - No-op when failure file is missing or GITHUB_OUTPUT unset
#
# Output:
#   failure_stage and failure_message on GITHUB_OUTPUT when set
#
# Dependencies:
#   - bash, jq, openssl
#   - failure_record.sh in the same directory
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#######################################
# Global variables
#######################################
LOOP_FAILURE_FILE="${LOOP_FAILURE_FILE:-}"
STATUS_DIR="${STATUS_DIR:-}"

#######################################
# resolve_failure_file: Resolve failure JSON path from env
#
# Globals:
#   LOOP_FAILURE_FILE - Explicit failure JSON path (optional)
#   STATUS_DIR - Runner temp directory for execute attempt artifacts (optional)
#
# Arguments:
#   None
#
# Outputs:
#   Resolved file path to stdout
#
# Returns:
#   Exits 1 when neither env provides a path
#
#######################################
function resolve_failure_file {
    if [[ -n ${LOOP_FAILURE_FILE} ]]; then
        printf '%s' "${LOOP_FAILURE_FILE}"
        return 0
    fi
    if [[ -n ${STATUS_DIR} ]]; then
        printf '%s' "${STATUS_DIR}/failure.json"
        return 0
    fi
    echo "::error::LOOP_FAILURE_FILE or STATUS_DIR is required" >&2
    exit 1
}

#######################################
# main: Export failure diagnostics to GITHUB_OUTPUT
#
# Globals:
#   LOOP_FAILURE_FILE, STATUS_DIR - Failure JSON location
#
# Arguments:
#   None
#
# Outputs:
#   failure_stage and failure_message on GITHUB_OUTPUT when set
#
# Returns:
#   0 on success
#
#######################################
function main {
    local failure_file

    # shellcheck source=./failure_record.sh
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/failure_record.sh"

    failure_file="$(resolve_failure_file)"
    loop_failure_export_outputs "${failure_file}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
