#!/bin/bash
#######################################
# Description:
#   Normalize Create PR inputs and compose hybrid PR body markdown.
#   Mirrors the loop-finalize Create PR step prelude so bats can cover
#   JSON defaulting without embedding action.yml snippets.
#
# Usage:
#   PR_BODY=... DETECT_RESULT_JSON=... NOTIFY_CONTEXT_JSON=... \
#   LEVEL=... SKIP_REASON=... TARGET_JSON=... \
#   bash lib/create_pr_body.sh
#
# Design Rules:
#   - Default empty JSON with quoted "{}" — never ${VAR:-{}} (bash closes early)
#   - Invalid JSON falls back to {}
#   - Delegates composition to render_pr_body.sh
#
# Output:
#   Full PR body markdown on stdout
#
# Dependencies:
#   - bash, jq, render_pr_body.sh (same directory)
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
DETECT_RESULT_JSON="${DETECT_RESULT_JSON:-}"
LEVEL="${LEVEL:-}"
NOTIFY_CONTEXT_JSON="${NOTIFY_CONTEXT_JSON:-}"
PR_BODY="${PR_BODY:-}"
SKIP_REASON="${SKIP_REASON:-}"
TARGET_JSON="${TARGET_JSON:-}"

#######################################
# normalize_json_object: Return valid JSON object or {}
#
# Description:
#   Accept a JSON string. Empty or invalid input becomes {}.
#   Callers must pass defaults as quoted "{}" — not ${VAR:-{}}.
#
# Arguments:
#   $1 - Raw JSON string (may be empty)
#
# Global Variables:
#   None
#
# Returns:
#   JSON object text on stdout
#
#######################################
function normalize_json_object {
    local raw="${1:-}"

    if [[ -z ${raw} ]] || ! jq -e . > /dev/null 2>&1 <<< "${raw}"; then
        printf '%s' '{}'
        return 0
    fi
    printf '%s' "${raw}"
}

#######################################
# create_pr_body: Normalize inputs and render PR body
#
# Description:
#   Apply Create PR JSON defaults, extract notify fields, export renderer
#   env, and print composed markdown.
#
# Arguments:
#   None
#
# Global Variables:
#   DETECT_RESULT_JSON - Detect JSON (optional)
#   LEVEL - Footer level
#   NOTIFY_CONTEXT_JSON - Notify context JSON (optional)
#   PR_BODY - Caller static prefix
#   SKIP_REASON - Footer skip reason
#   TARGET_JSON - Target JSON with .key (optional)
#
# Returns:
#   Composed PR body on stdout
#
#######################################
function create_pr_body {
    local notify_json detect_json target_json
    local script_dir

    # Quoted "{}" defaults — ${VAR:-{}} appends a literal "}" and corrupts JSON.
    notify_json="$(normalize_json_object "${NOTIFY_CONTEXT_JSON:-"{}"}")"
    detect_json="$(normalize_json_object "${DETECT_RESULT_JSON:-"{}"}")"
    target_json="$(normalize_json_object "${TARGET_JSON:-"{}"}")"

    CHANGED_FILES_JSON="$(jq -c '.changed_files // []' <<< "${notify_json}")"
    AGENT_REPORT_SUMMARY="$(jq -r '.agent_report_summary // empty' <<< "${notify_json}")"
    TARGET_KEY="$(jq -r '.key // empty' <<< "${target_json}" 2> /dev/null || true)"

    export PR_BODY_PREFIX="${PR_BODY}"
    export DETECT_RESULT_JSON="${detect_json}"
    export CHANGED_FILES_JSON
    export AGENT_REPORT_SUMMARY
    export LEVEL
    export TARGET_KEY
    export SKIP_REASON

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    bash "${script_dir}/render_pr_body.sh"
}

#######################################
# main: Entry point
#######################################
function main {
    create_pr_body
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
