#!/bin/bash
#######################################
# install_terraform.sh
#
# Description:
#   Downloads shared lint configs and pre-commit configuration for Terraform projects
#   from the config distribution repository.
#
# Usage:
#   bash install_terraform.sh [target_dir]
#   bash <(curl -sL https://raw.githubusercontent.com/y-miyazaki/config/main/install_terraform.sh)
#
# Design Rules:
#   - Existing files are not overwritten (idempotent).
#   - All files are fetched from the main branch of y-miyazaki/config.
#
#######################################
set -euo pipefail
umask 027
export LC_ALL=C.UTF-8

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source repository raw URL base
readonly REPO_RAW_BASE="https://raw.githubusercontent.com/y-miyazaki/config/main"

# Mapping: destination filename -> source filename in repository
declare -A FILES=(
    [".pre-commit-config.yaml"]=".pre-commit-config-terraform.yaml"
    [".tflint.hcl"]=".tflint.hcl"
    [".markdownlint-cli2.yaml"]=".markdownlint-cli2.yaml"
    [".gitleaks.toml"]=".gitleaks.toml"
    [".commitlintrc.yaml"]=".commitlintrc.yaml"
    ["trivy.yaml"]="trivy.yaml"
)

#######################################
# cleanup: Remove temporary files on exit
#
# Arguments:
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
# Returns:
#   exit 0
#
#######################################
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [target_dir]

Install shared Terraform project configurations from y-miyazaki/config.

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
# Returns:
#   0 on success, 1 on download failure
#
#######################################
install_file() {
    local src="$1"
    local dest="$2"
    local url="${REPO_RAW_BASE}/${src}"

    if [[ -f "${dest}" ]] && [[ "${FORCE}" == "false" ]]; then
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

    echo "Installing Terraform project configurations to: ${TARGET_DIR}"

    local error_count=0
    for dest in "${!FILES[@]}"; do
        local src="${FILES[${dest}]}"
        local dest_path="${TARGET_DIR}/${dest}"

        if ! install_file "${src}" "${dest_path}"; then
            ((error_count++))
        fi
    done

    if [[ "${error_count}" -gt 0 ]]; then
        echo "" >&2
        echo "Completed with ${error_count} error(s)." >&2
        return 1
    fi

    echo ""
    echo "Done. Next steps:"
    echo "  1. Run 'terraform init' to initialize providers"
    echo "  2. Run 'tflint --init' to initialize tflint plugins"
    echo "  3. Run 'pre-commit install && pre-commit install --hook-type commit-msg'"
    echo "  4. Customize .tflint.hcl for your project if needed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
