#!/bin/bash
#######################################
# Description:
#   Derive and validate loop decisions from the single declared delivery value.
#
# Usage:
#   loop_action_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"
#   source "${loop_action_lib}/delivery.sh"
#   derive_pr_auto_merge "<level>" "<delivery>"
#   validate_delivery_value "<delivery>"
#
# Design Rules:
#   - Functions are pure: no globals are read or written
#   - Implemented deliveries: none, pr_create, pr_push
#   - Declared but unimplemented deliveries fail closed
#   - pr_push targets pull_request kinds only
#
# Output:
#   Error annotations on stderr when invalid
#######################################

#######################################
# delivery_requires_pr_number_skip: Decide whether the run must skip for a missing PR number
#
# Globals:
#   None
#
# Arguments:
#   $1 - delivery (none | pr_create | pr_push)
#   $2 - detect_pr_number (PR number | empty | 0)
#
# Outputs:
#   None
#
# Returns:
#   0 when the run must skip (pr_push without a PR number); 1 otherwise
#
#######################################
function delivery_requires_pr_number_skip {
    local delivery="${1:-}"
    local detect_pr_number="${2:-}"

    if [[ ${delivery} == "pr_push" && (-z ${detect_pr_number} || ${detect_pr_number} == "0") ]]; then
        return 0
    fi
    return 1
}

#######################################
# derive_pr_auto_merge: Derive whether the opened PR is auto-merged
#
# Globals:
#   None
#
# Arguments:
#   $1 - level (L1 | L2 | L3)
#   $2 - delivery (none | pr_create | pr_push)
#
# Outputs:
#   true when level is L3 and delivery is pr_create; false otherwise
#
# Returns:
#   0 always
#
#######################################
function derive_pr_auto_merge {
    local level="${1:-}"
    local delivery="${2:-}"

    if [[ ${level} == "L3" && ${delivery} == "pr_create" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

#######################################
# validate_delivery_detect_config: Validate delivery against branch caller detect settings
#
# Globals:
#   None
#
# Arguments:
#   $1 - delivery (none | pr_create | pr_push)
#   $2 - detect_pr_enabled (true | false)
#   $3 - detect_branch_match (pattern | empty)
#
# Outputs:
#   None
#
# Returns:
#   0 when valid; 1 when invalid
#
#######################################
function validate_delivery_detect_config {
    local delivery="${1:-}"
    local detect_pr_enabled="${2:-}"
    local detect_branch_match="${3:-}"

    if [[ ${delivery} == "pr_push" ]]; then
        if [[ ${detect_pr_enabled} != "true" ]]; then
            echo "::error::delivery pr_push requires detect_pr_enabled true" >&2
            return 1
        fi
        if [[ -n ${detect_branch_match} ]]; then
            echo "::error::delivery pr_push does not allow detect_branch_match (got: ${detect_branch_match})" >&2
            return 1
        fi
    fi

    if [[ -z ${detect_branch_match} && ${detect_pr_enabled} != "true" ]]; then
        echo "::error::detect_branch_match or detect_pr_enabled true is required" >&2
        return 1
    fi
    return 0
}

#######################################
# validate_delivery_target: Validate a target kind is allowed for the delivery
#
# Globals:
#   None
#
# Arguments:
#   $1 - delivery (none | pr_create | pr_push)
#   $2 - target_json (JSON with .mode integration|pull_request or .entity.kind issue|pr)
#
# Outputs:
#   None
#
# Returns:
#   0 when the target kind is allowed; 1 otherwise
#
#######################################
function validate_delivery_target {
    local delivery="${1:-}"
    local target_json="${2:-}"
    local kind

    kind="$(jq -r '.mode // .entity.kind // empty' <<< "${target_json}" 2> /dev/null)" || kind=""

    case "${kind}" in
        integration | pull_request | issue | pr) ;;
        *)
            echo "::error::delivery ${delivery}: unknown target kind (got: ${kind:-empty})" >&2
            return 1
            ;;
    esac

    case "${delivery}" in
        none | pr_create) return 0 ;;
        pr_push)
            if [[ ${kind} == "pull_request" ]]; then
                return 0
            fi
            echo "::error::delivery pr_push allows only pull_request targets (got: ${kind})" >&2
            return 1
            ;;
        *)
            echo "::error::delivery ${delivery}: cannot validate target kind ${kind}" >&2
            return 1
            ;;
    esac
}

#######################################
# validate_delivery_value: Validate the delivery value is implemented
#
# Globals:
#   None
#
# Arguments:
#   $1 - delivery (none | pr_create | pr_push)
#
# Outputs:
#   None
#
# Returns:
#   0 for none, pr_create, pr_push; 1 otherwise
#
#######################################
function validate_delivery_value {
    local delivery="${1:-}"

    case "${delivery}" in
        none | pr_create | pr_push) return 0 ;;
        issue_comment | issue_create | pr_review)
            echo "::error::delivery ${delivery} is not implemented" >&2
            return 1
            ;;
        *)
            echo "::error::delivery must be none|pr_create|pr_push (got: ${delivery:-empty})" >&2
            return 1
            ;;
    esac
}
