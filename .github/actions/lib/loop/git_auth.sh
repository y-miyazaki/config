#!/bin/bash
#######################################
# Description:
#   Configure the commit identity and HTTPS push credentials for loop actions.
#
# Usage:
#   source git_auth.sh
#   GITHUB_TOKEN=... loop_git_configure_auth
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Credentials are written to the repository-local git config only
#   - Returns non-zero (never exits) so callers keep their own failure handling
#   - An empty GITHUB_TOKEN is rejected before any git config is written
#######################################

#######################################
# loop_git_configure_auth: Set commit identity and the GitHub auth header
#
# Globals:
#   GITHUB_TOKEN - Token used for fetch and push (read)
#
# Arguments:
#   None
#
# Outputs:
#   ::error:: annotation on stderr when GITHUB_TOKEN is empty
#
# Returns:
#   0 on success; 1 when GITHUB_TOKEN is empty or git config fails
#
#######################################
function loop_git_configure_auth {
    if [[ -z ${GITHUB_TOKEN:-} ]]; then
        echo "::error::GITHUB_TOKEN is required" >&2
        return 1
    fi
    git config user.name "github-actions[bot]" \
        && git config user.email "github-actions[bot]@users.noreply.github.com" \
        && git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GITHUB_TOKEN}" | base64 -w0)"
}
