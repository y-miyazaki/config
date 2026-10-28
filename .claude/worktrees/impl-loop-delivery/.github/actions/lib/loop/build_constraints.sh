#!/bin/bash
#######################################
# Description:
#   Emit the ## Constraints block for loop maker prompts.
#
# Usage:
#   loop_action_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"
#   source "${loop_action_lib}/build_constraints.sh"
#   emit_loop_constraints "<level>" "<agent_edit_target>" "<agent_edit_allowlist>" "<agent_report_file>"
#
# Design Rules:
#   - Skills branch on agent_edit_allowed and agent_edit_target — not on level or delivery
#   - agent_edit_allowed is derived from level (L1 false; L2/L3 true)
#   - Always emit agent_edit_allowed
#
# Output:
#   Constraints markdown on stdout
#######################################

#######################################
# emit_loop_constraints: Emit ## Constraints for loop maker prompts
#
# Globals:
#   None
#
# Arguments:
#   $1 - Autonomy level (L1 | L2 | L3); agent_edit_allowed is derived from it
#   $2 - agent_edit_target (fix | report; ignored for L1)
#   $3 - agent_edit_allowlist, comma-separated paths (optional; "**" is treated as empty)
#   $4 - agent_report_file path when agent_edit_target is report (optional)
#
# Outputs:
#   Constraints markdown on stdout
#
# Returns:
#   0 on success; 1 on invalid level or agent_edit_target
#
#######################################
function emit_loop_constraints {
    local level="${1:-}"
    local agent_edit_target="${2:-}"
    local allowlist="${3:-}"
    local agent_report_file="${4:-}"
    local agent_edit_allowed

    case "${level}" in
        L1) agent_edit_allowed="false" ;;
        L2 | L3) agent_edit_allowed="true" ;;
        *)
            echo "::error::Invalid level: ${level} (expected L1, L2, or L3)" >&2
            return 1
            ;;
    esac

    if [[ ${allowlist} == "**" ]]; then
        allowlist=""
    fi

    echo "## Constraints"
    echo "agent_edit_allowed: ${agent_edit_allowed}"

    if [[ ${agent_edit_allowed} == "true" ]]; then
        case "${agent_edit_target}" in
            fix)
                echo "agent_edit_target: fix"
                echo "You MUST persist fixes within allowlist; survey-only output is insufficient when agent_edit_allowed is true."
                ;;
            report)
                echo "agent_edit_target: report"
                if [[ -n ${agent_report_file} ]]; then
                    echo "agent_report_file: ${agent_report_file}"
                fi
                echo "You MUST persist agent_report_file within allowlist; source fixes outside allowlist are forbidden unless the caller checker explicitly allows closed-set paths."
                ;;
            *)
                echo "::error::agent_edit_target must be fix or report when agent_edit_allowed is true" >&2
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
