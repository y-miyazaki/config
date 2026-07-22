#!/bin/bash
#######################################
# Description:
#   Downloads shared lint configs and pre-commit configuration for Go projects
#   from the config distribution repository.
#
# Usage:
#   bash install_go.sh [target_dir]
#   bash <(curl -sL https://raw.githubusercontent.com/y-miyazaki/config/main/install_go.sh)
#
# Design Rules:
#   - Existing files are not overwritten (idempotent).
#   - All files are fetched from the main branch of y-miyazaki/config.
#
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
# Source repository raw URL base
readonly REPO_RAW_BASE="https://raw.githubusercontent.com/y-miyazaki/config/main"

# Mapping: destination filename:source filename in repository
# Uses colon-separated pairs for bash 3.2 compatibility (no associative arrays).
readonly FILE_PAIRS=(
    ".commitlintrc.yaml:.commitlintrc.yaml"
    ".editorconfig:.editorconfig"
    ".gitleaks.toml:.gitleaks.toml"
    ".golangci.yaml:.golangci.yaml"
    ".markdownlint-cli2.yaml:.markdownlint-cli2.yaml"
    ".pre-commit-config.yaml:.pre-commit-config-go.yaml"
    "trivy.yaml:trivy.yaml"
)

#######################################
# cleanup: Remove temporary files on exit
#
# Arguments:
#   None
#
# Global Variables:
#   None
#
# Returns:
#   None
#
#######################################
cleanup() {
    # No temporary files to clean in current implementation
    :
}
trap cleanup EXIT ERR INT TERM

#######################################
# show_usage: Display usage information
#
# Arguments:
#   None
#
# Global Variables:
#   None
#
# Returns:
#   exit 0
#
#######################################
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [target_dir]

Install shared Go project configurations from y-miyazaki/config.

Options:
  -h, --help    Show this help message
  -f, --force   Overwrite existing files

Arguments:
  target_dir    Target directory (default: current directory)

Examples:
  $(basename "$0")
  $(basename "$0") /path/to/project
  $(basename "$0") --force .
EOF
    exit 0
}

#######################################
# parse_arguments: Parse command line arguments
#
# Arguments:
#   $@ - command line arguments
#
# Global Variables:
#   TARGET_DIR - target directory for installation
#   FORCE - whether to overwrite existing files
#
# Returns:
#   0 on success, 1 on invalid arguments
#
#######################################
parse_arguments() {
    FORCE=false
    TARGET_DIR="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_usage
                ;;
            -f | --force)
                FORCE=true
                shift
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                show_usage
                ;;
            *)
                TARGET_DIR="$1"
                shift
                ;;
        esac
    done
}

#######################################
# install_file: Download a single file from the repository
#
# Arguments:
#   $1 - source filename in repository
#   $2 - destination file path
#
# Global Variables:
#   REPO_RAW_BASE - base URL for file downloads
#   FORCE - whether to overwrite existing files
#
# Returns:
#   0 on success, 1 on download failure
#
#######################################
install_file() {
    local src="$1"
    local dest="$2"
    local url="${REPO_RAW_BASE}/${src}"

    if [[ -f ${dest} ]] && [[ ${FORCE} == "false" ]]; then
        echo "  [skip] $(basename "${dest}") (already exists)" >&2
        return 0
    fi

    echo "  [install] $(basename "${dest}")" >&2
    if ! curl -sSfL "${url}" -o "${dest}"; then
        echo "  [error] Failed to download: ${url}" >&2
        return 1
    fi
}

#######################################
# main: Download and install configuration files
#
# Arguments:
#   $@ - command line arguments
#
# Global Variables:
#   TARGET_DIR - target directory for installation
#   FILE_PAIRS - array of destination:source file mappings
#
# Returns:
#   0 on success, 1 on failure
#
#######################################
main() {
    parse_arguments "$@"

    if ! command -v curl > /dev/null 2>&1; then
        echo "Error: curl is required but not installed." >&2
        exit 1
    fi

    echo "Installing Go project configurations to: ${TARGET_DIR}"

    local error_count=0
    for pair in "${FILE_PAIRS[@]}"; do
        local dest="${pair%%:*}"
        local src="${pair#*:}"
        local dest_path="${TARGET_DIR}/${dest}"

        if ! install_file "${src}" "${dest_path}"; then
            error_count=$((error_count + 1))
        fi
    done

    if [[ ${error_count} -gt 0 ]]; then
        echo "" >&2
        echo "Completed with ${error_count} error(s)." >&2
        return 1
    fi

    echo ""
    echo "Done. Next steps:"
    echo "  1. Run 'pre-commit install && pre-commit install --hook-type commit-msg'"
    echo "  2. Customize .golangci.yaml for your project if needed"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
