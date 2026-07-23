#!/bin/bash
#######################################
# Description:
#   Terminate background SSM port forwarding session when present.
#
# Usage:
#   SSM_PID=12345 bash lib/cleanup.sh
#
# Design Rules:
#   - No-op when SSM_PID is unset or process already exited
#   - Force kill only after graceful termination wait
#
# Output:
#   Status messages to stdout
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# cleanup_ssm_port_forward: Stop background SSM session
#
# Globals:
#   SSM_PID - Background session PID
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
function cleanup_ssm_port_forward {
    echo "Cleaning up SSM port forwarding session"

    if [[ -n ${SSM_PID:-} ]] && ! [[ ${SSM_PID} =~ ^[0-9]+$ ]]; then
        echo "❌ Error: invalid SSM_PID: ${SSM_PID}" >&2
        return 1
    fi

    if [[ -n ${SSM_PID:-} ]] && ps -p "${SSM_PID}" > /dev/null 2>&1; then
        echo "Terminating SSM session (PID: ${SSM_PID})"
        kill "${SSM_PID}" 2> /dev/null || true

        for _ in {1..5}; do
            if ! ps -p "${SSM_PID}" > /dev/null 2>&1; then
                echo "✅ SSM session terminated successfully"
                break
            fi
            sleep 1
        done

        if ps -p "${SSM_PID}" > /dev/null 2>&1; then
            echo "Force killing SSM session..."
            kill -9 "${SSM_PID}" 2> /dev/null || true
        fi
    else
        echo "No active SSM session to clean up"
    fi

    echo "SSM port forwarding cleanup completed"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    cleanup_ssm_port_forward
fi
