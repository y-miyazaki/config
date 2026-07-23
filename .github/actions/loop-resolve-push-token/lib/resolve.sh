#!/bin/bash
#######################################
# Description:
#   Resolve a GitHub push token from App token, GH_TOKEN_PUSH, or GITHUB_TOKEN.
#
# Usage:
#   APP_TOKEN=... GH_TOKEN_PUSH=... bash lib/resolve.sh
#
# Design Rules:
#   - Prefer App token when present, then explicit push token, then GITHUB_TOKEN
#   - Mask resolved token before writing to GITHUB_OUTPUT
#
# Output:
#   token=<value> on GITHUB_OUTPUT
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# resolve_push_token: Resolve push token precedence chain
#
# Globals:
#   APP_TOKEN - Optional GitHub App installation token
#   GH_TOKEN_PUSH - Optional explicit push token
#   GITHUB_TOKEN - Default Actions token
#   GITHUB_OUTPUT - GitHub Actions output file
#
# Arguments:
#   None
#
# Outputs:
#   Writes masked token to GITHUB_OUTPUT
#
# Returns:
#   None
#
#######################################
function resolve_push_token {
    local token=""

    if [[ ${BOT_APP_CONFIGURED:-false} == "true" && -z ${APP_TOKEN:-} ]]; then
        echo "::warning::GitHub App token generation failed; falling back to GH_TOKEN_PUSH or GITHUB_TOKEN" >&2
    fi

    if [[ -n ${APP_TOKEN:-} ]]; then
        token="${APP_TOKEN}"
    elif [[ -n ${GH_TOKEN_PUSH:-} ]]; then
        token="${GH_TOKEN_PUSH}"
    else
        token="${GITHUB_TOKEN}"
    fi

    echo "::add-mask::${token}"
    echo "token=${token}" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    resolve_push_token
fi
