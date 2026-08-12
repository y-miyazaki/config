#!/bin/bash
#######################################
# Description: Single-entity loop detection for loop-entity-detect action
#
# Usage: bash lib/detect.sh
#
# Output:
# - Writes should_run, skip_reason, target_matrix to GITHUB_OUTPUT
#
# Design Rules:
# - Pins DETECT_SCRIPT to an absolute path before invocation
# - Invokes detect_script once per entity event (caller never re-runs)
# - Large payloads live in loop-handoff artifact; matrix output stays slim
# - Detect-script boundary: non-zero exit fails the step without skip_reason
#
# Dependencies:
# - bash, jq, openssl
#
# Optional environment:
#   DETECT_SCRIPT, LOOP_NAME, SKILL_NAME, PROMPT_INSTRUCTIONS, LEVEL, DELIVERY
#   BUDGET_FILE, BUDGET_MAX_RUNS_PER_DAY, BUDGET_MAX_TOKENS_PER_DAY, RUN_LOG_FILE
#   DISPATCH_HOOK_SCRIPT, DISPATCH_HOOK_TOKEN (trusted post-detect dispatch hook)
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
# Environment supplied by loop-entity-detect composite action (validated in main).
DETECT_SCRIPT="${DETECT_SCRIPT-}"
LOOP_NAME="${LOOP_NAME-}"
SKILL_NAME="${SKILL_NAME-}"
PROMPT_INSTRUCTIONS="${PROMPT_INSTRUCTIONS:-}"
LEVEL="${LEVEL:-L1}"
DELIVERY="${DELIVERY:-none}"
DISPATCH_HOOK_SCRIPT="${DISPATCH_HOOK_SCRIPT:-}"
DISPATCH_HOOK_TOKEN="${DISPATCH_HOOK_TOKEN:-}"
HANDOFF_DIR="${RUNNER_TEMP:-/tmp}/loop-handoff"
DETECT_OUT="${RUNNER_TEMP:-/tmp}/entity-detect.json"

#######################################
# resolve_detect_script_path: Pin DETECT_SCRIPT to an absolute path
#
# Globals:
#   DETECT_SCRIPT - Updated in place to an absolute path
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success; non-zero when the script cannot be resolved
#
#######################################
function resolve_detect_script_path {
    local resolved

    if [[ -z ${DETECT_SCRIPT} ]]; then
        echo "::error::DETECT_SCRIPT is empty" >&2
        return 1
    fi

    if [[ ${DETECT_SCRIPT} == /* ]]; then
        resolved="${DETECT_SCRIPT}"
    else
        resolved="$(pwd)/${DETECT_SCRIPT}"
    fi

    if [[ ! -f ${resolved} ]]; then
        echo "::error::DETECT_SCRIPT not found: ${resolved}" >&2
        return 1
    fi

    if command -v realpath > /dev/null 2>&1; then
        resolved="$(realpath "${resolved}")"
    else
        resolved="$(cd "$(dirname "${resolved}")" && pwd)/$(basename "${resolved}")"
    fi

    DETECT_SCRIPT="${resolved}"
}

#######################################
# write_entity_skip_outputs: Emit skip outputs and exit successfully
#
# Globals:
#   None
#
# Arguments:
#   $1 - skip_reason
#
# Outputs:
#   should_run=false on GITHUB_OUTPUT
#
# Returns:
#   Exits 0
#
#######################################
function write_entity_skip_outputs {
    local skip_reason="$1"

    write_entity_detect_outputs "false" "${skip_reason}" "[]"
    exit 0
}

#######################################
# resolve_dispatch_hook_script: Pin and confine trusted dispatch hook path
#
# Globals:
#   GITHUB_WORKSPACE
#
# Arguments:
#   $1 - Hook script path from DISPATCH_HOOK_SCRIPT
#
# Outputs:
#   Absolute confined hook path on stdout
#
# Returns:
#   0 on success; non-zero when the hook path is invalid
#
#######################################
function resolve_dispatch_hook_script {
    local hook_script="$1"
    local workspace="${GITHUB_WORKSPACE:-$(pwd)}"

    if [[ -z ${hook_script} ]]; then
        echo "::error::DISPATCH_HOOK_SCRIPT is empty" >&2
        return 1
    fi

    if [[ ${hook_script} != /* ]]; then
        hook_script="$(pwd)/${hook_script}"
    fi

    if command -v realpath > /dev/null 2>&1; then
        hook_script="$(realpath "${hook_script}")"
    fi

    if [[ -z ${workspace} || ${hook_script} != "${workspace}/"* ]]; then
        echo "::error::DISPATCH_HOOK_SCRIPT must be under GITHUB_WORKSPACE: ${hook_script}" >&2
        return 1
    fi

    if [[ ${hook_script} != */scripts/hooks/on_detect_dispatch.sh ]]; then
        echo "::error::DISPATCH_HOOK_SCRIPT must end with scripts/hooks/on_detect_dispatch.sh" >&2
        return 1
    fi

    if [[ ! -f ${hook_script} ]]; then
        echo "::error::DISPATCH_HOOK_SCRIPT not found: ${hook_script}" >&2
        return 1
    fi

    printf '%s' "${hook_script}"
}

#######################################
# main: Run entity detect and publish matrix/handoff outputs
#
# Globals:
#   DETECT_SCRIPT, LOOP_NAME, SKILL_NAME, PROMPT_INSTRUCTIONS, LEVEL, DELIVERY
#   BUDGET_FILE, BUDGET_MAX_RUNS_PER_DAY, BUDGET_MAX_TOKENS_PER_DAY, RUN_LOG_FILE
#   HANDOFF_DIR, DETECT_OUT
#
# Arguments:
#   None
#
# Outputs:
#   should_run, skip_reason, target_matrix on GITHUB_OUTPUT
#
# Returns:
#   0 on success
#
#######################################
function main {
    local full_matrix target_matrix candidate detect_status skip_reason

    if [[ -z ${LOOP_NAME} || -z ${SKILL_NAME} ]]; then
        echo "::error::LOOP_NAME and SKILL_NAME are required" >&2
        exit 1
    fi

    if ! resolve_detect_script_path; then
        exit 1
    fi

    if budget_exceeded "${LOOP_NAME}" "${BUDGET_FILE:-.loop/loop-budget.json}" \
        "${RUN_LOG_FILE:-.loop/loop-run-log.md}" \
        "${BUDGET_MAX_RUNS_PER_DAY:-}" "${BUDGET_MAX_TOKENS_PER_DAY:-}"; then
        write_entity_skip_outputs "budget"
    fi

    bash "${DETECT_SCRIPT}" > "${DETECT_OUT}"
    detect_status="$(jq -r '.status // "error"' "${DETECT_OUT}")"
    if [[ ${detect_status} != "ok" ]]; then
        echo "::error::entity detect failed: status=$(jq -r '.status // "error"' "${DETECT_OUT}") message=$(jq -r '.message // ""' "${DETECT_OUT}")" >&2
        exit 1
    fi

    # Invoke whenever dispatch_requested==true (even if skip=true), status already ok.
    if [[ -n ${DISPATCH_HOOK_SCRIPT} ]]; then
        local hook_script
        requested="$(jq -r '.result.dispatch_requested // false' "${DETECT_OUT}")"
        if [[ ${requested} == "true" ]]; then
            if ! hook_script="$(resolve_dispatch_hook_script "${DISPATCH_HOOK_SCRIPT}")"; then
                exit 1
            fi
            GH_TOKEN="${DISPATCH_HOOK_TOKEN:-${GH_TOKEN:-}}" \
                bash "${hook_script}" "${DETECT_OUT}"
        fi
    fi

    full_matrix="$(build_entity_target_matrix \
        "${DETECT_OUT}" \
        "${LOOP_NAME}" \
        "${SKILL_NAME}" \
        "${PROMPT_INSTRUCTIONS}" \
        "${LEVEL}" \
        "${DELIVERY}")"

    if [[ $(jq 'length' <<< "${full_matrix}") -eq 0 ]]; then
        write_entity_skip_outputs "detect_skip"
    fi

    loop_handoff_init_bundle "${HANDOFF_DIR}" > /dev/null
    candidate="$(jq -c '.[0]' <<< "${full_matrix}")"
    if ! loop_handoff_write_candidate_payload "${HANDOFF_DIR}" "${candidate}"; then
        echo "::error::failed to write entity handoff payload" >&2
        exit 1
    fi

    target_matrix="$(shrink_entity_matrix_for_output "${full_matrix}")"
    write_entity_detect_outputs "true" "" "${target_matrix}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
