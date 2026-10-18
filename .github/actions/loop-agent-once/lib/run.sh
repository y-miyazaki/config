#!/bin/bash
#######################################
# Description: One-shot agent session for loop-agent-once (L1)
#
# Usage:
#   AGENT_TOKEN=... AGENT_ENGINE=... PROMPT=... bash lib/run.sh
#
# Output:
#   Agent stdout; usage_json on GITHUB_OUTPUT when set
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
#   - loop-execute lib (agent.sh, usage.sh) via _init.sh
#
# Optional environment:
#   AGENT_ENGINE, AGENT_MAKER_EFFORT, AGENT_MAKER_MAX_TURNS, AGENT_MAKER_MODEL,
#   AGENT_TOKEN, AGENT_TOOL_ALLOWLIST, GITHUB_TOKEN, OUTPUT_FILE, PROMPT,
#   WORKING_DIRECTORY, GITHUB_OUTPUT
#   COMMENT_HANDOFF_KEY, COMMENT_MARKER, REPOSITORY, RUN_URL: when the handoff
#   key names an Issue (entity:issue:<n>), the captured agent text (OUTPUT_FILE) is posted as one Issue
#   comment with Meta and the footer, right after the usage is measured
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
AGENT_ENGINE="${AGENT_ENGINE-}"
AGENT_TOKEN="${AGENT_TOKEN-}"
GITHUB_TOKEN="${GITHUB_TOKEN-}"
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
# post_loop_comment: Post the captured agent text as one Issue comment with Meta and footer
#
# Description:
#   The agent ends its run with the comment text instead of posting it. Usage is
#   measured here, in the same stage, so the comment goes out once, complete.
#
# Globals:
#   COMMENT_HANDOFF_KEY - Entity handoff key naming the Issue to comment on (empty = do nothing)
#   COMMENT_MARKER - Skill marker placed first in the comment
#   OUTPUT_FILE - File holding the agent's stdout
#   AGENT_ENGINE, REPOSITORY, RUN_URL, GITHUB_TOKEN (read)
#
# Arguments:
#   $1 - Engine CLI exit code (0 = unchanged, else error)
#
# Outputs:
#   Notice or warning annotation on stdout
#
# Returns:
#   0 always (the comment is best-effort)
#
#######################################
function post_loop_comment {
    local rc="${1:-0}"
    local outcome="unchanged"
    local issue_number

    if [[ -z ${COMMENT_HANDOFF_KEY:-} || -z ${OUTPUT_FILE:-} ]]; then
        return 0
    fi
    [[ ${rc} -ne 0 ]] && outcome="error"

    # shellcheck source=../../lib/loop/created_by.sh disable=SC1091
    source "${LIB_DIR}/../../lib/loop/created_by.sh"
    # shellcheck source=../../lib/loop/loop_meta.sh disable=SC1091
    source "${LIB_DIR}/../../lib/loop/loop_meta.sh"
    # shellcheck source=../../lib/loop/entity_meta.sh disable=SC1091
    source "${LIB_DIR}/../../lib/loop/entity_meta.sh"

    issue_number="$(entity_issue_number "${COMMENT_HANDOFF_KEY}")"
    if [[ -z ${issue_number} ]]; then
        return 0
    fi

    GH_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}" post_entity_comment "${issue_number}" "${COMMENT_MARKER:-}" \
        "${OUTPUT_FILE}" "${outcome}" "${AGENT_ENGINE:-}" "$(build_usage_json)" "${RUN_URL:-}"
}

#######################################
# run_loop_agent_once: Run one engine CLI session and emit usage_json
#
# Description:
#   Maps the caller's maker settings onto the role variables run_agent reads
#   (EFFORT, MAX_TURNS, MODEL). Without this assignment an L1 session would
#   silently fall back to the engine CLI defaults.
#
# Globals:
#   AGENT_ENGINE, AGENT_TOKEN, GITHUB_TOKEN, OUTPUT_FILE, PROMPT,
#   WORKING_DIRECTORY, GITHUB_OUTPUT (read)
#   AGENT_MAKER_EFFORT, AGENT_MAKER_MAX_TURNS, AGENT_MAKER_MODEL (read)
#   EFFORT, MAX_TURNS, MODEL (write)
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

    EFFORT="${AGENT_MAKER_EFFORT:-}"
    MAX_TURNS="${AGENT_MAKER_MAX_TURNS:-}"
    MODEL="${AGENT_MAKER_MODEL:-}"
    export EFFORT MAX_TURNS MODEL

    reset_usage_totals
    if [[ -n ${OUTPUT_FILE} ]]; then
        run_agent_capture "${OUTPUT_FILE}" "true" || rc=$?
    else
        run_agent "true" || rc=$?
    fi
    emit_usage_json_output
    post_loop_comment "${rc}"
    return "${rc}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    run_loop_agent_once
fi
