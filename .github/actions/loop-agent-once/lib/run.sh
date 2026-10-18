#!/bin/bash
#######################################
# Description: One-shot agent session for loop-agent-once (L1)
#
# Usage:
#   AGENT_TOKEN=... AGENT_ENGINE=... PROMPT=... bash lib/run.sh
#
# Output:
#   Agent stdout; usage_json and message_json on GITHUB_OUTPUT when set
#
# Design Rules:
#   - Delegates CLI execution to loop-execute/lib/agent.sh
#   - Reuses loop-execute usage capture (Cursor stream-json)
#   - Avoid pipe subshells so USAGE_* globals persist
#   - The action passes AGENT_MAKER_MODEL / AGENT_MAKER_EFFORT /
#     AGENT_MAKER_MAX_TURNS; run_loop_agent_once assigns them to the shared
#     role variables MODEL / EFFORT / MAX_TURNS before run_agent (same as the
#     maker in loop-execute/lib/loop.sh)
#
# Dependencies:
#   - bash, jq, openssl, npx
#   - lib/loop/loop_message.sh (loop_message_to_json)
#   - loop-execute lib (agent.sh, usage.sh) via _init.sh
#
# Optional environment:
#   AGENT_ENGINE, AGENT_MAKER_EFFORT, AGENT_MAKER_MAX_TURNS, AGENT_MAKER_MODEL,
#   AGENT_TOKEN, AGENT_TOOL_ALLOWLIST, GITHUB_TOKEN, OUTPUT_FILE, PROMPT,
#   WORKING_DIRECTORY, GITHUB_OUTPUT
#   LOOP_MESSAGE_DIR: directory the agent writes message.md / message_labels.json
#   into (claude only); it is collected into the message_json output and delivered
#   later by loop-finalize. This action never posts to GitHub.
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
# shellcheck source=../../lib/loop/loop_message.sh disable=SC1091
source "${LIB_DIR}/../../lib/loop/loop_message.sh"

#######################################
# Global variables
#######################################
# Environment supplied by loop-agent-once composite action.
AGENT_ENGINE="${AGENT_ENGINE-}"
AGENT_TOKEN="${AGENT_TOKEN-}"
GITHUB_TOKEN="${GITHUB_TOKEN-}"
LOOP_MESSAGE_DIR="${LOOP_MESSAGE_DIR:-}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
PROMPT="${PROMPT-}"
WORKING_DIRECTORY="${WORKING_DIRECTORY:-.}"

#######################################
# emit_message_json_output: Write the agent's message files to GITHUB_OUTPUT as message_json
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file
#   LOOP_MESSAGE_DIR - Directory holding message.md / message_labels.json
#
# Arguments:
#   None
#
# Outputs:
#   message_json key on GITHUB_OUTPUT (empty when nothing is deliverable)
#
# Returns:
#   0 on success
#
#######################################
function emit_message_json_output {
    local message_json delim

    [[ -n ${GITHUB_OUTPUT:-} ]] || return 0
    message_json=""
    if [[ -n ${LOOP_MESSAGE_DIR:-} ]]; then
        message_json="$(loop_message_to_json "${LOOP_MESSAGE_DIR}")"
    fi
    if [[ -n ${message_json} ]]; then
        delim="MESSAGE_JSON_$(openssl rand -hex 8)"
        {
            echo "message_json<<${delim}"
            echo "${message_json}"
            echo "${delim}"
        } >> "${GITHUB_OUTPUT}"
    else
        echo "message_json=" >> "${GITHUB_OUTPUT}"
    fi
}

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
# prepare_loop_message_dir: Create the message directory and point the prompt at it
#
# Globals:
#   LOOP_MESSAGE_DIR - Directory the agent writes its message files into (read)
#   PROMPT - Prompt text (write)
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function prepare_loop_message_dir {
    [[ -n ${LOOP_MESSAGE_DIR:-} ]] || return 0
    mkdir -p "${LOOP_MESSAGE_DIR}"
    PROMPT="${PROMPT}"$'\n\n'"Loop message directory: ${LOOP_MESSAGE_DIR}"
    export PROMPT
}

#######################################
# run_loop_agent_once: Run one engine CLI session and emit usage_json and message_json
#
# Description:
#   Maps the caller's maker settings onto the role variables run_agent reads
#   (EFFORT, MAX_TURNS, MODEL). Without this assignment an L1 session would
#   silently fall back to the engine CLI defaults.
#
# Globals:
#   AGENT_ENGINE, AGENT_TOKEN, GITHUB_TOKEN, LOOP_MESSAGE_DIR, OUTPUT_FILE,
#   WORKING_DIRECTORY, GITHUB_OUTPUT (read)
#   PROMPT (read, write: the message directory is appended)
#   AGENT_MAKER_EFFORT, AGENT_MAKER_MAX_TURNS, AGENT_MAKER_MODEL (read)
#   EFFORT, MAX_TURNS, MODEL (write)
#
# Arguments:
#   None
#
# Outputs:
#   Agent stdout (summarized for Cursor stream-json); usage_json and message_json on GITHUB_OUTPUT
#
# Returns:
#   Engine CLI exit code
#
#######################################
function run_loop_agent_once {
    local rc=0

    EFFORT="${AGENT_MAKER_EFFORT:-}"
    MAX_TURNS="${AGENT_MAKER_MAX_TURNS:-}"
    MODEL="${AGENT_MAKER_MODEL:-}"
    export EFFORT MAX_TURNS MODEL

    prepare_loop_message_dir
    reset_usage_totals
    if [[ -n ${OUTPUT_FILE} ]]; then
        run_agent_capture "${OUTPUT_FILE}" "true" || rc=$?
    else
        run_agent "true" || rc=$?
    fi
    emit_usage_json_output
    emit_message_json_output
    return "${rc}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    run_loop_agent_once
fi
