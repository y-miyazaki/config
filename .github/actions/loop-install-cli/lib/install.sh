#!/bin/bash
#######################################
# Description:
#   Install loop AI engine CLI and write package/version to GITHUB_OUTPUT.
#
# Usage:
#   AGENT_ENGINE=cursor AGENT_CLI_VERSION=latest bash lib/install.sh
#
# Design Rules:
#   - Cursor uses curl installer; other engines use npm install
#   - Unsupported AGENT_ENGINE values fail with a clear error
#
# Output:
#   Writes package and version to GITHUB_OUTPUT; may append bindir to GITHUB_PATH
#
# Dependencies:
#   - bash, curl, npm (non-cursor engines)
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
AGENT_ENGINE="${AGENT_ENGINE:-}"
AGENT_CLI_VERSION="${AGENT_CLI_VERSION:-latest}"
PKG=""
RESOLVED=""

#######################################
# install_cursor_cli: Download and register Cursor CLI bindir
#
# Globals:
#   HOME - Used to locate installed agent binary
#   GITHUB_PATH - Optional path file for workflow PATH updates
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 when Cursor CLI is not found after install
#
#######################################
function install_cursor_cli {
    local bindir

    # Official Cursor installer; trusted vendor endpoint in CI only.
    # nosemgrep: bash.curl.security.curl-pipe-bash.curl-pipe-bash
    curl https://cursor.com/install -fsS | bash
    for bindir in "${HOME}/.local/bin" "${HOME}/.cursor/bin"; do
        if [[ -x ${bindir}/agent ]] || [[ -x ${bindir}/cursor-agent ]]; then
            if [[ -n ${GITHUB_PATH:-} ]]; then
                echo "${bindir}" >> "${GITHUB_PATH}"
            fi
            return 0
        fi
    done
    echo "::error::Cursor CLI not found after install"
    exit 1
}

#######################################
# install_npm_package: Install resolved npm package and register its bindir
#
# Globals:
#   GITHUB_PATH - Workflow PATH file appended with the package bindir (optional)
#   PATH - Prepended with the package bindir
#   PKG - npm package name
#   RESOLVED - Resolved package version
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits with npm install status
#
#######################################
function install_npm_package {
    local bindir

    npm install "${PKG}@${RESOLVED}" --no-save
    # The loop runs the CLI from the isolated worktree, where a local
    # node_modules is not resolvable. Register the bindir like the cursor
    # installer does so the binary is reachable by name from any directory.
    bindir="$(pwd)/node_modules/.bin"
    if [[ ! -d ${bindir} ]]; then
        echo "::error::npm package ${PKG} installed without ${bindir}"
        exit 1
    fi
    if [[ -n ${GITHUB_PATH:-} ]]; then
        echo "${bindir}" >> "${GITHUB_PATH}"
    fi
    export PATH="${bindir}:${PATH}"
}

#######################################
# resolve_engine_package: Map AGENT_ENGINE to npm package identifier
#
# Globals:
#   AGENT_ENGINE - Engine slug (claude|copilot|codex|cursor)
#   PKG - Set to package name on success
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 on unsupported AGENT_ENGINE
#
#######################################
function resolve_engine_package {
    case "${AGENT_ENGINE}" in
        claude) PKG="@anthropic-ai/claude-code" ;;
        copilot) PKG="@github/copilot" ;;
        codex) PKG="@openai/codex" ;;
        cursor) PKG="cursor" ;;
        *)
            echo "::error::Unsupported engine: ${AGENT_ENGINE}"
            exit 1
            ;;
    esac
}

#######################################
# resolve_package_version: Resolve AGENT_CLI_VERSION to concrete version string
#
# Globals:
#   AGENT_ENGINE - Engine slug
#   AGENT_CLI_VERSION - Requested version or latest
#   PKG - npm package name for non-cursor engines
#   RESOLVED - Set to resolved version
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
function resolve_package_version {
    if [[ ${AGENT_ENGINE} == "cursor" ]]; then
        RESOLVED="${AGENT_CLI_VERSION}"
        return 0
    fi
    if [[ ${AGENT_CLI_VERSION} == "latest" ]]; then
        RESOLVED="$(npm view "${PKG}" version)"
        return 0
    fi
    RESOLVED="${AGENT_CLI_VERSION}"
}

#######################################
# validate_engine: Ensure AGENT_ENGINE is provided
#
# Globals:
#   AGENT_ENGINE - Required engine slug
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 when AGENT_ENGINE is empty
#
#######################################
function validate_engine {
    : "${AGENT_ENGINE:?}"
}

#######################################
# write_install_outputs: Write package and version to GITHUB_OUTPUT
#
# Globals:
#   PKG - Package identifier
#   RESOLVED - Resolved version
#   GITHUB_OUTPUT - GitHub Actions output file
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
function write_install_outputs {
    {
        echo "package=${PKG}"
        echo "version=${RESOLVED}"
    } >> "${GITHUB_OUTPUT}"
}

#######################################
# main: Install engine CLI and record outputs
#
# Globals:
#   AGENT_ENGINE, AGENT_CLI_VERSION, PKG, RESOLVED
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits with install status
#
#######################################
function main {
    validate_engine
    resolve_engine_package
    resolve_package_version
    write_install_outputs

    if [[ ${AGENT_ENGINE} == "cursor" ]]; then
        install_cursor_cli
        return 0
    fi

    install_npm_package
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
