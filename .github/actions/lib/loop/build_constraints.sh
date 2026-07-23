#!/bin/bash
#######################################
# Description:
#   Emit the ## Constraints block for loop implementer prompts.
#
# Usage:
#   source "${LOOP_ACTION_LIB_DIR}/build_constraints.sh"
#   emit_loop_constraints "<may_edit>" "<write_target>" "<allowlist>" "<report_file>"
#   emit_loop_constraints_from_level "<level>" "<allowlist>"  # deprecated
#
# Design Rules:
#   - Skills branch on may_edit and write_target — not on level or delivery
#   - Always emit may_edit when ## Constraints is present
#
# Output:
#   Constraints markdown on stdout
#######################################

#######################################
# emit_loop_constraints: Emit ## Constraints for loop implementer prompts
#
# Globals:
#   None
#
# Arguments:
#   $1 - may_edit (true | false, or empty with allowlist-only legacy)
#   $2 - write_target (fix | report | empty when may_edit false)
#   $3 - Comma-separated path allowlist (optional)
#   $4 - report_file path when write_target is report (optional)
#
# Outputs:
#   Constraints markdown on stdout
#
# Returns:
#   0 on success; 1 on invalid input
#
#######################################
function emit_loop_constraints {
    if [[ $# -eq 2 ]]; then
        if [[ ${1:-} =~ ^L[123]$ ]]; then
            emit_loop_constraints_from_level "$1" "$2"
            return $?
        fi
        if [[ -z ${1:-} && -n ${2:-} ]]; then
            emit_loop_constraints "false" "" "$2" ""
            return $?
        fi
    fi

    local may_edit="${1:-}"
    local write_target="${2:-}"
    local allowlist="${3:-}"
    local report_file="${4:-}"

    if [[ -z ${may_edit} && -z ${allowlist} ]]; then
        return 0
    fi

    if [[ -z ${may_edit} && -n ${allowlist} ]]; then
        may_edit="false"
    fi

    case "${may_edit}" in
        true | false) ;;
        *)
            echo "::error::may_edit must be true or false (got: ${may_edit})" >&2
            return 1
            ;;
    esac

    echo "## Constraints"
    echo "may_edit: ${may_edit}"

    if [[ ${may_edit} == "true" ]]; then
        case "${write_target}" in
            fix)
                echo "write_target: fix"
                echo "You MUST persist fixes within allowlist; survey-only output is insufficient when may_edit is true."
                ;;
            report)
                echo "write_target: report"
                if [[ -n ${report_file} ]]; then
                    echo "report_file: ${report_file}"
                fi
                echo "You MUST persist report_file within allowlist; source fixes outside allowlist are forbidden unless the caller verifier explicitly allows closed-set paths."
                ;;
            *)
                echo "::error::write_target must be fix or report when may_edit is true" >&2
                return 1
                ;;
        esac
    fi

    echo "Do not claim files were modified unless git would show real changes."
    if [[ -n ${allowlist} ]]; then
        echo "Allowed paths: ${allowlist}."
        echo "Do NOT modify any other files."
    fi
}

#######################################
# emit_loop_constraints_from_level: Deprecated level-based constraints shim
#
# Globals:
#   None
#
# Arguments:
#   $1 - Autonomy level (L1 | L2 | L3, or empty when allowlist-only)
#   $2 - Comma-separated path allowlist (optional)
#
# Outputs:
#   Constraints markdown on stdout
#
# Returns:
#   0 on success; 1 when level is non-empty and not L1/L2/L3
#
#######################################
function emit_loop_constraints_from_level {
    local level="${1:-}"
    local allowlist="${2:-}"
    local may_edit="false"

    if [[ -z ${level} && -z ${allowlist} ]]; then
        return 0
    fi

    echo "::warning::emit_loop_constraints_from_level is deprecated; pass may_edit and write_target explicitly" >&2

    if [[ -n ${level} ]]; then
        case "${level}" in
            L1) may_edit="false" ;;
            L2 | L3) may_edit="true" ;;
            *)
                echo "::error::Invalid level: ${level} (expected L1, L2, or L3)" >&2
                return 1
                ;;
        esac
    fi

    if [[ ${may_edit} == "true" ]]; then
        emit_loop_constraints "${may_edit}" "fix" "${allowlist}" ""
    else
        emit_loop_constraints "${may_edit}" "" "${allowlist}" ""
    fi
}

#######################################
# emit_loop_constraints_legacy: Backward-compatible alias for level shim
#
# Globals:
#   None
#
# Arguments:
#   $@ - Passed to emit_loop_constraints_from_level
#
# Outputs:
#   Constraints markdown on stdout
#
# Returns:
#   Exit status from emit_loop_constraints_from_level
#
#######################################
function emit_loop_constraints_legacy {
    emit_loop_constraints_from_level "$@"
}
