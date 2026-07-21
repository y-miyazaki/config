#!/bin/bash
#######################################
# Description:
#   Install loop AI engine CLI and write package/version to GITHUB_OUTPUT.
#
# Usage:
#   ENGINE=cursor CLI_VERSION=latest bash lib/install.sh
#
# Design Rules:
#   - Cursor uses curl installer; other engines use npm install
#   - Unsupported ENGINE values fail with a clear error
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
ENGINE="${ENGINE:-}"
CLI_VERSION="${CLI_VERSION:-latest}"
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
# install_npm_package: Install resolved npm package without saving to package.json
#
# Globals:
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
    npm install "${PKG}@${RESOLVED}" --no-save
}

#######################################
# resolve_engine_package: Map ENGINE to npm package identifier
#
# Globals:
#   ENGINE - Engine slug (claude|copilot|codex|cursor)
#   PKG - Set to package name on success
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 on unsupported ENGINE
#
#######################################
function resolve_engine_package {
    case "${ENGINE}" in
        claude) PKG="@anthropic-ai/claude-code" ;;
        copilot) PKG="@github/copilot" ;;
        codex) PKG="@openai/codex" ;;
        cursor) PKG="cursor" ;;
        *)
            echo "::error::Unsupported engine: ${ENGINE}"
            exit 1
            ;;
    esac
}

#######################################
# resolve_package_version: Resolve CLI_VERSION to concrete version string
#
# Globals:
#   ENGINE - Engine slug
#   CLI_VERSION - Requested version or latest
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
    if [[ ${ENGINE} == "cursor" ]]; then
        RESOLVED="${CLI_VERSION}"
        return 0
    fi
    if [[ ${CLI_VERSION} == "latest" ]]; then
        RESOLVED="$(npm view "${PKG}" version)"
        return 0
    fi
    RESOLVED="${CLI_VERSION}"
}

#######################################
# validate_engine: Ensure ENGINE is provided
#
# Globals:
#   ENGINE - Required engine slug
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 when ENGINE is empty
#
#######################################
function validate_engine {
    : "${ENGINE:?}"
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
#   ENGINE, CLI_VERSION, PKG, RESOLVED
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

    if [[ ${ENGINE} == "cursor" ]]; then
        install_cursor_cli
        return 0
    fi

    install_npm_package
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
