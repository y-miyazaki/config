#!/bin/bash
#######################################
# Description: Resolve loop state file path from explicit input or loop_name default
#
# Usage:
#   source "${GITHUB_ACTION_PATH}/../lib/loop/resolve_state_file.sh"
#   LOOP_NAME=changelog STATE_FILE_INPUT= GITHUB_OUTPUT=/tmp/out resolve_state_file_emit
#
# Output:
#   state_file=<path> on GITHUB_OUTPUT (may be empty)
#
# Design Rules:
#   - Explicit STATE_FILE_INPUT overrides loop_name-derived default
#   - Empty output when neither input is provided
#######################################

# shellcheck source=./check_names.sh
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check_names.sh"

#######################################
# resolve_state_file_emit: Resolve state file path
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
function resolve_state_file_emit {
    local state_file=""

    if [[ -n ${STATE_FILE_INPUT:-} ]]; then
        state_file="${STATE_FILE_INPUT}"
    elif [[ -n ${LOOP_NAME:-} ]]; then
        if ! check_names_loop_name "${LOOP_NAME}"; then
            echo "::error::loop_name contains invalid characters" >&2
            return 1
        fi
        state_file=".loop/state-${LOOP_NAME}.json"
    fi

    if [[ -n ${state_file} ]] && ! check_names_state_file "${state_file}"; then
        echo "::error::state_file must match .loop/state-<name>.json (no '..')" >&2
        return 1
    fi

    echo "state_file=${state_file}" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    set -euo pipefail
    umask 027
    export LC_ALL=C.UTF-8
    resolve_state_file_emit
fi
