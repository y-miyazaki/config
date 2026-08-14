#!/bin/bash
#######################################
# Description:
#   Resolve an APM skill source directory across .apm/packages/*.
#
# Usage:
#   source apm_skill_root.sh
#   apm_skill_root <skill-name>
#
# Design Rules:
#   - Skills live under .apm/packages/<pkg>/.apm/skills/<skill>/
#   - Skill names are unique across packages
#######################################

# apm_skill_root: Print the source directory for a skill name
#
# Globals:
#   WORKSPACE_ROOT - repository root (required)
#
# Arguments:
#   $1 - Skill name (kebab-case)
#
# Outputs:
#   Absolute skill directory on stdout
#
# Returns:
#   0 when found; 1 when missing or duplicated
#
function apm_skill_root {
    local skill="$1"
    local packages_root="${WORKSPACE_ROOT}/.apm/packages"
    local found=()
    local pkg_dir skill_dir

    if [[ -z ${skill} ]]; then
        echo "ERROR: skill name required" >&2
        return 1
    fi
    if [[ -z ${WORKSPACE_ROOT:-} ]]; then
        echo "ERROR: WORKSPACE_ROOT is not set" >&2
        return 1
    fi

    shopt -s nullglob
    for pkg_dir in "${packages_root}"/*/; do
        skill_dir="${pkg_dir}.apm/skills/${skill}"
        if [[ -d ${skill_dir} ]]; then
            found+=("${skill_dir}")
        fi
    done
    shopt -u nullglob

    if [[ ${#found[@]} -eq 0 ]]; then
        echo "ERROR: skill not found: ${skill}" >&2
        return 1
    fi
    if [[ ${#found[@]} -gt 1 ]]; then
        echo "ERROR: skill name is not unique: ${skill}" >&2
        printf '%s\n' "${found[@]}" >&2
        return 1
    fi
    printf '%s\n' "${found[0]}"
}
