#!/bin/bash
#######################################
# Description: Sync all APM distribution artifacts from repository source-of-truth paths
#
# Usage: ./sync_apm_artifacts.sh [--check] [component...]
#   --check       Dry-run for bash-based sync scripts (pass-through)
#   component     skill-lib | validate-mirror | guidelines | all (default)
#
# Source-of-truth map (edit canonical files, then run this script):
#   skill-lib         → scripts/lib/
#   validate-mirror   → scripts/{shell-script,go,terraform}/
#   guidelines        → category-*.md under *-review skills (via Perl sync)
#
# After any component sync when .apm/packages/ changed:
#   apm install --update && apm audit --ci
#
# See CLAUDE.md § Edit Targets (edit targets and sync workflow) and .apm/AGENTS.md § Validation Scripts Mirror (path layout).
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHECK_MODE="false"
declare -a COMPONENTS=()

declare -a ALL_COMPONENTS=(
    skill-lib
    validate-mirror
    guidelines
)

#######################################
# show_usage: Display usage information
#######################################
function show_usage {
    cat << 'EOF'
Usage: sync_apm_artifacts.sh [--check] [component...]

Description:
    Run all APM artifact sync scripts from repository source-of-truth paths.

Components:
    skill-lib         scripts/lib/ → skill scripts/lib/ copies
    validate-mirror   scripts/<domain>/ → validation skill scripts/
    guidelines        category-*.md → instructions and common-checklist.md
    all               all of the above (default)

Options:
    --check    Dry-run where supported (skill-lib, validate-mirror)

Examples:
    ./sync_apm_artifacts.sh
    ./sync_apm_artifacts.sh --check validate-mirror
    ./sync_apm_artifacts.sh guidelines skill-lib
EOF
    exit 0
}

#######################################
# parse_arguments: Parse command line arguments
#######################################
function parse_arguments {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_usage
                ;;
            --check)
                CHECK_MODE="true"
                shift
                ;;
            skill-lib | validate-mirror | guidelines | all)
                COMPONENTS+=("$1")
                shift
                ;;
            *)
                echo "ERROR: Unknown argument: $1" >&2
                exit 1
                ;;
        esac
    done

    if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
        COMPONENTS=("all")
    fi
}

#######################################
# component_selected: Return whether a component should run
#######################################
function component_selected {
    local component="$1"
    local selected

    for selected in "${COMPONENTS[@]}"; do
        if [[ ${selected} == "all" || ${selected} == "${component}" ]]; then
            return 0
        fi
    done
    return 1
}

#######################################
# run_check_flag: Print --check when enabled
#######################################
function run_check_flag {
    if [[ ${CHECK_MODE} == "true" ]]; then
        printf '%s' "--check"
    fi
}

#######################################
# sync_skill_lib_component: Sync scripts/lib to skill copies
#######################################
function sync_skill_lib_component {
    echo "==> skill-lib"
    # shellcheck disable=SC2046
    bash "${SCRIPT_DIR}/sync_skill_lib.sh" $(run_check_flag)
}

#######################################
# sync_validate_mirror_component: Sync validation script mirrors
#######################################
function sync_validate_mirror_component {
    echo "==> validate-mirror"
    # shellcheck disable=SC2046
    bash "${SCRIPT_DIR}/sync_validate_mirror.sh" $(run_check_flag)
}

#######################################
# sync_guidelines_component: Regenerate instructions from category files
#######################################
function sync_guidelines_component {
    if [[ ${CHECK_MODE} == "true" ]]; then
        echo "==> guidelines (no --check mode; run without --check to apply)"
        return 0
    fi
    echo "==> guidelines"
    perl "${SCRIPT_DIR}/sync_guidelines_from_categories.pl"
}

#######################################
# main: Run selected sync components
#######################################
function main {
    local component

    parse_arguments "$@"

    for component in "${ALL_COMPONENTS[@]}"; do
        if ! component_selected "${component}"; then
            continue
        fi
        case "${component}" in
            skill-lib) sync_skill_lib_component ;;
            validate-mirror) sync_validate_mirror_component ;;
            guidelines) sync_guidelines_component ;;
            *)
                echo "ERROR: Unhandled component: ${component}" >&2
                exit 1
                ;;
        esac
    done

    echo ""
    echo "sync_apm_artifacts: done."
    if [[ ${CHECK_MODE} == "false" ]]; then
        echo "Next: apm install --update && apm audit --ci"
    fi
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
