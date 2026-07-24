#!/bin/bash
#######################################
# Description:
#   Detect whether workflow CodeQL should run for the current repository.
#
# Usage:
#   GITHUB_REPOSITORY=owner/repo GH_TOKEN=... bash lib/detect.sh
#
# Design Rules:
#   - Skip when CodeQL default setup is enabled (workflow SARIF would be rejected)
#   - Skip private repositories without GitHub Code Security or Advanced Security
#
# Output:
#   skip=true|false on GITHUB_OUTPUT
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# detect_codeql_support: Detect whether workflow CodeQL should run
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file
#   GITHUB_REPOSITORY - Repository under test (owner/name)
#
# Arguments:
#   None
#
# Outputs:
#   Writes skip=true|false to GITHUB_OUTPUT
#
# Returns:
#   None
#
#######################################
function detect_codeql_support {
    local code_security=""
    local private=""
    local state=""

    state="$(gh api "repos/${GITHUB_REPOSITORY}/code-scanning/default-setup" --jq '.state // empty' 2> /dev/null || true)"
    if [[ ${state} == "configured" ]]; then
        echo "skip=true" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
        echo "::notice title=CodeQL skipped::CodeQL default setup is enabled on ${GITHUB_REPOSITORY}. Skipping workflow CodeQL to avoid SARIF upload rejection."
        return 0
    fi

    private="$(gh api "repos/${GITHUB_REPOSITORY}" --jq '.private' 2> /dev/null || echo "true")"
    if [[ ${private} == "false" ]]; then
        echo "skip=false" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
        echo "CodeQL will run in this workflow."
        return 0
    fi

    code_security="$(gh api "repos/${GITHUB_REPOSITORY}" --jq '
      .security_and_analysis.code_security.status //
      .security_and_analysis.advanced_security.status //
      empty
    ' 2> /dev/null || true)"
    if [[ ${code_security} == "enabled" ]]; then
        echo "skip=false" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
        echo "CodeQL will run in this workflow."
        return 0
    fi

    echo "skip=true" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
    echo "::notice title=CodeQL skipped::GitHub Code Security is not enabled on private repository ${GITHUB_REPOSITORY}. Skipping workflow CodeQL; enable Code Security under Settings > Code security and analysis (requires a license for private repositories)."
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    detect_codeql_support
fi
