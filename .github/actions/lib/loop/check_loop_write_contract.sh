#!/bin/bash
#######################################
# Description:
#   Validate loop caller inputs keyed on level (delivery and agent edit contract).
#
# Usage:
#   loop_action_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"
#   source "${loop_action_lib}/check_loop_write_contract.sh"
#   check_loop_write_contract_all "<level>" "<delivery>" "<agent_edit_target>" \
#       "<agent_edit_allowlist>" "<agent_edit_denylist>" "<agent_unchanged_verdict>" \
#       "<finalize_script>" "<finalize_label_allowlist>"
#
# Design Rules:
#   - level is the primary key and is required: L1, L2, or L3
#   - L1: delivery must be none or issue_comment; agent_edit_target, agent_edit_allowlist,
#     agent_edit_denylist, agent_unchanged_verdict, and finalize_script must be empty
#   - L2/L3: delivery must be issue_comment, issue_create, none, pr_create, pr_push, or
#     pr_review (delivery_validate_value)
#   - L2/L3: finalize_script is required for delivery issue_comment, issue_create and pr_review
#   - issue_create (L2/L3 only): finalize_label_allowlist is required and
#     agent_unchanged_verdict must be REJECT (an APPROVE on no output would fail delivery forever)
#   - All levels: finalize_label_allowlist is allowed only with delivery issue_comment,
#     issue_create or pr_review
#   - L2/L3: agent_edit_target must be fix or report (required)
#   - L2/L3: agent_edit_allowlist is required; empty fails, ** means unrestricted
#   - L2/L3: agent_edit_denylist is optional; empty uses the default denylist
#   - L2/L3: agent_unchanged_verdict must be APPROVE or REJECT (required)
#   - check_loop_write_contract_agent_tool_denylist: agent_tool_denylist needs L2/L3 and agent_engine claude
#   - Required values are enforced here, not by composite action required: true
#
# Output:
#   Error annotations on stderr when invalid
#######################################

_LOOP_WRITE_CONTRACT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./delivery.sh disable=SC1091
source "${_LOOP_WRITE_CONTRACT_LIB_DIR}/delivery.sh"

#######################################
# check_loop_write_contract_finalize_label_allowlist: Validate finalize_label_allowlist against the delivery
#
# Globals:
#   None
#
# Arguments:
#   $1 - delivery (issue_comment | none | pr_create | pr_push | pr_review)
#   $2 - finalize_label_allowlist (newline-separated labels | empty)
#
# Outputs:
#   STDERR: ::error:: annotation when a non-empty allowlist is set for another delivery
#
# Returns:
#   0 when empty or delivery is issue_comment, issue_create or pr_review; 1 otherwise
#
#######################################
function check_loop_write_contract_finalize_label_allowlist {
    local delivery="${1:-}"
    local finalize_label_allowlist="${2:-}"

    if [[ -n ${finalize_label_allowlist} && ${delivery} != "issue_comment" && ${delivery} != "issue_create" && ${delivery} != "pr_review" ]]; then
        echo "::error::finalize_label_allowlist requires delivery issue_comment, issue_create or pr_review (got: ${delivery:-empty})" >&2
        return 1
    fi
    return 0
}

#######################################
# check_loop_write_contract_finalize_issue_limit: Validate finalize_issue_limit for delivery issue_create
#
# Globals:
#   None
#
# Arguments:
#   $1 - delivery
#   $2 - finalize_issue_limit (positive integer | empty for the default)
#
# Outputs:
#   STDERR: ::error:: annotation for an invalid value
#
# Returns:
#   0 when delivery is not issue_create, or the value is empty or a positive integer; 1 otherwise
#
#######################################
function check_loop_write_contract_finalize_issue_limit {
    local delivery="${1:-}"
    local finalize_issue_limit="${2:-}"

    [[ ${delivery} != "issue_create" || -z ${finalize_issue_limit} ]] && return 0
    if ! [[ ${finalize_issue_limit} =~ ^[1-9][0-9]*$ ]]; then
        echo "::error::finalize_issue_limit must be a positive integer (got: ${finalize_issue_limit})" >&2
        return 1
    fi
    return 0
}

#######################################
# check_loop_write_contract_agent_tool_denylist: Validate agent_tool_denylist against the level and engine
#
# Globals:
#   None
#
# Arguments:
#   $1 - level (L1 | L2 | L3)
#   $2 - agent_engine (claude | copilot | codex | cursor | empty)
#   $3 - agent_tool_denylist (newline-separated deny rules | empty)
#
# Outputs:
#   STDERR: ::error:: annotation when a non-empty denylist cannot be enforced
#
# Returns:
#   0 when empty, or when level is L2/L3 and the engine is claude; 1 otherwise
#
#######################################
function check_loop_write_contract_agent_tool_denylist {
    local level="${1:-}"
    local agent_engine="${2:-}"
    local agent_tool_denylist="${3:-}"

    [[ -z ${agent_tool_denylist} ]] && return 0
    if [[ ${level} == "L1" ]]; then
        echo "::error::agent_tool_denylist is not allowed at L1" >&2
        return 1
    fi
    if [[ ${agent_engine} != "claude" ]]; then
        echo "::error::agent_tool_denylist requires agent_engine claude (got: ${agent_engine:-empty}); other engines cannot enforce it" >&2
        return 1
    fi
    return 0
}

#######################################
# check_loop_write_contract_all: Validate loop inputs keyed on level
#
# Globals:
#   None
#
# Arguments:
#   $1 - level (L1 | L2 | L3)
#   $2 - delivery (issue_comment | issue_create | none | pr_create | pr_push | pr_review; L1 allows only none or issue_comment)
#   $3 - agent_edit_target (fix | report; empty at L1)
#   $4 - agent_edit_allowlist (non-empty at L2/L3, ** for unrestricted; empty at L1)
#   $5 - agent_edit_denylist (any at L2/L3 including empty; empty at L1)
#   $6 - agent_unchanged_verdict (APPROVE | REJECT; empty at L1)
#   $7 - finalize_script (required for issue_comment, issue_create and pr_review at L2/L3; empty at L1)
#   $8 - finalize_label_allowlist (newline-separated; required for issue_create; only with issue_comment, issue_create or pr_review)
#
# Outputs:
#   STDERR: ::error:: annotation naming the invalid field
#
# Returns:
#   0 when valid; 1 when invalid
#
#######################################
function check_loop_write_contract_all {
    local level="${1:-}"
    local delivery="${2:-}"
    local agent_edit_target="${3:-}"
    local agent_edit_allowlist="${4:-}"
    local agent_edit_denylist="${5:-}"
    local agent_unchanged_verdict="${6:-}"
    local finalize_script="${7:-}"
    local finalize_label_allowlist="${8:-}"

    case "${level}" in
        L1)
            if [[ ${delivery} != "none" && ${delivery} != "issue_comment" ]]; then
                echo "::error::delivery must be none or issue_comment at L1 (got: ${delivery:-empty})" >&2
                return 1
            fi
            if [[ -n ${agent_edit_target} ]]; then
                echo "::error::agent_edit_target is not allowed at L1 (L1 is read-only)" >&2
                return 1
            fi
            if [[ -n ${agent_edit_allowlist} ]]; then
                echo "::error::agent_edit_allowlist is not allowed at L1 (L1 is read-only)" >&2
                return 1
            fi
            if [[ -n ${agent_edit_denylist} ]]; then
                echo "::error::agent_edit_denylist is not allowed at L1 (L1 is read-only)" >&2
                return 1
            fi
            if [[ -n ${agent_unchanged_verdict} ]]; then
                echo "::error::agent_unchanged_verdict is not allowed at L1 (L1 is read-only)" >&2
                return 1
            fi
            if [[ -n ${finalize_script} ]]; then
                echo "::error::finalize_script is not allowed at L1" >&2
                return 1
            fi
            check_loop_write_contract_finalize_label_allowlist "${delivery}" "${finalize_label_allowlist}" || return 1
            return 0
            ;;
        L2 | L3) ;;
        "")
            echo "::error::level is required (L1, L2, or L3)" >&2
            return 1
            ;;
        *)
            echo "::error::level must be L1, L2, or L3 (got: ${level})" >&2
            return 1
            ;;
    esac

    delivery_validate_value "${delivery}" || return 1

    if [[ (${delivery} == "issue_comment" || ${delivery} == "issue_create" || ${delivery} == "pr_review") && -z ${finalize_script} ]]; then
        echo "::error::finalize_script is required for delivery ${delivery}" >&2
        return 1
    fi
    if [[ ${delivery} == "issue_create" && -z ${finalize_label_allowlist} ]]; then
        echo "::error::finalize_label_allowlist is required for delivery issue_create" >&2
        return 1
    fi
    check_loop_write_contract_finalize_label_allowlist "${delivery}" "${finalize_label_allowlist}" || return 1

    case "${agent_edit_target}" in
        fix | report) ;;
        "")
            echo "::error::agent_edit_target is required at ${level} (fix or report)" >&2
            return 1
            ;;
        *)
            echo "::error::agent_edit_target must be fix or report (got: ${agent_edit_target})" >&2
            return 1
            ;;
    esac

    if [[ -z ${agent_edit_allowlist} ]]; then
        echo "::error::agent_edit_allowlist is required at ${level} (use ** for unrestricted)" >&2
        return 1
    fi

    case "${agent_unchanged_verdict}" in
        APPROVE | REJECT) ;;
        "")
            echo "::error::agent_unchanged_verdict is required at ${level} (APPROVE or REJECT)" >&2
            return 1
            ;;
        *)
            echo "::error::agent_unchanged_verdict must be APPROVE or REJECT (got: ${agent_unchanged_verdict})" >&2
            return 1
            ;;
    esac
    if [[ ${delivery} == "issue_create" && ${agent_unchanged_verdict} != "REJECT" ]]; then
        echo "::error::agent_unchanged_verdict must be REJECT for delivery issue_create (got: ${agent_unchanged_verdict})" >&2
        return 1
    fi

    return 0
}
