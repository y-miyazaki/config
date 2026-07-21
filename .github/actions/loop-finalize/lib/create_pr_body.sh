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
#   Large payloads: pass file paths as CLI arguments (avoids ARG_MAX / MAX_ARG_STRLEN):
#   bash lib/create_pr_body.sh --detect-json-file /path/a --notify-json-file /path/b
#
# Design Rules:
#   - Default empty JSON with quoted "{}" — never ${VAR:-{}} (bash closes early)
#   - Invalid JSON falls back to {}
#   - Detect JSON is slimmed to failures[] before render (commits[] may be 100s of KB)
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

_JSON_FILE_DETECT=""
_JSON_FILE_NOTIFY=""
_JSON_FILE_TARGET=""

#######################################
# parse_create_pr_body_args: Parse optional JSON file path arguments
#
# Globals:
#   _JSON_FILE_DETECT - Path to detect JSON payload (set)
#   _JSON_FILE_NOTIFY - Path to notify JSON payload (set)
#   _JSON_FILE_TARGET - Path to target JSON payload (set)
#
# Arguments:
#   $@ - CLI arguments
#
# Outputs:
#   None
#
# Returns:
#   Exits 2 on unknown arguments
#
#######################################
function parse_create_pr_body_args {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --detect-json-file)
                _JSON_FILE_DETECT="${2:?--detect-json-file requires a path}"
                shift 2
                ;;
            --notify-json-file)
                _JSON_FILE_NOTIFY="${2:?--notify-json-file requires a path}"
                shift 2
                ;;
            --target-json-file)
                _JSON_FILE_TARGET="${2:?--target-json-file requires a path}"
                shift 2
                ;;
            -h | --help)
                printf '%s\n' \
                    "Usage: create_pr_body.sh [--detect-json-file PATH] [--notify-json-file PATH] [--target-json-file PATH]"
                exit 0
                ;;
            *)
                printf 'create_pr_body.sh: unknown argument: %s\n' "$1" >&2
                exit 2
                ;;
        esac
    done
}

#######################################
# normalize_json_object: Return valid JSON object or {}
#
# Description:
#   Accept a JSON string. Empty or invalid input becomes {}.
#   Callers must pass defaults as quoted "{}" — not ${VAR:-{}}.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Raw JSON string (may be empty)
#
# Outputs:
#   JSON object text to stdout
#
# Returns:
#   0 on success
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
# read_json_payload: Load JSON from file or inline string
#
# Globals:
#   None
#
# Arguments:
#   $1 - Optional file path
#   $2 - Inline JSON fallback
#
# Outputs:
#   Raw JSON text to stdout (may be empty)
#
# Returns:
#   0 on success
#
#######################################
function read_json_payload {
    local file_path="${1:-}"
    local inline="${2:-}"

    if [[ -n ${file_path} && -f ${file_path} ]]; then
        cat "${file_path}"
        return 0
    fi
    printf '%s' "${inline}"
}

#######################################
# slim_detect_json_for_pr_body: Keep only failures[] for PR rendering
#
# Globals:
#   None
#
# Arguments:
#   $1 - Detect result JSON object string
#
# Outputs:
#   Small JSON with failures array to stdout
#
# Returns:
#   0 on success
#
#######################################
function slim_detect_json_for_pr_body {
    local detect_json="${1:-}"

    if [[ -z ${detect_json} ]] || ! jq -e . > /dev/null 2>&1 <<< "${detect_json}"; then
        printf '%s' '{}'
        return 0
    fi
    jq -c '{failures: (.failures // [])}' <<< "${detect_json}"
}

#######################################
# create_pr_body: Normalize inputs and render PR body
#
# Description:
#   Apply Create PR JSON defaults, extract notify fields, export renderer
#   env, and print composed markdown.
#
# Globals:
#   DETECT_RESULT_JSON - Detect JSON (optional)
#   LEVEL - Footer level
#   NOTIFY_CONTEXT_JSON - Notify context JSON (optional)
#   PR_BODY - Caller static prefix
#   SKIP_REASON - Footer skip reason
#   TARGET_JSON - Target JSON with .key (optional)
#
# Arguments:
#   None
#
# Outputs:
#   Composed PR body to stdout
#
# Returns:
#   0 on success
#
#######################################
function create_pr_body {
    local notify_json detect_json target_json
    local script_dir

    # Quoted "{}" defaults — ${VAR:-{}} appends a literal "}" and corrupts JSON.
    notify_json="$(normalize_json_object "$(read_json_payload "${_JSON_FILE_NOTIFY}" "${NOTIFY_CONTEXT_JSON:-"{}"}")")"
    detect_json="$(slim_detect_json_for_pr_body "$(normalize_json_object "$(read_json_payload "${_JSON_FILE_DETECT}" "${DETECT_RESULT_JSON:-"{}"}")")")"
    target_json="$(normalize_json_object "$(read_json_payload "${_JSON_FILE_TARGET}" "${TARGET_JSON:-"{}"}")")"

    CHANGED_FILES_JSON="$(jq -c '.changed_files // []' <<< "${notify_json}")"
    AGENT_REPORT_OVERVIEW="$(jq -r '.agent_report_overview // empty' <<< "${notify_json}")"
    AGENT_REPORT_SUMMARY="$(jq -r '.agent_report_summary // empty' <<< "${notify_json}")"
    AGENT_REPORT_VERIFICATION="$(jq -r '.agent_report_verification // empty' <<< "${notify_json}")"
    TARGET_KEY="$(jq -r '.key // empty' <<< "${target_json}" 2> /dev/null || true)"

    export PR_BODY_PREFIX="${PR_BODY}"
    export DETECT_RESULT_JSON="${detect_json}"
    export CHANGED_FILES_JSON
    export AGENT_REPORT_OVERVIEW
    export AGENT_REPORT_SUMMARY
    export AGENT_REPORT_VERIFICATION
    export LEVEL
    export TARGET_KEY
    export SKIP_REASON

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    bash "${script_dir}/render_pr_body.sh"
}

#######################################
# main: Entry point
#
# Globals:
#   None
#
# Arguments:
#   $@ - Optional --detect-json-file / --notify-json-file / --target-json-file
#
# Outputs:
#   Composed PR body markdown to stdout
#
# Returns:
#   0 on success
#
#######################################
function main {
    if [[ $# -gt 0 ]]; then
        parse_create_pr_body_args "$@"
    fi
    create_pr_body
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
