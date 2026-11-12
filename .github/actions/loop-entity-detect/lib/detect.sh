#!/bin/bash
#######################################
# Description: Single-entity loop detection for loop-entity-detect action
#
# Usage: bash lib/detect.sh
#
# Output:
# - Writes should_run, skip_reason, delivery, pr_auto_merge, target_matrix to GITHUB_OUTPUT
#
# Design Rules:
# - Pins DETECT_SCRIPT to an absolute path before invocation
# - Invokes detect_script once per entity event (caller never re-runs)
# - Large payloads live in loop-handoff artifact; matrix output stays slim
# - Detect-script boundary: non-zero exit fails the step without skip_reason
# - level and delivery have no defaults; invalid level-keyed inputs fail the step
# - skip=false requires result.entity.kind issue | pr, allowed by delivery (delivery_validate_target)
#
# Dependencies:
# - bash, jq, openssl
#
# Optional environment:
#   DETECT_SCRIPT, LOOP_NAME, AGENT_MAKER_SKILL_NAME, AGENT_MAKER_INSTRUCTIONS, LEVEL, DELIVERY
#   AGENT_EDIT_TARGET, AGENT_EDIT_ALLOWLIST, AGENT_EDIT_DENYLIST, AGENT_UNCHANGED_VERDICT
#   BUDGET_FILE, BUDGET_MAX_RUNS_PER_DAY, BUDGET_MAX_TOKENS_PER_DAY, RUN_LOG_FILE, STATE_FILE
#   GITHUB_TOKEN (detect token)
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
# KEY=VALUE entries from detect_env_json, filled by loop_build_detect_env_args (detect_env.sh).
LOOP_DETECT_ENV_ARGS=()
LOOP_NAME="${LOOP_NAME-}"
AGENT_MAKER_SKILL_NAME="${AGENT_MAKER_SKILL_NAME-}"
AGENT_MAKER_INSTRUCTIONS="${AGENT_MAKER_INSTRUCTIONS:-}"
LEVEL="${LEVEL-}"
DELIVERY="${DELIVERY-}"
AGENT_EDIT_TARGET="${AGENT_EDIT_TARGET-}"
AGENT_EDIT_ALLOWLIST="${AGENT_EDIT_ALLOWLIST-}"
AGENT_EDIT_DENYLIST="${AGENT_EDIT_DENYLIST-}"
AGENT_UNCHANGED_VERDICT="${AGENT_UNCHANGED_VERDICT-}"
HANDOFF_DIR="${RUNNER_TEMP:-/tmp}/loop-handoff"
DETECT_OUT="${RUNNER_TEMP:-/tmp}/entity-detect.json"

#######################################
# read_entity_target_state: Read one target's state from a state file snapshot
#
# Description:
#   Reads the given file (the state-branch snapshot made by main). A missing file, an unreadable file or a missing
#   target gives {} (no state), so the circuit breaker is not open for a target without history.
#
# Globals:
#   None
#
# Arguments:
#   $1 - State file path (may be empty)
#   $2 - Target key
#
# Outputs:
#   Target state JSON on stdout ({} when none)
#
# Returns:
#   0 always
#
#######################################
function read_entity_target_state {
    local state_file="${1:-}"
    local target_key="$2"

    if [[ -z ${state_file} || ! -f ${state_file} ]]; then
        printf '{}'
        return 0
    fi
    jq -c --arg key "${target_key}" '.targets[$key] // {}' "${state_file}" 2> /dev/null || printf '{}'
}

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
#   $2 - skip_detail (optional)
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
    local skip_detail="${2:-}"

    write_entity_detect_outputs "false" "${skip_reason}" "[]" "${skip_detail}"
    exit 0
}

#######################################
# main: Run entity detect and publish matrix/handoff outputs
#
# Globals:
#   DETECT_SCRIPT, LOOP_NAME, AGENT_MAKER_SKILL_NAME, AGENT_MAKER_INSTRUCTIONS, LEVEL, DELIVERY
#   AGENT_EDIT_TARGET, AGENT_EDIT_ALLOWLIST, AGENT_EDIT_DENYLIST, AGENT_UNCHANGED_VERDICT
#   GITHUB_TOKEN
#   BUDGET_FILE, BUDGET_MAX_RUNS_PER_DAY, BUDGET_MAX_TOKENS_PER_DAY, RUN_LOG_FILE
#   STATE_BRANCH, STATE_FILE - The state file and run log are read from origin/<STATE_BRANCH>
#   HANDOFF_DIR, DETECT_OUT
#
# Arguments:
#   None
#
# Outputs:
#   should_run, skip_reason, delivery, pr_auto_merge, target_matrix on GITHUB_OUTPUT
#
# Returns:
#   0 on success or skip; exits 1 when input, entity kind, or target validation fails
#
#######################################
function main {
    local full_matrix target_matrix candidate detect_status handoff_key skip_reason verdict

    if [[ -z ${LOOP_NAME} || -z ${AGENT_MAKER_SKILL_NAME} ]]; then
        echo "::error::LOOP_NAME and AGENT_MAKER_SKILL_NAME are required" >&2
        exit 1
    fi

    local loop_action_lib
    loop_action_lib="$(cd "${SCRIPT_DIR}/../../lib/loop" && pwd)"
    # shellcheck source=../../lib/loop/validate_loop_write_contract.sh disable=SC1091
    source "${loop_action_lib}/validate_loop_write_contract.sh"
    # A configuration error fails the job (no outputs written).
    if ! validate_loop_write_contract "${LEVEL}" "${DELIVERY}" "${AGENT_EDIT_TARGET}" \
        "${AGENT_EDIT_ALLOWLIST}" "${AGENT_EDIT_DENYLIST}" "${AGENT_UNCHANGED_VERDICT}" \
        "${FINALIZE_SCRIPT:-}" "${FINALIZE_LABEL_ALLOWLIST:-}"; then
        exit 1
    fi
    if ! delivery_validate_value "${DELIVERY}"; then
        exit 1
    fi

    if ! resolve_detect_script_path; then
        exit 1
    fi
    # shellcheck source=../../lib/loop/detect_env.sh disable=SC1091
    source "${loop_action_lib}/detect_env.sh"
    if ! loop_build_detect_env_args "${DETECT_ENV_JSON:-}"; then
        exit 1
    fi

    # Snapshot the state and the run log from the state branch; the budget file is policy and stays on the trusted checkout.
    local state_read_file run_log_read_file
    local -a snapshot_pairs=("${RUN_LOG_FILE:-.loop/loop-run-log.md}" "")
    state_read_file="$(mktemp)"
    run_log_read_file="$(mktemp)"
    snapshot_pairs[1]="${run_log_read_file}"
    if [[ -n ${STATE_FILE:-} ]]; then
        snapshot_pairs+=("${STATE_FILE}" "${state_read_file}")
    fi
    if ! state_snapshot_from_branch "${STATE_BRANCH:?STATE_BRANCH is required}" "${snapshot_pairs[@]}"; then
        exit 1
    fi

    if admission_budget_exceeded "${LOOP_NAME}" "${BUDGET_FILE:-.loop/loop-budget.json}" \
        "${run_log_read_file}" \
        "${BUDGET_MAX_RUNS_PER_DAY:-}" "${BUDGET_MAX_TOKENS_PER_DAY:-}"; then
        write_entity_skip_outputs "budget"
    fi

    env "${LOOP_DETECT_ENV_ARGS[@]}" bash "${DETECT_SCRIPT}" > "${DETECT_OUT}"
    detect_status="$(jq -r '.status // "error"' "${DETECT_OUT}")"
    if [[ ${detect_status} != "ok" ]]; then
        echo "::error::entity detect failed: status=$(jq -r '.status // "error"' "${DETECT_OUT}") message=$(jq -r '.message // ""' "${DETECT_OUT}")" >&2
        exit 1
    fi

    # Validate the entity kind and target before writing outputs.
    if ! full_matrix="$(build_entity_target_matrix \
        "${DETECT_OUT}" \
        "${LOOP_NAME}" \
        "${AGENT_MAKER_SKILL_NAME}" \
        "${AGENT_MAKER_INSTRUCTIONS}" \
        "${LEVEL}" \
        "${DELIVERY}" \
        "${AGENT_EDIT_TARGET}" \
        "${AGENT_EDIT_ALLOWLIST}")"; then
        exit 1
    fi
    if [[ $(jq 'length' <<< "${full_matrix}") -gt 0 ]] \
        && ! delivery_validate_target "${DELIVERY}" "$(jq -c '.[0].target_json' <<< "${full_matrix}")"; then
        exit 1
    fi

    if [[ $(jq 'length' <<< "${full_matrix}") -eq 0 ]]; then
        write_entity_skip_outputs "$(resolve_entity_skip_reason "${DETECT_OUT}")" \
            "$(resolve_entity_skip_detail "${DETECT_OUT}")"
    fi

    handoff_key="$(jq -r '.[0].target_json.key' <<< "${full_matrix}")"
    verdict="$(admission_evaluate "$(jq -c '.result.gate // null' "${DETECT_OUT}")" \
        "$(read_entity_target_state "${state_read_file}" "${handoff_key}")")"
    if [[ $(jq -r '.admit' <<< "${verdict}") != "true" ]]; then
        write_entity_skip_outputs "$(jq -r '.skip_reason' <<< "${verdict}")" \
            "$(jq -r '.detail' <<< "${verdict}")"
    fi

    handoff_init_bundle "${HANDOFF_DIR}" > /dev/null
    candidate="$(jq -c '.[0]' <<< "${full_matrix}")"
    if ! handoff_write_candidate_payload "${HANDOFF_DIR}" "${candidate}"; then
        echo "::error::failed to write entity handoff payload" >&2
        exit 1
    fi

    target_matrix="$(shrink_entity_matrix_for_output "${full_matrix}")"
    write_entity_detect_outputs "true" "" "${target_matrix}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
