#!/bin/bash
#######################################
# Description: MCP enablement helpers for loop agent CLIs
#
# Usage: source "${SCRIPT_DIR}/lib/mcp.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - resolve_mcp_json_path prefers .mcp.json, then .cursor/mcp.json, then .github/mcp.json
# - prepare_agent_mcps materializes Codex config from the shared MCP manifest
# - append_agent_mcp_args adds engine-specific non-interactive approval flags
# - Codex MCP servers are configured in prepare_agent_mcps; other engines use CLI flags
#######################################

#######################################
# append_agent_mcp_args: Add engine-specific MCP approval flags to an ARGS array
#
# Arguments:
#   $1 - Name of the ARGS array variable (nameref)
#   $2 - Engine name (claude|copilot|codex|cursor)
#
# Global Variables:
#   None
#
# Returns:
#   None
#
#######################################
function append_agent_mcp_args {
    local -n args_ref=$1
    local engine="${2:?engine required}"

    case "${engine}" in
        claude)
            args_ref+=(--settings '{"enableAllProjectMcpServers":true}')
            ;;
        copilot)
            args_ref+=(--allow-all-tools)
            ;;
        cursor)
            args_ref+=(--approve-mcps)
            ;;
        codex) ;;
    esac
}

#######################################
# prepare_agent_mcps: Enable MCP servers for the selected engine in CI
#
# Description:
#   Codex does not read project .mcp.json automatically. When ENGINE is codex,
#   render an isolated CODEX_HOME/config.toml from the shared MCP manifest.
#
# Arguments:
#   $1 - Engine name (claude|copilot|codex|cursor)
#   $2 - Workspace root (default: .)
#
# Global Variables:
#   CODEX_HOME - Set for codex runs to an isolated config directory
#   RUNNER_TEMP - GitHub Actions temp directory used for the default CODEX_HOME parent
#
# Returns:
#   0 when setup completes or MCP is not configured
#
#######################################
function prepare_agent_mcps {
    local engine="${1:?engine required}"
    local root="${2:-.}"
    local mcp_json codex_home

    if [[ ${engine} != "codex" ]]; then
        return 0
    fi

    if ! mcp_json="$(resolve_mcp_json_path "${root}")"; then
        return 0
    fi

    codex_home="${CODEX_HOME:-${RUNNER_TEMP:-/tmp}/loop-codex-home}"
    export CODEX_HOME="${codex_home}"
    mkdir -p "${CODEX_HOME}"
    write_codex_mcp_config "${mcp_json}" "${CODEX_HOME}/config.toml"
}

#######################################
# resolve_mcp_json_path: Locate the shared MCP manifest for a workspace root
#
# Description:
#   Prefer the git toplevel from the caller's current directory so a relative
#   working_directory label is not appended twice when the step already cd'd
#   into that directory.
#
# Arguments:
#   $1 - Workspace root hint (default: .)
#
# Global Variables:
#   None
#
# Returns:
#   Manifest path to stdout, 1 when none exists
#
#######################################
function resolve_mcp_json_path {
    local root="${1:-.}"
    local candidate search_root

    if [[ ${root} == "." ]]; then
        search_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
    elif [[ ${root} == /* ]]; then
        search_root="$(git -C "${root}" rev-parse --show-toplevel 2> /dev/null || printf '%s' "${root}")"
    else
        search_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
    fi

    for candidate in \
        "${search_root}/.mcp.json" \
        "${search_root}/.cursor/mcp.json" \
        "${search_root}/.github/mcp.json"; do
        if [[ -f ${candidate} ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

#######################################
# write_codex_mcp_config: Render Codex config.toml MCP tables from mcp.json
#
# Arguments:
#   $1 - Source mcp.json path
#   $2 - Destination config.toml path
#
# Global Variables:
#   None
#
# Returns:
#   0 on success, 1 when jq conversion fails
#
#######################################
function write_codex_mcp_config {
    local mcp_json="${1:?mcp_json required}"
    local config_toml="${2:?config_toml required}"

    if ! jq -r '
        .mcpServers
        | to_entries[]
        | . as $entry
        | "[mcp_servers.\($entry.key)]",
          "command = \"\($entry.value.command)\"",
          (if ($entry.value.args // [] | length) > 0
              then "args = " + (($entry.value.args // []) | @json)
              else empty
           end),
          (if ($entry.value.env // {} | length) > 0
              then "[mcp_servers.\($entry.key).env]",
                   ($entry.value.env | to_entries[] | "\(.key) = \"\(.value)\"")
              else empty
           end),
          ""
    ' "${mcp_json}" > "${config_toml}"; then
        return 1
    fi
}
