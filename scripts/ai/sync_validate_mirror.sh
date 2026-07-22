#!/bin/bash
#######################################
# Description: Sync validate.sh and paired helper scripts between scripts/<domain>/ and skill copies
#
# Usage: ./sync_validate_mirror.sh [--check] [--from-skill] [--domain <name>]
#   --check       Dry-run: report drift without copying (for CI)
#   --from-skill  Sync skill copy → scripts/<domain>/ (default: scripts → skill)
#   --domain      Limit to one domain: shell-script, go, or terraform
#
# Output:
# - Per-domain sync or drift status
# - Exit 0 if all in sync, exit 1 if drift detected (--check mode)
#
# Design Rules:
# - Source of truth for behavior: keep both sides aligned via this script
# - Default direction: scripts/<domain>/validate.sh → skill scripts/validate.sh
# - Path layout differences only (see .apm/AGENTS.md § Validation Scripts Mirror)
#
# Dependencies:
# - bash
# - diff
# - sed
# - mktemp
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SYNC_VALIDATE_MIRROR_ROOT overrides workspace root for fixture-isolated tests.
WORKSPACE_ROOT="${SYNC_VALIDATE_MIRROR_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

CHECK_MODE="false"
FROM_SKILL="false"
DOMAIN_FILTER=""

declare -a DOMAINS=(shell-script go terraform)

declare -A REPO_SCRIPTS_DIR=(
    ["shell-script"]="${WORKSPACE_ROOT}/scripts/shell-script"
    [go]="${WORKSPACE_ROOT}/scripts/go"
    [terraform]="${WORKSPACE_ROOT}/scripts/terraform"
)

declare -A SKILL_SCRIPTS_DIR=(
    ["shell-script"]="${WORKSPACE_ROOT}/.apm/packages/shell-script/.apm/skills/shell-script-validation/scripts"
    [go]="${WORKSPACE_ROOT}/.apm/packages/go/.apm/skills/go-validation/scripts"
    [terraform]="${WORKSPACE_ROOT}/.apm/packages/terraform/.apm/skills/terraform-validation/scripts"
)

declare -A DOMAIN_MIRROR_FILES=(
    ["shell-script"]="validate.sh fix_function_doc_order.sh"
    [go]="validate.sh"
    [terraform]="validate.sh"
)

declare -a TEMP_FILES=()

cleanup_temp_files() {
    local f
    for f in "${TEMP_FILES[@]}"; do
        rm -f "${f}"
    done
}
trap cleanup_temp_files EXIT

DRIFT_COUNT=0
SYNC_COUNT=0

#######################################
# show_usage: Display usage information
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Usage text to stdout
#
# Returns:
#   Exits with code 0
#######################################
function show_usage {
    cat << 'EOF'
Usage: sync_validate_mirror.sh [--check] [--from-skill] [--domain <name>]

Description:
    Keep scripts/<domain>/validate.sh (and shell-script fix_function_doc_order.sh) aligned with skill copies.

Options:
    --check       Dry-run: report drift without copying (for CI)
    --from-skill  Sync skill copy → scripts/<domain>/ (default: scripts → skill)
    --domain      Limit to shell-script, go, or terraform

Examples:
    ./sync_validate_mirror.sh
    ./sync_validate_mirror.sh --check
    ./sync_validate_mirror.sh --from-skill --domain go
EOF
    exit 0
}

#######################################
# parse_arguments: Parse command line arguments
#
# Globals:
#   CHECK_MODE, FROM_SKILL, DOMAIN_FILTER
#
# Arguments:
#   $@ - Command line arguments
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 on unknown argument or invalid domain
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
            --from-skill)
                FROM_SKILL="true"
                shift
                ;;
            --domain)
                if [[ $# -lt 2 ]]; then
                    echo "ERROR: --domain requires a value" >&2
                    exit 1
                fi
                DOMAIN_FILTER="$2"
                shift 2
                ;;
            *)
                echo "ERROR: Unknown argument: $1" >&2
                exit 1
                ;;
        esac
    done

    if [[ -n ${DOMAIN_FILTER} ]]; then
        case "${DOMAIN_FILTER}" in
            shell-script | go | terraform) ;;
            *)
                echo "ERROR: Invalid domain: ${DOMAIN_FILTER}" >&2
                exit 1
                ;;
        esac
    fi
}

#######################################
# check_domain: Compare repo and skill validate.sh after normalization
#
# Globals:
#   DOMAIN_MIRROR_FILES - Per-domain mirrored basenames
#   DRIFT_COUNT - Incremented on drift
#
# Arguments:
#   $1 - Domain name
#
# Outputs:
#   Drift details to stdout when files differ
#
# Returns:
#   None
#######################################
function check_domain {
    local domain="$1"
    local mirror_file

    for mirror_file in ${DOMAIN_MIRROR_FILES[${domain}]}; do
        check_mirror_file "${domain}" "${mirror_file}"
    done
}

#######################################
# check_mirror_file: Compare one mirrored file after normalization
#
# Globals:
#   DRIFT_COUNT
#
# Arguments:
#   $1 - Domain name
#   $2 - Mirror file basename
#
# Outputs:
#   Drift details to stdout when files differ
#
# Returns:
#   None
#######################################
function check_mirror_file {
    local domain="$1"
    local mirror_file="$2"
    local repo_file="${REPO_SCRIPTS_DIR[${domain}]}/${mirror_file}"
    local skill_file="${SKILL_SCRIPTS_DIR[${domain}]}/${mirror_file}"
    local normalized
    normalized="$(mktemp)"
    TEMP_FILES+=("${normalized}")
    local diff_output

    if [[ ! -f ${repo_file} ]]; then
        echo "  DRIFT: ${domain}/${mirror_file} (missing repo file: ${repo_file})"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
        return
    fi
    if [[ ! -f ${skill_file} ]]; then
        echo "  DRIFT: ${domain}/${mirror_file} (missing skill file: ${skill_file})"
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
        return
    fi

    transform_repo_to_skill "${domain}" "${mirror_file}" "${repo_file}" "${normalized}"
    if ! diff_output=$(diff -u "${skill_file}" "${normalized}" 2>&1); then
        echo "  DRIFT: ${domain}/${mirror_file}"
        printf '%s\n' "${diff_output}" | sed 's/^/    /'
        DRIFT_COUNT=$((DRIFT_COUNT + 1))
    fi
}

#######################################
# domain_selected: Return whether a domain should run
#
# Globals:
#   DOMAIN_FILTER
#
# Arguments:
#   $1 - Domain name
#
# Outputs:
#   None
#
# Returns:
#   0 when selected, 1 otherwise
#######################################
function domain_selected {
    local domain="$1"
    [[ -z ${DOMAIN_FILTER} || ${DOMAIN_FILTER} == "${domain}" ]]
}

#######################################
# sync_domain: Copy validate.sh with path layout transforms
#
# Globals:
#   DOMAIN_MIRROR_FILES - Per-domain mirrored basenames
#   FROM_SKILL - Sync direction flag
#   SYNC_COUNT - Incremented on sync
#
# Arguments:
#   $1 - Domain name
#
# Outputs:
#   Sync status to stdout
#
# Returns:
#   None
#######################################
function sync_domain {
    local domain="$1"
    local mirror_file

    for mirror_file in ${DOMAIN_MIRROR_FILES[${domain}]}; do
        sync_mirror_file "${domain}" "${mirror_file}"
    done
}

#######################################
# sync_mirror_file: Copy one mirrored file with path layout transforms
#
# Globals:
#   FROM_SKILL, SYNC_COUNT
#
# Arguments:
#   $1 - Domain name
#   $2 - Mirror file basename
#
# Outputs:
#   Sync status to stdout
#
# Returns:
#   Exits 1 when source file is missing
#######################################
function sync_mirror_file {
    local domain="$1"
    local mirror_file="$2"
    local repo_file="${REPO_SCRIPTS_DIR[${domain}]}/${mirror_file}"
    local skill_file="${SKILL_SCRIPTS_DIR[${domain}]}/${mirror_file}"
    local source_file
    local target_file
    local tmp_file
    tmp_file="$(mktemp)"
    TEMP_FILES+=("${tmp_file}")

    if [[ ${FROM_SKILL} == "true" ]]; then
        source_file="${skill_file}"
        target_file="${repo_file}"
        if [[ ! -f ${source_file} ]]; then
            echo "ERROR: Missing skill file: ${source_file}" >&2
            exit 1
        fi
        transform_skill_to_repo "${domain}" "${mirror_file}" "${source_file}" "${tmp_file}"
    else
        source_file="${repo_file}"
        target_file="${skill_file}"
        if [[ ! -f ${source_file} ]]; then
            echo "ERROR: Missing repo file: ${source_file}" >&2
            exit 1
        fi
        transform_repo_to_skill "${domain}" "${mirror_file}" "${source_file}" "${tmp_file}"
    fi

    mkdir -p "$(dirname "${target_file}")"
    cp "${tmp_file}" "${target_file}"
    echo "  SYNCED: ${domain}/${mirror_file} (${source_file} → ${target_file})"
    SYNC_COUNT=$((SYNC_COUNT + 1))
}

#######################################
# transform_repo_to_skill: Apply path layout transforms for skill copy
#
# Globals:
#   None
#
# Arguments:
#   $1 - Domain name
#   $2 - Mirror file basename
#   $3 - Input file path
#   $4 - Output file path
#
# Outputs:
#   Writes transformed content to output file
#
# Returns:
#   None
#######################################
function transform_repo_to_skill {
    local domain="$1"
    local mirror_file="$2"
    local input_file="$3"
    local output_file="$4"

    # shellcheck disable=SC2016  # sed patterns; ${SCRIPT_DIR} is literal text to match in validate.sh
    sed \
        -e 's|# shellcheck source=\.\./lib/all\.sh|# shellcheck source=./lib/all.sh|g' \
        -e 's|\${SCRIPT_DIR}/\.\./lib/all\.sh|\${SCRIPT_DIR}/lib/all.sh|g' \
        "${input_file}" > "${output_file}"

    if [[ ${domain} == "shell-script" && ${mirror_file} == "validate.sh" ]]; then
        # shellcheck disable=SC2016
        sed -i 's|WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/\.\./\.\." \&\& pwd)"|WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." \&\& pwd)"|g' \
            "${output_file}"
    fi
}

#######################################
# transform_skill_to_repo: Apply path layout transforms for repo copy
#
# Globals:
#   None
#
# Arguments:
#   $1 - Domain name
#   $2 - Mirror file basename
#   $3 - Input file path
#   $4 - Output file path
#
# Outputs:
#   Writes transformed content to output file
#
# Returns:
#   None
#######################################
function transform_skill_to_repo {
    local domain="$1"
    local mirror_file="$2"
    local input_file="$3"
    local output_file="$4"

    # shellcheck disable=SC2016  # sed patterns; ${SCRIPT_DIR} is literal text to match in validate.sh
    sed \
        -e 's|# shellcheck source=\./lib/all\.sh|# shellcheck source=../lib/all.sh|g' \
        -e 's|\${SCRIPT_DIR}/lib/all\.sh|\${SCRIPT_DIR}/../lib/all.sh|g' \
        "${input_file}" > "${output_file}"

    if [[ ${domain} == "shell-script" && ${mirror_file} == "validate.sh" ]]; then
        # shellcheck disable=SC2016
        sed -i 's|WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/\.\./\.\./\.\." \&\& pwd)"|WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." \&\& pwd)"|g' \
            "${output_file}"
    fi
}

#######################################
# main: Check or sync all configured domains
#
# Globals:
#   CHECK_MODE, DOMAINS
#
# Arguments:
#   $@ - Command line arguments
#
# Outputs:
#   Summary to stdout
#
# Returns:
#   0 if all in sync or sync succeeded, 1 if drift in check mode
#######################################
function main {
    local domain

    parse_arguments "$@"

    if [[ ${CHECK_MODE} == "true" ]]; then
        echo "Checking validation mirror drift..."
        for domain in "${DOMAINS[@]}"; do
            if domain_selected "${domain}"; then
                check_domain "${domain}"
            fi
        done
        echo ""
        if [[ ${DRIFT_COUNT} -gt 0 ]]; then
            echo "FAIL: ${DRIFT_COUNT} mirrored file(s) have drifted. Run: bash scripts/ai/sync_validate_mirror.sh"
            exit 1
        fi
        echo "OK: All validation mirrors are in sync."
        exit 0
    fi

    if [[ ${FROM_SKILL} == "true" ]]; then
        echo "Syncing skill copies → scripts/<domain>/..."
    else
        echo "Syncing scripts/<domain>/ → skill copies..."
    fi
    for domain in "${DOMAINS[@]}"; do
        if domain_selected "${domain}"; then
            sync_domain "${domain}"
        fi
    done
    echo ""
    echo "Done: ${SYNC_COUNT} file(s) synced."
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
