#!/bin/bash
#######################################
# Description:
#   Detect drift between APM package skill sources and installed skill mirrors.
#
# Usage:
#   bash check_apm_skill_install_drift.sh [--check]
#
# Design Rules:
#   - Source of truth: .apm/packages/common/.apm/skills/<skill>/
#   - Install targets: .claude/skills/, .agents/skills/ (when present)
#   - Exit 0 when in sync; exit 1 when drift is detected
#
# Output:
#   Drift lines to stdout
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

SOURCE_ROOT="${WORKSPACE_ROOT}/.apm/packages/common/.apm/skills"

declare -a LOOP_SKILLS=(
    changelog
    ci-sweeper
    docs-updater
    refactor
    tech-debt
)

declare -a INSTALL_TARGETS=(
    .claude/skills
    .agents/skills
)

declare -a DRIFT_LINES=()
DRIFT_COUNT=0

#######################################
# record_drift: Append a drift line and increment counter
#
# Globals:
#   DRIFT_LINES
#   DRIFT_COUNT
#
# Arguments:
#   $1 - Drift description
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function record_drift {
    DRIFT_LINES+=("$1")
    DRIFT_COUNT=$((DRIFT_COUNT + 1))
}

#######################################
# check_skill_target_drift: Compare one skill directory against an install target
#
# Globals:
#   SOURCE_ROOT
#   WORKSPACE_ROOT
#
# Arguments:
#   $1 - Skill name
#   $2 - Install target relative path (e.g. .claude/skills)
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function check_skill_target_drift {
    local skill="$1"
    local target_rel="$2"
    local source_dir="${SOURCE_ROOT}/${skill}"
    local target_dir="${WORKSPACE_ROOT}/${target_rel}/${skill}"
    local diff_output=""

    if [[ ! -d ${target_dir} ]]; then
        record_drift "Missing install mirror: ${target_rel}/${skill}"
        return 0
    fi

    if [[ ! -d ${source_dir} ]]; then
        record_drift "Missing APM source: .apm/packages/common/.apm/skills/${skill}"
        return 0
    fi

    diff_output="$(diff -rq "${source_dir}" "${target_dir}" 2> /dev/null || true)"
    if [[ -n ${diff_output} ]]; then
        while IFS= read -r line; do
            [[ -z ${line} ]] && continue
            record_drift "${line}"
        done <<< "${diff_output}"
    fi
}

#######################################
# main: Compare loop skills across install targets
#
# Globals:
#   LOOP_SKILLS
#   INSTALL_TARGETS
#   DRIFT_LINES
#   DRIFT_COUNT
#
# Arguments:
#   None
#
# Outputs:
#   Drift lines to stdout
#
# Returns:
#   0 when in sync; 1 when drift exists
#
#######################################
function main {
    local skill target

    if [[ ! -d ${SOURCE_ROOT} ]]; then
        echo "ERROR: APM skills root not found: ${SOURCE_ROOT}" >&2
        return 1
    fi

    for skill in "${LOOP_SKILLS[@]}"; do
        for target in "${INSTALL_TARGETS[@]}"; do
            check_skill_target_drift "${skill}" "${target}"
        done
    done

    if [[ ${DRIFT_COUNT} -gt 0 ]]; then
        printf '%s\n' "${DRIFT_LINES[@]}"
        echo "apm skill install drift: ${DRIFT_COUNT} issue(s); run: apm install --update" >&2
        return 1
    fi

    printf 'apm skill install drift: OK (%d skills × %d targets)\n' \
        "${#LOOP_SKILLS[@]}" "${#INSTALL_TARGETS[@]}"
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
