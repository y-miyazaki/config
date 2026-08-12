#!/bin/bash
#######################################
# Description: GITHUB_OUTPUT helpers for loop-entity-detect
#
# Usage: source "${LIB_DIR}/outputs.sh"
#
# Output:
# - None (library file)
#
# Design Rules:
# - Multiline values use heredoc delimiters on GITHUB_OUTPUT
# - Detect outputs mirror loop-detect write_detect_outputs shape
#######################################

#######################################
# write_entity_detect_outputs: Write should_run, skip_reason, target_matrix
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file
#   DELIVERY - Platform delivery channel
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
function write_entity_detect_outputs {
    local should_run="$1"
    local skip_reason="$2"
    local target_matrix_json="$3"
    local delim

    {
        echo "should_run=${should_run}"
        echo "skip_reason=${skip_reason}"
        echo "delivery=${DELIVERY:-}"
        delim="TARGET_MATRIX_$(openssl rand -hex 8)"
        echo "target_matrix<<${delim}"
        echo "${target_matrix_json}"
        echo "${delim}"
    } >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
}

#######################################
# shrink_entity_matrix_for_output: Trim matrix payload for job output limits
#
# Globals:
#   None
#
# Arguments:
#   $1 - Full target_matrix JSON array string
#
# Outputs:
#   Compacted matrix JSON on stdout
#
# Returns:
#   0 on success
#
#######################################
function shrink_entity_matrix_for_output {
    local full_matrix="$1"

    jq -c '[.[] | {
      handoff_key: .handoff_key,
      prompt: .prompt,
      target_json: .target_json,
      verifier_context: ""
    }]' <<< "${full_matrix}"
}
