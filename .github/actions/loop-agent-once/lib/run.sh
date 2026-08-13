#!/bin/bash
#######################################
# Description: One-shot agent session for loop-agent-once (L1)
#
# Usage:
#   AGENT_TOKEN=... ENGINE=... PROMPT=... bash lib/run.sh
#
# Output:
#   Agent stdout; usage_json on GITHUB_OUTPUT when set
#
# Design Rules:
#   - Delegates CLI execution to loop-execute/lib/agent.sh
#   - Reuses loop-execute usage capture (Cursor stream-json)
#   - Avoid pipe subshells so USAGE_* globals persist
#
# Dependencies:
#   - bash, jq, openssl, npx
#   - loop-execute lib (agent.sh, usage.sh) via _init.sh
#
# Optional environment:
#   AGENT_TOKEN, ENGINE, GITHUB_TOKEN, MAX_TURNS, MODEL, OUTPUT_FILE,
#   PROMPT, WORKING_DIRECTORY, GITHUB_OUTPUT
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load initialization library
# shellcheck source=./_init.sh disable=SC1091
source "${SCRIPT_DIR}/_init.sh"

#######################################
# Global variables
#######################################
# Environment supplied by loop-agent-once composite action.
AGENT_TOKEN="${AGENT_TOKEN-}"
ENGINE="${ENGINE-}"
GITHUB_TOKEN="${GITHUB_TOKEN-}"
MAX_TURNS="${MAX_TURNS:-}"
MODEL="${MODEL:-}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
PROMPT="${PROMPT-}"
WORKING_DIRECTORY="${WORKING_DIRECTORY:-.}"

#######################################
# emit_usage_json_output: Write measured usage to GITHUB_OUTPUT
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file
#   USAGE_* - Totals from usage.sh
#
# Arguments:
#   None
#
# Outputs:
#   usage_json key on GITHUB_OUTPUT
#
# Returns:
#   0 on success
#
#######################################
function emit_usage_json_output {
    local usage_json delim

    [[ -n ${GITHUB_OUTPUT:-} ]] || return 0
    usage_json="$(build_usage_json)"
    if [[ -n ${usage_json} ]]; then
        delim="USAGE_JSON_$(openssl rand -hex 8)"
        {
            echo "usage_json<<${delim}"
            echo "${usage_json}"
            echo "${delim}"
        } >> "${GITHUB_OUTPUT}"
    else
        echo "usage_json=" >> "${GITHUB_OUTPUT}"
    fi
}

#######################################
# run_loop_agent_once: Run one engine CLI session and emit usage_json
#
# Globals:
#   AGENT_TOKEN, ENGINE, GITHUB_TOKEN, MAX_TURNS, MODEL, OUTPUT_FILE, PROMPT,
#   WORKING_DIRECTORY, GITHUB_OUTPUT
#
# Arguments:
#   None
#
# Outputs:
#   Agent stdout (summarized for Cursor stream-json); usage_json on GITHUB_OUTPUT
#
# Returns:
#   Engine CLI exit code
#
#######################################
function run_loop_agent_once {
    local rc=0

    reset_usage_totals
    if [[ -n ${OUTPUT_FILE} ]]; then
        run_agent_capture "${OUTPUT_FILE}" "true" || rc=$?
    else
        run_agent "true" || rc=$?
    fi
    emit_usage_json_output
    return "${rc}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    run_loop_agent_once
fi
