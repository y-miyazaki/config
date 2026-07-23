#!/bin/bash
#######################################
# Description: Resolve loop state file path from explicit input or loop_name default
#
# Usage:
#   source "${LOOP_ACTION_LIB_DIR}/resolve_state_file.sh"
#   LOOP_NAME=changelog STATE_FILE_INPUT= GITHUB_OUTPUT=/tmp/out resolve_state_file
#
# Output:
#   state_file=<path> on GITHUB_OUTPUT (may be empty)
#
# Design Rules:
#   - Explicit STATE_FILE_INPUT overrides loop_name-derived default
#   - Empty output when neither input is provided
#######################################

#######################################
# resolve_state_file: Resolve state file path
#
# Globals:
#   LOOP_NAME - Loop name for default path
#   STATE_FILE_INPUT - Explicit override path
#   GITHUB_OUTPUT - GitHub Actions output file
#
# Arguments:
#   None
#
# Outputs:
#   Writes state_file to GITHUB_OUTPUT
#
# Returns:
#   0 on success
#
#######################################
function resolve_state_file {
    local state_file=""

    if [[ -n ${STATE_FILE_INPUT:-} ]]; then
        if [[ ${STATE_FILE_INPUT} == *".."* ]]; then
            echo "::error::state_file must not contain '..'" >&2
            return 1
        fi
        if ! [[ ${STATE_FILE_INPUT} =~ ^\.loop/state[-a-zA-Z0-9_.]+\.json$ ]]; then
            echo "::error::state_file must match .loop/state-<name>.json" >&2
            return 1
        fi
        state_file="${STATE_FILE_INPUT}"
    elif [[ -n ${LOOP_NAME:-} ]]; then
        if ! [[ ${LOOP_NAME} =~ ^[a-zA-Z0-9][-a-zA-Z0-9_.]*$ ]]; then
            echo "::error::loop_name contains invalid characters" >&2
            return 1
        fi
        state_file=".loop/state-${LOOP_NAME}.json"
    fi

    echo "state_file=${state_file}" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    set -euo pipefail
    umask 027
    export LC_ALL=C.UTF-8
    resolve_state_file
fi
