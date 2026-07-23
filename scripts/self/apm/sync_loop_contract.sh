#!/bin/bash
#######################################
# Description: Sync portable loop contract files to loop skill references/
#
# Usage: ./sync_loop_contract.sh [--check]
#   --check    Dry-run: report drift without copying (for CI)
#
# Source of truth:
#   docs/explanation/loop-engineering/portable/common-loop-*.md
#
# Targets:
#   .apm/packages/common/.apm/skills/{changelog,ci-sweeper,docs-updater,refactor,tech-debt}/references/
#
# Dependencies:
# - bash
# - diff
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${SYNC_LOOP_CONTRACT_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

CHECK_MODE="false"
SOURCE_DIR="${WORKSPACE_ROOT}/docs/explanation/loop-engineering/portable"
PACKAGES_SKILL_ROOT="${WORKSPACE_ROOT}/.apm/packages/common/.apm/skills"

declare -a CONTRACT_FILES=(
    common-loop-triage-format.md
    common-loop-pr-body-contract.md
)

declare -a TARGET_SKILLS=(
    changelog
    ci-sweeper
    docs-updater
    refactor
    tech-debt
)

DRIFT_COUNT=0
SYNC_COUNT=0

#######################################
# show_usage: Display usage information
#######################################
function show_usage {
    cat << 'EOF'
Usage: sync_loop_contract.sh [--check]

Description:
    Sync portable loop contract markdown from docs/explanation/loop-engineering/portable/
    to loop skill references/ directories.

Options:
    --check    Dry-run: report drift without copying (for CI)

Examples:
    ./sync_loop_contract.sh
    ./sync_loop_contract.sh --check
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
            *)
                echo "ERROR: Unknown argument: $1" >&2
                exit 1
                ;;
        esac
    done
}

#######################################
# check_contract_file: Compare one contract file for one skill
#######################################
function check_contract_file {
    local skill="$1"
    local contract_file="$2"
    local source_file="${SOURCE_DIR}/${contract_file}"
    local target_file="${PACKAGES_SKILL_ROOT}/${skill}/references/${contract_file}"

    if [[ ! -f ${source_file} ]]; then
        echo "  DRIFT: missing source file: ${source_file}"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
        return
    fi
    if [[ ! -f ${target_file} ]]; then
        echo "  DRIFT: ${skill}/${contract_file} (missing target: ${target_file})"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
        return
    fi
    if ! diff -q "${source_file}" "${target_file}" > /dev/null 2>&1; then
        echo "  DRIFT: ${skill}/${contract_file}"
        diff -u "${target_file}" "${source_file}" | sed 's/^/    /' || true
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
    fi
}

#######################################
# sync_contract_file: Copy one contract file to one skill
#######################################
function sync_contract_file {
    local skill="$1"
    local contract_file="$2"
    local source_file="${SOURCE_DIR}/${contract_file}"
    local target_file="${PACKAGES_SKILL_ROOT}/${skill}/references/${contract_file}"

    if [[ ! -f ${source_file} ]]; then
        echo "ERROR: Missing source file: ${source_file}" >&2
        exit 1
    fi
    mkdir -p "$(dirname "${target_file}")"
    cp "${source_file}" "${target_file}"
    echo "  SYNCED: ${skill}/${contract_file}"
    SYNC_COUNT=$((SYNC_COUNT + 1))
}

#######################################
# main: Check or sync all loop contract mirrors
#######################################
function main {
    local skill contract_file

    parse_arguments "$@"

    if [[ ${CHECK_MODE} == "true" ]]; then
        echo "Checking loop contract drift..."
        for skill in "${TARGET_SKILLS[@]}"; do
            for contract_file in "${CONTRACT_FILES[@]}"; do
                check_contract_file "${skill}" "${contract_file}"
            done
        done
        echo ""
        if [[ ${DRIFT_COUNT} -gt 0 ]]; then
            echo "FAIL: ${DRIFT_COUNT} loop contract file(s) have drifted. Run: bash scripts/self/apm/sync_loop_contract.sh"
            exit 1
        fi
        echo "OK: All loop contract mirrors are in sync."
        exit 0
    fi

    echo "Syncing docs/explanation/loop-engineering/portable/ → skill references/..."
    for skill in "${TARGET_SKILLS[@]}"; do
        for contract_file in "${CONTRACT_FILES[@]}"; do
            sync_contract_file "${skill}" "${contract_file}"
        done
    done
    echo ""
    echo "Done: ${SYNC_COUNT} file(s) synced."
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
