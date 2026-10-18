#!/bin/bash
#######################################
# Description:
#   Validate loop caller inputs keyed on level (delivery and agent edit contract).
#
# Usage:
#   loop_action_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"
#   source "${loop_action_lib}/validate_loop_write_contract.sh"
#   validate_loop_write_contract "<level>" "<delivery>" "<agent_edit_target>" \
#       "<agent_edit_allowlist>" "<agent_edit_denylist>" "<agent_unchanged_verdict>" \
#       "<finalize_script>" "<finalize_label_allowlist>"
#
# Design Rules:
#   - level is the primary key and is required: L1, L2, or L3
#   - L1: delivery must be none or issue_comment; agent_edit_target, agent_edit_allowlist,
#     agent_edit_denylist, agent_unchanged_verdict, and finalize_script must be empty
#   - L2/L3: delivery must be issue_comment, none, pr_create, pr_push, or pr_review
#     (validate_delivery_value)
#   - L2/L3: finalize_script is required for delivery issue_comment and pr_review
#   - All levels: finalize_label_allowlist is allowed only with delivery issue_comment
#     or pr_review
#   - L2/L3: agent_edit_target must be fix or report (required)
#   - L2/L3: agent_edit_allowlist is required; empty fails, ** means unrestricted
#   - L2/L3: agent_edit_denylist is optional; empty uses the default denylist
#   - L2/L3: agent_unchanged_verdict must be APPROVE or REJECT (required)
#   - Required values are enforced here, not by composite action required: true
#
# Output:
#   Error annotations on stderr when invalid
#######################################

_LOOP_WRITE_CONTRACT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./delivery.sh disable=SC1091
source "${_LOOP_WRITE_CONTRACT_LIB_DIR}/delivery.sh"

#######################################
# validate_finalize_label_allowlist: Validate finalize_label_allowlist against the delivery
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
#   0 when empty or delivery is issue_comment or pr_review; 1 otherwise
#
#######################################
function validate_finalize_label_allowlist {
    local delivery="${1:-}"
    local finalize_label_allowlist="${2:-}"

    if [[ -n ${finalize_label_allowlist} && ${delivery} != "issue_comment" && ${delivery} != "pr_review" ]]; then
        echo "::error::finalize_label_allowlist requires delivery issue_comment or pr_review (got: ${delivery:-empty})" >&2
        return 1
    fi
    return 0
}

#######################################
# validate_loop_write_contract: Validate loop inputs keyed on level
#
# Globals:
#   None
#
# Arguments:
#   $1 - level (L1 | L2 | L3)
#   $2 - delivery (issue_comment | none | pr_create | pr_push | pr_review; L1 allows only none or issue_comment)
#   $3 - agent_edit_target (fix | report; empty at L1)
#   $4 - agent_edit_allowlist (non-empty at L2/L3, ** for unrestricted; empty at L1)
#   $5 - agent_edit_denylist (any at L2/L3 including empty; empty at L1)
#   $6 - agent_unchanged_verdict (APPROVE | REJECT; empty at L1)
#   $7 - finalize_script (required for issue_comment and pr_review at L2/L3; empty at L1)
#   $8 - finalize_label_allowlist (newline-separated; only with issue_comment or pr_review)
#
# Outputs:
#   STDERR: ::error:: annotation naming the invalid field
#
# Returns:
#   0 when valid; 1 when invalid
#
#######################################
function validate_loop_write_contract {
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
            validate_finalize_label_allowlist "${delivery}" "${finalize_label_allowlist}" || return 1
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

    validate_delivery_value "${delivery}" || return 1

    if [[ (${delivery} == "issue_comment" || ${delivery} == "pr_review") && -z ${finalize_script} ]]; then
        echo "::error::finalize_script is required for delivery ${delivery}" >&2
        return 1
    fi
    validate_finalize_label_allowlist "${delivery}" "${finalize_label_allowlist}" || return 1

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

    return 0
}
