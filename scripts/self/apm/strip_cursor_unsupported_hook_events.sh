#!/bin/bash
#######################################
# Description:
#   Remove Cursor-unsupported PascalCase hook event keys from .cursor/hooks.json.
#
#   Cursor requires camelCase event names (stop / preToolUse / postToolUse).
#   APM may merge Claude-format keys (Stop / PreToolUse / PostToolUse) into the
#   same file when both targets are installed; those keys must be stripped.
#
# Usage:
#   bash strip_cursor_unsupported_hook_events.sh [hooks.json]
#
#   hooks.json  Optional path (default: <repo>/.cursor/hooks.json)
#
# Exit codes:
#   0  Success (including missing file / already clean)
#   1  Invalid JSON, missing jq, or write failure
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

HOOKS_JSON="${1:-${WORKSPACE_ROOT}/.cursor/hooks.json}"

readonly UNSUPPORTED_EVENTS=(
    Stop
    PostToolUse
    PreToolUse
)

#######################################
# require_jq: Ensure jq is available
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Error message to stderr when jq is missing
#
# Returns:
#   0 when jq exists; 1 otherwise
#
#######################################
function require_jq {
    if ! command -v jq > /dev/null 2>&1; then
        echo "ERROR: jq is required to strip unsupported Cursor hook events" >&2
        return 1
    fi
}

#######################################
# strip_unsupported_events: Delete PascalCase hook keys from a hooks.json file
#
# Globals:
#   UNSUPPORTED_EVENTS
#
# Arguments:
#   $1 - Path to hooks.json
#
# Outputs:
#   Status line to stdout
#
# Returns:
#   0 on success; 1 on jq/write failure
#
#######################################
function strip_unsupported_events {
    local hooks_json="$1"
    local tmp_json
    local deleted_count
    local filter
    local event

    filter='.hooks // {}'
    for event in "${UNSUPPORTED_EVENTS[@]}"; do
        filter+=" | del(.${event})"
    done
    filter="{version: (.version // 1), hooks: (${filter})}"

    tmp_json="$(mktemp "${hooks_json}.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -f '${tmp_json}'" RETURN

    if ! jq "${filter}" "${hooks_json}" > "${tmp_json}"; then
        echo "ERROR: failed to rewrite ${hooks_json}" >&2
        return 1
    fi

    deleted_count="$(
        jq -r --argjson keys "$(printf '%s\n' "${UNSUPPORTED_EVENTS[@]}" | jq -R . | jq -s .)" '
            [.hooks // {} | keys[] | select(. as $k | $keys | index($k))] | length
        ' "${hooks_json}"
    )"

    mv "${tmp_json}" "${hooks_json}"
    trap - RETURN

    if [[ ${deleted_count} -gt 0 ]]; then
        echo "strip_cursor_unsupported_hook_events: removed ${deleted_count} unsupported key(s) from ${hooks_json}"
    else
        echo "strip_cursor_unsupported_hook_events: ${hooks_json} already clean"
    fi
}

#######################################
# main: Strip unsupported events from the target hooks.json
#
# Globals:
#   HOOKS_JSON
#
# Arguments:
#   None (path taken from HOOKS_JSON / argv at script load)
#
# Outputs:
#   Status line to stdout
#
# Returns:
#   0 on success; 1 on failure
#
#######################################
function main {
    require_jq

    if [[ ! -f ${HOOKS_JSON} ]]; then
        echo "strip_cursor_unsupported_hook_events: ${HOOKS_JSON} not found; skipping"
        return 0
    fi

    strip_unsupported_events "${HOOKS_JSON}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
