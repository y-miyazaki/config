#!/bin/bash
#######################################
# Description:
#   Detect whether SARIF upload to GitHub Security is supported for the
#   current repository.
#
# Usage:
#   GITHUB_REPOSITORY=owner/repo GH_TOKEN=... bash lib/detect.sh
#
# Design Rules:
#   - Public repositories always support SARIF upload
#   - Private repositories require GitHub Code Security or Advanced Security
#
# Output:
#   supported=true|false on GITHUB_OUTPUT
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# detect_sarif_upload_support: Detect SARIF upload support for the repository
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file
#   GITHUB_REPOSITORY - Repository under test (owner/name)
#
# Arguments:
#   None
#
# Outputs:
#   Writes supported=true|false to GITHUB_OUTPUT
#
# Returns:
#   None
#
#######################################
function detect_sarif_upload_support {
    local code_security=""
    local private=""

    private="$(gh api "repos/${GITHUB_REPOSITORY}" --jq '.private' 2> /dev/null || echo "true")"
    if [[ ${private} == "false" ]]; then
        echo "supported=true" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
        echo "SARIF upload is supported (public repository)."
        return 0
    fi

    code_security="$(gh api "repos/${GITHUB_REPOSITORY}" --jq '
      .security_and_analysis.code_security.status //
      .security_and_analysis.advanced_security.status //
      empty
    ' 2> /dev/null || true)"
    if [[ ${code_security} == "enabled" ]]; then
        echo "supported=true" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
        echo "GitHub Code Security is enabled; SARIF upload will run."
        return 0
    fi

    echo "supported=false" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
    echo "::notice title=SARIF upload skipped::GitHub Code Security is not enabled on private repository ${GITHUB_REPOSITORY}. Results are available in job logs and artifacts only. Enable Code Security under Settings > Code security and analysis (requires a license for private repositories)."
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    detect_sarif_upload_support
fi
