#!/usr/bin/env bash
# Description:
#   Validate may_edit × write_target × delivery × level combinations for loop callers.
#
# Usage:
#   source .../validate_loop_write_contract.sh
#   validate_loop_write_contract "<may_edit>" "<write_target>" "<delivery>" "<level>"

#######################################
# Validate loop write/delivery contract.
# Globals:
#   None
#
# Arguments:
#   $1 - may_edit (true | false)
#   $2 - write_target (fix | report | empty)
#   $3 - delivery (log | issue | notion | open_pr | none)
#   $4 - level (L1 | L2 | L3 | empty)
#
# Returns:
#   0 when valid; 1 when invalid
#######################################
validate_loop_write_contract() {
    local may_edit="${1:-}"
    local write_target="${2:-}"
    local delivery="${3:-}"
    local level="${4:-}"

    if [[ -z ${may_edit} ]]; then
        echo "::error::may_edit is required (true or false)" >&2
        return 1
    fi

    case "${may_edit}" in
        true | false) ;;
        *)
            echo "::error::may_edit must be true or false (got: ${may_edit})" >&2
            return 1
            ;;
    esac

    case "${delivery}" in
        log | issue | notion | open_pr | none) ;;
        *)
            echo "::error::delivery must be log|issue|notion|open_pr|none (got: ${delivery})" >&2
            return 1
            ;;
    esac

    if [[ -n ${level} ]]; then
        case "${level}" in
            L1 | L2 | L3) ;;
            *)
                echo "::error::level must be L1, L2, or L3 when set (got: ${level})" >&2
                return 1
                ;;
        esac
    fi

    if [[ ${may_edit} == "false" ]]; then
        if [[ -n ${write_target} ]]; then
            echo "::warning::write_target ignored when may_edit is false" >&2
        fi
        case "${delivery}" in
            log | issue | notion | none) return 0 ;;
            open_pr)
                echo "::error::invalid: may_edit false with delivery open_pr" >&2
                return 1
                ;;
        esac
    fi

    case "${write_target}" in
        fix | report) ;;
        "")
            echo "::error::write_target required when may_edit is true (fix or report)" >&2
            return 1
            ;;
        *)
            echo "::error::write_target must be fix or report (got: ${write_target})" >&2
            return 1
            ;;
    esac

    if [[ ${level} == "L1" ]]; then
        echo "::error::invalid: L1 with may_edit true (agent-l1 is read-only)" >&2
        return 1
    fi

    case "${delivery}" in
        open_pr | none) return 0 ;;
        log | issue | notion)
            echo "::error::invalid: may_edit true with delivery ${delivery}" >&2
            return 1
            ;;
    esac
}
