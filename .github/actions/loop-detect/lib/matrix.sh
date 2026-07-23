#!/bin/bash
#######################################
# Description: Candidate assembly, prompts, and target_matrix output for loop-detect
#
# Usage: source "${LIB_DIR}/matrix.sh"
#
# Output:
# - None (library file; writes to GITHUB_OUTPUT via helpers)
#
# Design Rules:
# - Large payloads (result, verifier_context) live in loop-handoff artifact files
# - target_matrix carries handoff_key; execute resolves payloads by key
# - Implementer prompts use LOOP_DETECT_RESULT_MARKER; detect JSON is file-backed at execute
#######################################

#######################################
# Global variables
#######################################
LOOP_DETECT_RESULT_MARKER='__LOOP_DETECT_RESULT_JSON__'

_MATRIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_loop_action_lib="$(cd "${_MATRIX_LIB_DIR}/../../lib/loop" && pwd)"
if ! declare -f emit_loop_constraints > /dev/null 2>&1; then
    # shellcheck source=../../lib/loop/build_constraints.sh disable=SC1091
    source "${_loop_action_lib}/build_constraints.sh"
fi
if ! declare -f build_verifier_context_from_result > /dev/null 2>&1; then
    # shellcheck source=../../lib/loop/verifier_context.sh disable=SC1091
    source "${_loop_action_lib}/verifier_context.sh"
fi

#######################################
# build_prompt_text: Assemble implementer prompt for one candidate
#
# Globals:
#   None
#
# Arguments:
#   $1 - Skill name
#   $2 - Autonomy level
#   $3 - Allowlist csv
#   $4 - Prompt instructions
#   $5 - Last SHA
#   $6 - Current SHA
#   $7 - Detect result JSON
#   $8 - Open rejections prompt markdown
#   $9 - Consecutive failures count
#   $10 - may_edit (required when ## Constraints is emitted)
#   $11 - write_target (required when may_edit is true)
#   $12 - report_file (optional; falls back to detect JSON)
#
# Outputs:
#   Prompt text on stdout
#
# Returns:
#   0 on success
#
#######################################
function build_prompt_text {
    local skill_name="$1"
    local level="$2"
    local allowlist="$3"
    local prompt_instructions="$4"
    local last_sha="$5"
    local current_sha="$6"
    local detect_result="$7"
    local open_rejections_prompt="$8"
    local consecutive_failures="$9"
    local may_edit="${10:-}"
    local write_target="${11:-}"
    local report_file="${12:-}"

    if [[ -z ${report_file} ]]; then
        report_file="$(jq -r '.report_file // ""' <<< "${detect_result}" 2> /dev/null || echo "")"
    fi

    {
        echo "Run the ${skill_name} skill."
        echo ""
        echo "## Context"
        echo "Last SHA: ${last_sha}"
        echo "Current SHA: ${current_sha}"
        echo ""
        echo "## Change Detection Result"
        echo "${LOOP_DETECT_RESULT_MARKER}"
        echo "At execute time this is replaced with a runner-local JSON file path (not inlined JSON)."
        if [[ -n ${open_rejections_prompt} ]]; then
            echo ""
            echo "## Open Rejections from Previous Run"
            echo ""
            echo "The previous loop run left unresolved items (${consecutive_failures} consecutive failure(s)). Address these before proceeding with new work:"
            echo ""
            echo "${open_rejections_prompt}"
        fi
        if [[ -n ${prompt_instructions} ]]; then
            echo ""
            echo "## Instructions"
            echo "${prompt_instructions}"
        fi
        if [[ -n ${level} || -n ${allowlist} ]]; then
            echo ""
            if [[ -z ${may_edit} ]]; then
                echo "::error::may_edit is required for prompt constraints" >&2
                return 1
            fi
            emit_loop_constraints "${may_edit}" "${write_target}" "${allowlist}" "${report_file}"
        fi
    }
}

#######################################
# shrink_matrix_candidate_for_output: Trim matrix payload for job output limits
#
# Globals:
#   None
#
# Arguments:
#   $1 - Candidate JSON object string
#
# Outputs:
#   Compacted candidate JSON on stdout
#
# Returns:
#   0 on success
#
#######################################
function shrink_matrix_candidate_for_output {
    local candidate="$1"

    if ! jq -e . <<< "${candidate}" > /dev/null 2>&1; then
        printf '%s' "${candidate}"
        return 0
    fi

    jq -c '
        .handoff_key = (.target_json.key // "") |
        .verifier_context = "" |
        del(.result)
    ' <<< "${candidate}"
}

#######################################
# candidate_priority_rank: Echo numeric rank for mode (lower runs first)
#
# Globals:
#   LOOP_PRIORITY - Comma-separated mode order
#
# Arguments:
#   $1 - Target mode (integration|pull_request)
#
# Outputs:
#   Rank integer on stdout
#
# Returns:
#   0 on success
#
#######################################
function candidate_priority_rank {
    local mode="$1"
    local -a order=()
    local idx=0 found=0 token

    split_csv "${LOOP_PRIORITY}" order
    for token in "${order[@]}"; do
        idx=$((idx + 1))
        if [[ ${token} == "${mode}" ]]; then
            found="${idx}"
            break
        fi
    done
    if [[ ${found} -eq 0 ]]; then
        found=99
    fi
    printf '%s' "${found}"
}

#######################################
# sort_candidates_by_priority: Sort CANDIDATES_JSON by LOOP_PRIORITY
#
# Globals:
#   CANDIDATES_JSON - Array to sort in place
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
function sort_candidates_by_priority {
    if [[ ${#CANDIDATES_JSON[@]} -le 1 ]]; then
        return 0
    fi

    local -a sorted=()
    local candidate rank min_rank min_idx i

    while [[ ${#sorted[@]} -lt ${#CANDIDATES_JSON[@]} ]]; do
        min_rank=99
        min_idx=-1
        for i in "${!CANDIDATES_JSON[@]}"; do
            candidate="${CANDIDATES_JSON[$i]}"
            [[ -z ${candidate} ]] && continue
            rank=$(candidate_priority_rank "$(jq -r '.target_json.mode' <<< "${candidate}")")
            if [[ ${rank} -lt ${min_rank} ]]; then
                min_rank="${rank}"
                min_idx="${i}"
            fi
        done
        if [[ ${min_idx} -lt 0 ]]; then
            break
        fi
        sorted+=("${CANDIDATES_JSON[$min_idx]}")
        CANDIDATES_JSON[min_idx]=""
    done
    CANDIDATES_JSON=("${sorted[@]}")
}

#######################################
# write_detect_outputs: Write should_run, skip_reason, target_matrix
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file
#
# Arguments:
#   $1 - should_run (true|false)
#   $2 - skip_reason
#   $3 - target_matrix JSON array string
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function write_detect_outputs {
    local should_run="$1"
    local skip_reason="$2"
    local target_matrix_json="$3"

    {
        echo "should_run=${should_run}"
        echo "skip_reason=${skip_reason}"
        echo "delivery=${DELIVERY:-}"
        local delim
        delim="TARGET_MATRIX_$(openssl rand -hex 8)"
        echo "target_matrix<<${delim}"
        echo "${target_matrix_json}"
        echo "${delim}"
    } >> "${GITHUB_OUTPUT}"
}
