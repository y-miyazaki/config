#!/bin/bash
#######################################
# Description:
#   Start SSM port forwarding from bastion to the database host.
#
# Usage:
#   BASTION_ID=i-123 DB_HOST=db.example DB_PORT=5432 DB_TYPE=pgsql bash lib/port-forward.sh
#
# Design Rules:
#   - Start SSM session in background and wait for port-open log markers
#   - Default local port by DB_TYPE when BASTION_LOCAL_PORT is empty
#
# Output:
#   LOCAL_PORT and SSM_PID on GITHUB_ENV; local_port and ssm_pid on GITHUB_OUTPUT
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# setup_ssm_port_forward: Start and wait for SSM port forwarding
#
# Globals:
#   BASTION_ID, BASTION_LOCAL_PORT, DB_HOST, DB_PORT, DB_TYPE
#   GITHUB_ENV, GITHUB_OUTPUT
#
# Arguments:
#   None
#
# Outputs:
#   Writes LOCAL_PORT and SSM_PID to GITHUB_ENV
#
# Returns:
#   Exits non-zero when port forwarding fails to start
#
#######################################
function setup_ssm_port_forward {
    local elapsed=0
    local local_port=""
    local max_wait=60
    local ssm_log=""
    local ssm_pid=""

    echo "Starting AWS Systems Manager Session Manager port forwarding"

    if [[ -z ${BASTION_ID:-} ]]; then
        echo "❌ Error: BASTION_ID is required" >&2
        return 1
    fi
    if ! [[ ${BASTION_ID} =~ ^i-[0-9a-f]+$ ]]; then
        echo "❌ Error: invalid BASTION_ID format: ${BASTION_ID}" >&2
        return 1
    fi

    if [[ -n ${BASTION_LOCAL_PORT} ]]; then
        if ! [[ ${BASTION_LOCAL_PORT} =~ ^[0-9]+$ ]] \
            || ((BASTION_LOCAL_PORT < 1 || BASTION_LOCAL_PORT > 65535)); then
            echo "❌ Error: invalid BASTION_LOCAL_PORT: ${BASTION_LOCAL_PORT}" >&2
            return 1
        fi
        local_port="${BASTION_LOCAL_PORT}"
    else
        case "${DB_TYPE}" in
            mysql) local_port="13306" ;;
            pgsql | pgsql11) local_port="15432" ;;
            redshift) local_port="15439" ;;
            *) local_port="13306" ;;
        esac
    fi

    if [[ -z ${DB_HOST:-} ]]; then
        echo "❌ Error: DB_HOST is required" >&2
        return 1
    fi
    if [[ -z ${DB_PORT:-} ]] || ! [[ ${DB_PORT} =~ ^[0-9]+$ ]] \
        || ((DB_PORT < 1 || DB_PORT > 65535)); then
        echo "❌ Error: invalid DB_PORT: ${DB_PORT:-<empty>}" >&2
        return 1
    fi

    echo "LOCAL_PORT=${local_port}" >> "$GITHUB_ENV"
    echo "local_port=${local_port}" >> "$GITHUB_OUTPUT"

    echo "Starting port forwarding: localhost:${local_port} -> ${BASTION_ID} -> ${DB_HOST}:${DB_PORT}"

    local ssm_parameters=""
    ssm_log="$(mktemp)"
    trap 'rm -f "${ssm_log:-}"; [[ -n ${ssm_pid:-} ]] && kill "${ssm_pid}" 2>/dev/null || true' EXIT

    ssm_parameters=$(jq -nc \
        --arg host "${DB_HOST}" \
        --arg port "${DB_PORT}" \
        --arg local_port "${local_port}" \
        '{host:[$host], portNumber:[$port], localPortNumber:[$local_port]}')

    aws ssm start-session \
        --target "${BASTION_ID}" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "${ssm_parameters}" \
        > "${ssm_log}" 2>&1 &

    ssm_pid=$!
    echo "SSM_PID=${ssm_pid}" >> "$GITHUB_ENV"
    echo "ssm_pid=${ssm_pid}" >> "$GITHUB_OUTPUT"
    echo "SSM Session started with PID: ${ssm_pid}"

    echo "Waiting for port forwarding to be ready..."
    while [[ ${elapsed} -lt ${max_wait} ]]; do
        if ! ps -p "${ssm_pid}" > /dev/null 2>&1; then
            echo "❌ SSM session process died unexpectedly" >&2
            echo "SSM Session log:" >&2
            cat "${ssm_log}" >&2
            return 1
        fi

        if grep -q "Port ${local_port} opened" "${ssm_log}" 2> /dev/null \
            && grep -q "Waiting for connections" "${ssm_log}" 2> /dev/null; then
            echo "✅ Port forwarding is ready on localhost:${local_port} (confirmed by SSM log)"
            sleep 2
            trap - EXIT
            rm -f "${ssm_log}"
            return 0
        fi

        sleep 1
        elapsed=$((elapsed + 1))

        if [[ ${elapsed} -eq ${max_wait} ]]; then
            echo "❌ Port forwarding failed to start within ${max_wait} seconds" >&2
            echo "SSM Session log:" >&2
            cat "${ssm_log}" >&2
            return 1
        fi

        if [[ $((elapsed % 10)) -eq 0 && ${elapsed} -gt 0 ]]; then
            echo "  ${elapsed}/${max_wait} seconds: Still waiting for port forwarding..."
        fi
    done
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    setup_ssm_port_forward || exit $?
fi
