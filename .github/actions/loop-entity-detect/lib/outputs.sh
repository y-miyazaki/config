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
# - A detect-script skip is published as skip_reason domain:<slug> plus a one-line, redacted skip_detail
#######################################

_ENTITY_OUTPUTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f redact_sensitive_text > /dev/null 2>&1; then
    # shellcheck source=../../lib/loop/redact.sh disable=SC1091
    source "${_ENTITY_OUTPUTS_LIB_DIR}/../../lib/loop/redact.sh"
fi
if ! declare -f derive_pr_auto_merge > /dev/null 2>&1; then
    # shellcheck source=../../lib/loop/delivery.sh disable=SC1091
    source "${_ENTITY_OUTPUTS_LIB_DIR}/../../lib/loop/delivery.sh"
fi

#######################################
# resolve_entity_skip_detail: Build the one-line, redacted detail of a detect-script skip
#
# Globals:
#   None
#
# Arguments:
#   $1 - Path to the detect JSON file
#
# Outputs:
#   The detect message on one line, redacted and cut to 300 characters (empty when absent)
#
# Returns:
#   0 always
#
#######################################
function resolve_entity_skip_detail {
    local detect_file="$1"
    local message

    message="$(jq -r '(.message // "") | tostring' "${detect_file}" 2> /dev/null || true)"
    message="$(printf '%s' "${message}" | tr '\r\n' '  ')"
    message="$(redact_sensitive_text "${message}")"
    printf '%s' "${message:0:300}"
}

#######################################
# resolve_entity_skip_reason: Build the skip_reason of a detect-script skip
#
# Globals:
#   None
#
# Arguments:
#   $1 - Path to the detect JSON file
#
# Outputs:
#   domain:<slug>; slug is the detect JSON skip_reason when it matches ^[a-z0-9_]+$, else detect
#
# Returns:
#   0 always
#
#######################################
function resolve_entity_skip_reason {
    local detect_file="$1"
    local slug

    slug="$(jq -r '(.skip_reason // .result.skip_reason // "") | tostring' "${detect_file}" 2> /dev/null || true)"
    if [[ ! ${slug} =~ ^[a-z0-9_]+$ ]]; then
        slug="detect"
    fi
    printf 'domain:%s' "${slug}"
}

#######################################
# write_entity_detect_outputs: Write should_run, skip_reason, skip_detail, delivery, pr_auto_merge, target_matrix
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file
#   DELIVERY, LEVEL - Read; pr_auto_merge is derived from them (derive_pr_auto_merge)
#
# Arguments:
#   $1 - should_run (true|false)
#   $2 - skip_reason
#   $3 - target_matrix JSON array string
#   $4 - skip_detail (optional, one line)
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
    local skip_detail="${4:-}"
    local delim

    {
        echo "should_run=${should_run}"
        echo "skip_reason=${skip_reason}"
        echo "skip_detail=${skip_detail}"
        echo "delivery=${DELIVERY:-}"
        echo "pr_auto_merge=$(derive_pr_auto_merge "${LEVEL:-}" "${DELIVERY:-}")"
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
      prompt: .prompt,
      target_json: .target_json,
      verifier_context: ""
    }]' <<< "${full_matrix}"
}
