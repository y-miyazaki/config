#!/bin/bash
#######################################
# Description:
#   Resolve a GitHub API token from App token, INPUT_GITHUB_TOKEN, or GITHUB_TOKEN.
#
# Usage:
#   APP_TOKEN=... INPUT_GITHUB_TOKEN=... bash lib/resolve.sh
#
# Design Rules:
#   - Prefer App token when present, then explicit github_token input, then GITHUB_TOKEN
#   - Mask resolved token before writing to GITHUB_OUTPUT
#
# Output:
#   github_token=<value> on GITHUB_OUTPUT
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# resolve_github_token: Resolve github_token precedence chain
#
# Globals:
#   APP_TOKEN - Optional GitHub App installation token
#   INPUT_GITHUB_TOKEN - Optional explicit github_token input
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
function resolve_github_token {
    local token=""

    if [[ ${BOT_APP_CONFIGURED:-false} == "true" && -z ${APP_TOKEN:-} ]]; then
        echo "::warning::GitHub App token generation failed; falling back to INPUT_GITHUB_TOKEN or GITHUB_TOKEN" >&2
    fi

    if [[ -n ${APP_TOKEN:-} ]]; then
        token="${APP_TOKEN}"
    elif [[ -n ${INPUT_GITHUB_TOKEN:-} ]]; then
        token="${INPUT_GITHUB_TOKEN}"
    else
        token="${GITHUB_TOKEN}"
    fi

    echo "::add-mask::${token}"
    echo "github_token=${token}" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    resolve_github_token
fi
