#!/bin/bash
#######################################
# Description:
#   Validate AWS service control action and resolve target JSON for control jobs.
#
# Usage:
#   ACTION=start AUTO_DISCOVER=true DISCOVERED_B64=... bash lib/validate.sh
#
# Design Rules:
#   - action must be start or stop
#   - auto_discover reads base64 discovery output; manual mode uses MANUAL_TARGETS_JSON
#   - empty targets emit targets=[] without failing
#
# Output:
#   action and targets on GITHUB_OUTPUT
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# validate_service_control_inputs: Validate action and resolve targets JSON
#
# Globals:
#   ACTION - start|stop
#   AUTO_DISCOVER - true|false
#   DISCOVERED_B64 - Base64 discovered targets
#   INPUT_FIELD_NAME - Field name for JSON errors
#   MANUAL_TARGETS_JSON - Manual targets JSON
#   RESOURCE_LABEL - Human-readable resource label
#   GITHUB_OUTPUT - GitHub Actions output file
#
# Arguments:
#   None
#
# Outputs:
#   Writes action and targets to GITHUB_OUTPUT
#
# Returns:
#   Exits non-zero on invalid action or JSON
#
#######################################
function validate_service_control_inputs {
    local jq_err=""
    local sanitized_targets=""
    local target_count=""

    if [[ ${ACTION} != "start" && ${ACTION} != "stop" ]]; then
        echo "❌ Error: action must be 'start' or 'stop', got '${ACTION}'" >&2
        return 1
    fi
    echo "action=${ACTION}" >> "$GITHUB_OUTPUT"
    echo "✅ Action validated: ${ACTION}"

    local target_json=""

    if [[ ${AUTO_DISCOVER} == "true" ]]; then
        if [[ -n ${DISCOVERED_B64:-} ]]; then
            target_json=$(printf '%s' "${DISCOVERED_B64}" | base64 --decode)
        else
            target_json='[]'
        fi
        echo "Using auto-discovered ${RESOURCE_LABEL}"
    else
        target_json="${MANUAL_TARGETS_JSON}"
        echo "Using manually specified ${RESOURCE_LABEL}"
    fi

    if ! jq_err=$(printf '%s' "${target_json}" | jq empty 2>&1); then
        echo "❌ Error: ${INPUT_FIELD_NAME} is not valid JSON: ${jq_err}" >&2
        return 1
    fi

    target_count=$(printf '%s' "${target_json}" | jq '. | length')
    if [[ ${target_count} -eq 0 ]]; then
        echo "⚠️  Warning: No ${RESOURCE_LABEL} found (skipping control)" >&2
        {
            echo "targets<<TARGETS_EOF"
            echo "[]"
            echo "TARGETS_EOF"
        } >> "$GITHUB_OUTPUT"
        return 0
    fi

    sanitized_targets=$(printf '%s' "${target_json}" | jq -c '.')
    {
        echo "targets<<TARGETS_EOF"
        printf '%s\n' "${sanitized_targets}"
        echo "TARGETS_EOF"
    } >> "$GITHUB_OUTPUT"
    echo "✅ Target ${RESOURCE_LABEL} count: ${target_count}"
    printf '%s' "${sanitized_targets}" | jq .
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    validate_service_control_inputs || exit $?
fi
