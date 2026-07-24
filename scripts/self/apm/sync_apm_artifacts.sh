#!/bin/bash
#######################################
# Description: Sync all APM distribution artifacts from repository source-of-truth paths
#
# Usage: ./sync_apm_artifacts.sh [--check] [--skip-install] [--skip-audit] [component...]
#   --check         Dry-run for bash-based sync scripts; skip apm install/audit
#   --skip-install  Apply sync but do not run apm install --update
#   --skip-audit    Apply sync/install but do not run apm audit --ci
#   component       skill-lib | validate-mirror | guidelines | loop-contract |
#                   apm-install | apm-skill-drift | apm-audit | all (default)
#
# Source-of-truth map (edit canonical files, then run this script):
#   skill-lib         → scripts/lib/
#   validate-mirror   → scripts/{shell-script,go,terraform}/
#   guidelines        → category-*.md under *-review skills (via Perl sync)
#   loop-contract     → loop PR body templates/envelopes under .apm/packages/
#   apm-install       → apm install --update (.apm/packages → agent install dirs)
#   apm-skill-drift   → loop skill sources vs installed mirrors (post-install check)
#   apm-audit         → apm audit --ci
#
# Default (no args): run all sync + install + drift check + audit.
#
# See CLAUDE.md § Edit Targets and .apm/AGENTS.md § Validation Scripts Mirror.
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHECK_MODE="false"
SKIP_INSTALL="false"
SKIP_AUDIT="false"
declare -a COMPONENTS=()

declare -a SYNC_COMPONENTS=(
    skill-lib
    validate-mirror
    guidelines
)

#######################################
# show_usage: Display usage information
#######################################
function show_usage {
    cat << 'EOF'
Usage: sync_apm_artifacts.sh [--check] [--skip-install] [--skip-audit] [component...]

Description:
    Sync APM artifacts, install package outputs, and verify integrity.

Components:
    skill-lib         scripts/lib/ → skill scripts/lib/ copies
    validate-mirror   scripts/<domain>/ → validation skill scripts/
    guidelines        category-*.md → instructions and common-checklist.md
    loop-contract     loop PR body templates/envelopes consistency checks
    apm-install       apm install --update (skipped with --check or --skip-install)
    apm-skill-drift   loop skill sources vs installed .claude/.agents mirrors
    apm-audit         apm audit --ci (skipped with --check or --skip-audit)
    all               all of the above (default)

Options:
    --check         Dry-run where supported; skip apm install and apm audit
    --skip-install  Do not run apm install --update after sync
    --skip-audit    Do not run apm audit --ci after install

Examples:
    ./sync_apm_artifacts.sh
    ./sync_apm_artifacts.sh --check
    ./sync_apm_artifacts.sh --skip-audit guidelines skill-lib
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
            --skip-install)
                SKIP_INSTALL="true"
                shift
                ;;
            --skip-audit)
                SKIP_AUDIT="true"
                shift
                ;;
            apm-audit | apm-install | apm-skill-drift | guidelines | loop-contract | skill-lib | validate-mirror | all)
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
#
# Globals:
#   COMPONENTS
#
# Arguments:
#   $1 - Component name
#
# Outputs:
#   None
#
# Returns:
#   0 when selected; 1 otherwise
#
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
# should_run_apm_install: Return whether apm install should run
#
# Globals:
#   CHECK_MODE
#   SKIP_INSTALL
#   COMPONENTS
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 when apm install should run; 1 otherwise
#
#######################################
function should_run_apm_install {
    local component

    if [[ ${CHECK_MODE} == "true" || ${SKIP_INSTALL} == "true" ]]; then
        return 1
    fi

    if component_selected "apm-install"; then
        return 0
    fi

    for component in "${SYNC_COMPONENTS[@]}"; do
        if component_selected "${component}"; then
            return 0
        fi
    done

    return 1
}

#######################################
# should_run_apm_audit: Return whether apm audit should run
#
# Globals:
#   CHECK_MODE
#   SKIP_AUDIT
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 when apm audit should run; 1 otherwise
#
#######################################
function should_run_apm_audit {
    if [[ ${CHECK_MODE} == "true" || ${SKIP_AUDIT} == "true" ]]; then
        return 1
    fi

    if component_selected "apm-audit"; then
        return 0
    fi

    should_run_apm_install
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
# check_loop_contract_component: Validate loop PR body skill contract files
#######################################
function check_loop_contract_component {
    echo "==> loop-contract"
    bash "${SCRIPT_DIR}/check_loop_pr_body_contract.sh"
}

#######################################
# check_apm_skill_drift_component: Detect APM skill install drift
#######################################
function check_apm_skill_drift_component {
    echo "==> apm-skill-drift"
    bash "${SCRIPT_DIR}/check_apm_skill_install_drift.sh"
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
# run_apm_install_component: Install APM package outputs into agent directories
#######################################
function run_apm_install_component {
    echo "==> apm-install"
    if ! command -v apm > /dev/null 2>&1; then
        echo "ERROR: apm command not found; install APM CLI before running sync_apm_artifacts.sh" >&2
        return 1
    fi
    apm install --update
}

#######################################
# run_apm_audit_component: Run APM integrity audit for CI
#######################################
function run_apm_audit_component {
    echo "==> apm-audit"
    if ! command -v apm > /dev/null 2>&1; then
        echo "ERROR: apm command not found; install APM CLI before running sync_apm_artifacts.sh" >&2
        return 1
    fi
    apm audit --ci
}

#######################################
# main: Run selected sync components in dependency order
#######################################
function main {
    local component

    parse_arguments "$@"

    for component in "${SYNC_COMPONENTS[@]}"; do
        if component_selected "${component}"; then
            case "${component}" in
                skill-lib) sync_skill_lib_component ;;
                validate-mirror) sync_validate_mirror_component ;;
                guidelines) sync_guidelines_component ;;
            esac
        fi
    done

    if component_selected "loop-contract"; then
        check_loop_contract_component
    fi

    if should_run_apm_install; then
        run_apm_install_component
    fi

    if component_selected "apm-skill-drift"; then
        check_apm_skill_drift_component
    fi

    if should_run_apm_audit; then
        run_apm_audit_component
    fi

    echo ""
    echo "sync_apm_artifacts: done."
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
