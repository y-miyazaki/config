#!/usr/bin/env bash
# Description:
#   Emit the ## Constraints block for loop implementer prompts.
#
# Usage:
#   source .../build_constraints.sh
#   emit_loop_constraints "<level>" "<allowlist>"
#
# Design Rules:
#   - Skills branch on may_edit only; level maps to may_edit at injection time
#   - Always emit may_edit when ## Constraints is present

#######################################
# Emit ## Constraints for loop implementer prompts.
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
#######################################
emit_loop_constraints() {
    local level="${1:-}"
    local allowlist="${2:-}"

    if [[ -z ${level} && -z ${allowlist} ]]; then
        return 0
    fi

    local may_edit="false"
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

    echo "## Constraints"
    echo "may_edit: ${may_edit}"
    if [[ ${may_edit} == "true" ]]; then
        echo "You MUST persist edits to disk in the worktree; a report alone is not sufficient when may_edit is true."
    fi
    echo "Do not claim files were modified unless git would show real changes."
    if [[ -n ${allowlist} ]]; then
        echo "Allowed paths: ${allowlist}."
        echo "Do NOT modify any other files."
    fi
}
